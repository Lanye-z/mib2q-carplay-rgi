#!/bin/bash
# Full Java source build against firmware lsd.jar and OSGi dependencies.
# Target: Java 1.2 bytecode for MHI2Q JVM compatibility.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="${JXE2JAR_DIR:-$SCRIPT_DIR/../jxe2jar}"

DEFAULT_JAVA_HOME="$TOOLS_DIR/jvms/zulu8.78.0.19-ca-jdk8.0.412-macosx_aarch64/zulu-8.jdk/Contents/Home"
JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"
JAVAC="${JAVAC:-$JAVA_HOME/bin/javac}"
JAR="${JAR:-$JAVA_HOME/bin/jar}"

LSD_JAR="${LSD_JAR:-$TOOLS_DIR/out/lsd.jar}"
OSGI_LIBS="${OSGI_LIBS:-$TOOLS_DIR/libs}"
OSGI_CP="$OSGI_LIBS/org.osgi.framework-1.10.0.jar:$OSGI_LIBS/org.osgi.util.tracker-1.5.4.jar"

SRC_DIR="$SCRIPT_DIR/java_patch"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build}"
OUTPUT_DIR="$BUILD_DIR/java/classes"
OUTPUT_JAR="${JAVA_OUTPUT:-$BUILD_DIR/carplay_hook.jar}"

echo "=== CarPlay Hook Java Builder ==="

if [ ! -x "$JAVAC" ]; then
    echo "ERROR: javac not found at $JAVAC" >&2
    echo "Set JAVA_HOME or JAVAC to a Java 8 compiler." >&2
    exit 1
fi
if [ ! -x "$JAR" ]; then
    echo "ERROR: jar not found at $JAR" >&2
    exit 1
fi
if [ ! -f "$LSD_JAR" ]; then
    echo "ERROR: lsd.jar not found at $LSD_JAR" >&2
    echo "Set LSD_JAR or JXE2JAR_DIR after extracting lsd.jxe with jxe2jar." >&2
    exit 1
fi
for dep in org.osgi.framework-1.10.0.jar org.osgi.util.tracker-1.5.4.jar; do
    if [ ! -f "$OSGI_LIBS/$dep" ]; then
        echo "ERROR: missing OSGi dependency: $OSGI_LIBS/$dep" >&2
        exit 1
    fi
done

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$(dirname "$OUTPUT_JAR")"

BUILD_ID="${CARPLAY_BUILD_ID:-2026-08-06-main-release}"
echo "Build ID: $BUILD_ID"

HOOK_FILE="$SRC_DIR/com/luka/carplay/CarPlayHook.java"
if [ -f "$HOOK_FILE" ]; then
    sed -i.bak "s/@BUILD_ID@/$BUILD_ID/g" "$HOOK_FILE"
    trap 'mv "$HOOK_FILE.bak" "$HOOK_FILE"' EXIT
fi

SOURCES_LIST=$(mktemp)
find "$SRC_DIR" -name '*.java' -type f ! -path '*/out/*' | sort > "$SOURCES_LIST"
FILE_COUNT=$(wc -l < "$SOURCES_LIST" | tr -d ' ')
echo "Compiling $FILE_COUNT files (target 1.2)..."

"$JAVAC" -source 1.2 -target 1.2 \
    -cp "$LSD_JAR:$OSGI_CP" \
    -sourcepath "$SRC_DIR" \
    -d "$OUTPUT_DIR" \
    -Xlint:-options \
    @"$SOURCES_LIST"
rm -f "$SOURCES_LIST"

cd "$OUTPUT_DIR"
"$JAR" cf "$OUTPUT_JAR" .
cd "$SCRIPT_DIR"

echo "Output: $OUTPUT_JAR"
find "$OUTPUT_DIR" -name '*.class' | sed "s|$OUTPUT_DIR/||" | sort
