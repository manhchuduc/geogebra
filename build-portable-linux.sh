#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/source/desktop/desktop/build"
INSTALL_DIR="$BUILD_DIR/install/desktop"
DIST_DIR="$BUILD_DIR/distributions"
CACHE_DIR="$BUILD_DIR/tmp/portable-linux"
APP_IMAGE_NAME="GeoGebra"
ARCHIVE_PATH="$DIST_DIR/geogebra-classic5-portable-linux-x64.tar.gz"
ARCHIVE_TMP="$DIST_DIR/.geogebra-classic5-portable-linux-x64.$$.tar.gz"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    printf 'ERROR: This script must run on Linux x86_64.\n' >&2
    exit 1
fi

for command in java jpackage tar grep; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'ERROR: Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

JAVA_VERSION_OUTPUT="$(java -version 2>&1)"
if [[ ! "$JAVA_VERSION_OUTPUT" =~ version\ \"25\. ]]; then
    printf 'ERROR: JDK 25 is required; found:\n%s\n' "$JAVA_VERSION_OUTPUT" >&2
    exit 1
fi
JPACKAGE_VERSION_OUTPUT="$(jpackage --version)"
if [[ ! "$JPACKAGE_VERSION_OUTPUT" =~ ^25([.]|$) ]]; then
    printf 'ERROR: jpackage 25 is required; found: %s\n' "$JPACKAGE_VERSION_OUTPUT" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR" "$DIST_DIR"
"$ROOT_DIR/gradlew" -p "$ROOT_DIR/source/desktop" :desktop:installDist \
    --no-daemon --max-workers=1 \
    -Dorg.gradle.jvmargs="-Xmx1536m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
if [[ ! -f "$INSTALL_DIR/lib/desktop.jar" ]]; then
    printf 'ERROR: Gradle did not create %s\n' "$INSTALL_DIR/lib/desktop.jar" >&2
    exit 1
fi

STAGING_DIR="$(mktemp --directory "$CACHE_DIR/staging.XXXXXX")"
cleanup() {
    if [[ -n "${STAGING_DIR:-}" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
    if [[ -n "${ARCHIVE_TMP:-}" && -f "$ARCHIVE_TMP" ]]; then
        rm -f -- "$ARCHIVE_TMP"
    fi
}
trap cleanup EXIT

jpackage \
    --type app-image \
    --dest "$STAGING_DIR" \
    --name "$APP_IMAGE_NAME" \
    --input "$INSTALL_DIR/lib" \
    --main-jar desktop.jar \
    --main-class org.geogebra.desktop.GeoGebra3D \
    --java-options "--add-exports=java.base/java.lang=ALL-UNNAMED" \
    --java-options "--add-exports=java.desktop/sun.awt=ALL-UNNAMED" \
    --java-options "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED" \
    --java-options "--enable-native-access=ALL-UNNAMED"

APP_IMAGE_PATH="$STAGING_DIR/$APP_IMAGE_NAME"
if [[ ! -x "$APP_IMAGE_PATH/bin/$APP_IMAGE_NAME" ]]; then
    printf 'ERROR: jpackage did not create the GeoGebra launcher.\n' >&2
    exit 1
fi
if [[ ! -f "$APP_IMAGE_PATH/lib/runtime/lib/modules" ]]; then
    printf 'ERROR: jpackage did not include a Java runtime.\n' >&2
    exit 1
fi

tar --create --gzip --file "$ARCHIVE_TMP" --directory "$STAGING_DIR" "$APP_IMAGE_NAME"
tar --list --gzip --file "$ARCHIVE_TMP" >/dev/null
tar --list --gzip --file "$ARCHIVE_TMP" \
    | grep -Fx "$APP_IMAGE_NAME/bin/$APP_IMAGE_NAME" >/dev/null
tar --list --gzip --file "$ARCHIVE_TMP" \
    | grep -Fx "$APP_IMAGE_NAME/lib/runtime/lib/modules" >/dev/null
mv -f -- "$ARCHIVE_TMP" "$ARCHIVE_PATH"
ARCHIVE_TMP=""

printf 'Portable Linux build created:\n%s\n' "$ARCHIVE_PATH"
