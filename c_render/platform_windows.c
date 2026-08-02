/* Windows local-preview backend -- GLFW + OpenGL 3.3 compatibility. */

#ifdef PLATFORM_WINDOWS

#include <stdio.h>
#include <stdlib.h>

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#define GLAD_GL_IMPLEMENTATION
#include "gl_compat.h"

#include "platform.h"
#include "protocol.h"

static GLFWwindow *g_window = NULL;
static int g_key_taps[CR_KEY_MAX] = {0};

static void error_callback(int error, const char *description) {
    fprintf(stderr, "GLFW error %d: %s\n", error, description);
}

static void key_callback(GLFWwindow *window, int key, int scancode,
                         int action, int mods) {
    (void)scancode;
    (void)mods;
    if (action != GLFW_PRESS) return;

    if (key == GLFW_KEY_ESCAPE)
        glfwSetWindowShouldClose(window, GLFW_TRUE);
    else if (key == GLFW_KEY_LEFT)
        g_key_taps[CR_KEY_LEFT] = 1;
    else if (key == GLFW_KEY_RIGHT)
        g_key_taps[CR_KEY_RIGHT] = 1;
    else if (key == GLFW_KEY_UP)
        g_key_taps[CR_KEY_UP] = 1;
    else if (key == GLFW_KEY_DOWN)
        g_key_taps[CR_KEY_DOWN] = 1;
    else if (key == GLFW_KEY_P)
        g_key_taps[CR_KEY_P] = 1;
    else if (key == GLFW_KEY_SPACE)
        g_key_taps[CR_KEY_SPACE] = 1;
    else if (key == GLFW_KEY_S)
        g_key_taps[CR_KEY_S] = 1;
    else if (key == GLFW_KEY_A)
        g_key_taps[CR_KEY_A] = 1;
    else if (key == GLFW_KEY_LEFT_BRACKET)
        g_key_taps[CR_KEY_LBRACKET] = 1;
    else if (key == GLFW_KEY_RIGHT_BRACKET)
        g_key_taps[CR_KEY_RBRACKET] = 1;
    else if (key == GLFW_KEY_D)
        g_key_taps[CR_KEY_D] = 1;
}

int platform_init(int width, int height) {
    int scale = 2;
    const char *scale_env = getenv("CR_LOCAL_SCALE");
    if (scale_env && *scale_env) {
        int requested = atoi(scale_env);
        if (requested >= 1 && requested <= 4) scale = requested;
    }

    glfwSetErrorCallback(error_callback);
    if (!glfwInit()) {
        fprintf(stderr, "platform_windows: glfwInit failed\n");
        return -1;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
    glfwWindowHint(GLFW_SAMPLES, 0);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_TRUE);
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);

    g_window = glfwCreateWindow(width * scale, height * scale,
                                "CarPlay RGI local renderer", NULL, NULL);
    if (!g_window) {
        fprintf(stderr, "platform_windows: window creation failed\n");
        glfwTerminate();
        return -1;
    }

    glfwSetKeyCallback(g_window, key_callback);
    glfwMakeContextCurrent(g_window);
    glfwSwapInterval(0);

    if (!gladLoadGL((GLADloadfunc)glfwGetProcAddress)) {
        fprintf(stderr, "platform_windows: gladLoadGL failed\n");
        glfwDestroyWindow(g_window);
        g_window = NULL;
        glfwTerminate();
        return -1;
    }

    fprintf(stderr, "platform_windows: GL %s, scale=%d\n",
            glGetString(GL_VERSION), scale);
    return 0;
}

void platform_swap(void) {
    if (g_window) glfwSwapBuffers(g_window);
}

void platform_poll(void) {
    glfwPollEvents();
}

int platform_should_close(void) {
    return g_window ? glfwWindowShouldClose(g_window) : 1;
}

void platform_shutdown(void) {
    if (g_window) {
        glfwDestroyWindow(g_window);
        g_window = NULL;
    }
    glfwTerminate();
    fprintf(stderr, "platform_windows: shutdown\n");
}

void platform_get_framebuffer_size(int *width, int *height) {
    if (g_window) glfwGetFramebufferSize(g_window, width, height);
}

void platform_get_routing_ids(int *display_id, int *context_id,
                              int *displayable_id) {
    if (display_id) *display_id = CR_DISPLAY_ID;
    if (context_id) *context_id = CR_CONTEXT_ID;
    if (displayable_id) *displayable_id = CR_DISPLAYABLE_ID;
}

void platform_ensure_focus(void) {}
void platform_check_and_recover_window(void) {}
void platform_release_displayable(void) {}

void platform_set_preview_visible(int visible) {
    if (!g_window) return;
    if (visible)
        glfwShowWindow(g_window);
    else
        glfwHideWindow(g_window);
}

int platform_key_tap(int key) {
    int value;
    if (key < 0 || key >= CR_KEY_MAX) return 0;
    value = g_key_taps[key];
    g_key_taps[key] = 0;
    return value;
}

#endif /* PLATFORM_WINDOWS */
