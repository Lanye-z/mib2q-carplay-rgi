#!/bin/bash
set -e

QNX_VM="${QNX_VM:-192.168.64.16}"
QNX_USER="${QNX_USER:-root}"
QNX_PASSWORD="${QNX_PASSWORD:-root}"
QNX_REMOTE_DIR="${QNX_REMOTE_DIR:-/tmp/c_render}"
SSH_OPTS="${SSH_OPTS:--oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RENDERER_DIR="${SCRIPT_DIR}/c_render"
OUT="${RENDER_OUT:-${SCRIPT_DIR}/release/maneuver_render}"
mkdir -p "$(dirname "$OUT")"

for cmd in sshpass ssh scp tar; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd" >&2; exit 1; }
done

RENDERER_SRCS="main.c render.c maneuver.c route_path.c server.c platform_qnx.c"
REMOTE="${QNX_USER}@${QNX_VM}"
SSH=(sshpass -p "$QNX_PASSWORD" ssh $SSH_OPTS "$REMOTE")
SCP=(sshpass -p "$QNX_PASSWORD" scp $SSH_OPTS)

echo "=== Cluster Renderer Build ==="
echo "QNX host: $REMOTE"
echo "Remote directory: $QNX_REMOTE_DIR"
echo "Output: $OUT"

tar --disable-copyfile --format=ustar -C "$RENDERER_DIR" -cf - \
    main.c render.c render.h maneuver.c maneuver.h route_path.c route_path.h \
    server.c server.h protocol.h platform.h platform_qnx.c gl_compat.h \
    | "${SSH[@]}" "rm -rf '$QNX_REMOTE_DIR' && mkdir -p '$QNX_REMOTE_DIR' && tar -xf - -C '$QNX_REMOTE_DIR'"

EXTRA_CFLAGS=""
if [ "${1:-}" = "grid" ]; then
    EXTRA_CFLAGS="-DCR_DEBUG_GRID"
fi

SRC_PATHS=""
for f in $RENDERER_SRCS; do
    SRC_PATHS="$SRC_PATHS $QNX_REMOTE_DIR/$f"
done

BUILD_CMD="/usr/qnx650/host/qnx6/x86/usr/bin/ntoarmv7-gcc -O2 -std=gnu99 -Wall -D__QNX__ -DPLATFORM_QNX -fdata-sections -ffunction-sections $EXTRA_CFLAGS -I$QNX_REMOTE_DIR $SRC_PATHS -o $QNX_REMOTE_DIR/maneuver_render -Wl,--gc-sections -lEGL -lGLESv2 -lsocket -lm"

"${SSH[@]}" "export QNX_HOST=/usr/qnx650/host/qnx6/x86; export QNX_TARGET=/usr/qnx650/target/qnx6; cd '$QNX_REMOTE_DIR' && $BUILD_CMD"
"${SCP[@]}" "$REMOTE:$QNX_REMOTE_DIR/maneuver_render" "$OUT"
chmod +x "$OUT"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT_NAME="$(basename "$OUT")"
if [ "$OUT_NAME" = "maneuver_render" ] && [ -f "$OUT_DIR/carplay_hook.jar" ]; then
    (cd "$OUT_DIR" && sha256sum carplay_hook.jar maneuver_render > SHA256SUMS)
else
    sha256sum "$OUT"
fi
