/* WinSock implementation of the renderer TCP client for local testing. */

#ifdef PLATFORM_WINDOWS

#include <stdio.h>
#include <string.h>
#include <winsock2.h>
#include <ws2tcpip.h>

#include "server.h"

static SOCKET g_server_fd = INVALID_SOCKET;
static int g_target_port = 0;
static ULONGLONG g_last_retry_ms = 0;
static int g_winsock_ready = 0;

#define RECV_BUF_SIZE 512
static uint8_t g_recv_buf[RECV_BUF_SIZE];
static int g_recv_len = 0;
static int g_ready_sent = 0;
static int g_frame_ready_sent = 0;
static int g_peer_closed = 0;

static void close_socket(void) {
    if (g_server_fd != INVALID_SOCKET) {
        closesocket(g_server_fd);
        g_server_fd = INVALID_SOCKET;
    }
}

static void set_nonblocking(SOCKET fd) {
    u_long enabled = 1;
    ioctlsocket(fd, FIONBIO, &enabled);
}

static void send_event(uint8_t event_id) {
    uint8_t packet[CR_PKT_SIZE];
    if (g_server_fd == INVALID_SOCKET) return;
    memset(packet, 0, sizeof(packet));
    packet[0] = event_id;
    (void)send(g_server_fd, (const char *)packet, CR_PKT_SIZE, 0);
}

static SOCKET try_connect(void) {
    SOCKET fd;
    struct sockaddr_in addr;
    int rc;
    int error;
    int one = 1;

    fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd == INVALID_SOCKET) return INVALID_SOCKET;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const char *)&one, sizeof(one));
    set_nonblocking(fd);

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((u_short)g_target_port);

    rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc == SOCKET_ERROR) {
        fd_set write_set;
        struct timeval timeout;
        int so_error = 0;
        int so_error_len = sizeof(so_error);

        error = WSAGetLastError();
        if (error != WSAEWOULDBLOCK && error != WSAEINPROGRESS
                && error != WSAEINVAL) {
            closesocket(fd);
            return INVALID_SOCKET;
        }

        FD_ZERO(&write_set);
        FD_SET(fd, &write_set);
        timeout.tv_sec = 0;
        timeout.tv_usec = 300 * 1000;
        rc = select(0, NULL, &write_set, NULL, &timeout);
        if (rc <= 0 || getsockopt(fd, SOL_SOCKET, SO_ERROR,
                (char *)&so_error, &so_error_len) != 0 || so_error != 0) {
            closesocket(fd);
            return INVALID_SOCKET;
        }
    }

    return fd;
}

int cr_server_peer_closed(void) {
    return g_peer_closed;
}

int cr_server_init(int port) {
    WSADATA data;
    g_target_port = port;
    g_peer_closed = 0;

    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
        fprintf(stderr, "server_windows: WSAStartup failed\n");
        return -1;
    }
    g_winsock_ready = 1;

    g_server_fd = try_connect();
    if (g_server_fd != INVALID_SOCKET)
        fprintf(stderr, "server_windows: connected to 127.0.0.1:%d\n", port);
    else
        fprintf(stderr, "server_windows: :%d not listening, will retry\n", port);
    g_recv_len = 0;
    return 0;
}

void cr_server_poll(void) {
    if (g_server_fd == INVALID_SOCKET && g_target_port > 0) {
        ULONGLONG now = GetTickCount64();
        if (now - g_last_retry_ms >= 1000) {
            g_last_retry_ms = now;
            g_server_fd = try_connect();
            if (g_server_fd != INVALID_SOCKET) {
                fprintf(stderr, "server_windows: connected to 127.0.0.1:%d\n",
                        g_target_port);
                g_recv_len = 0;
                if (g_ready_sent) send_event(EVT_READY);
                if (g_frame_ready_sent) send_event(EVT_FRAME_READY);
            }
        }
    }

    if (g_server_fd != INVALID_SOCKET && g_recv_len < RECV_BUF_SIZE) {
        int n = recv(g_server_fd, (char *)g_recv_buf + g_recv_len,
                     RECV_BUF_SIZE - g_recv_len, 0);
        if (n > 0) {
            g_recv_len += n;
        } else if (n == 0) {
            fprintf(stderr, "server_windows: peer closed, requesting exit\n");
            close_socket();
            g_recv_len = 0;
            g_peer_closed = 1;
        } else {
            int error = WSAGetLastError();
            if (error != WSAEWOULDBLOCK) {
                fprintf(stderr, "server_windows: recv error %d\n", error);
                close_socket();
                g_recv_len = 0;
            }
        }
    }
}

int cr_server_read_cmd(cr_cmd_t *out) {
    if (g_recv_len < CR_PKT_SIZE) return 0;
    memcpy(out, g_recv_buf, CR_PKT_SIZE);
    g_recv_len -= CR_PKT_SIZE;
    if (g_recv_len > 0)
        memmove(g_recv_buf, g_recv_buf + CR_PKT_SIZE, g_recv_len);
    return 1;
}

void cr_server_send_heartbeat(void) {
    send_event(EVT_HEARTBEAT);
}

void cr_server_mark_ready(void) {
    g_ready_sent = 1;
    send_event(EVT_READY);
}

void cr_server_mark_frame_ready(void) {
    g_frame_ready_sent = 1;
    send_event(EVT_FRAME_READY);
}

void cr_server_shutdown(void) {
    close_socket();
    g_recv_len = 0;
    if (g_winsock_ready) {
        WSACleanup();
        g_winsock_ready = 0;
    }
    fprintf(stderr, "server_windows: shutdown\n");
}

#endif /* PLATFORM_WINDOWS */
