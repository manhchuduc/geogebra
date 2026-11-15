#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/source/desktop/desktop/build"
INSTALL_DIR="$BUILD_DIR/install/desktop"
DIST_DIR="$BUILD_DIR/distributions"
CACHE_DIR="$BUILD_DIR/tmp/portable-windows"
LAUNCH4J_CACHE_DIR="$BUILD_DIR/tmp/launch4j"
ZIP_PATH="$DIST_DIR/geogebra-classic5-portable-windows-x64.zip"
ICON_PATH="$ROOT_DIR/source/web/web/src/main/resources/org/geogebra/web/resources/war/favicon.ico"

JRE_ARCHIVE="$CACHE_DIR/temurin-jre.zip"
JRE_URL="https://api.adoptium.net/v3/binary/version/jdk-25.0.5+8/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
JRE_SHA256="da78d54a2fcdbba1e92d5e3f07dd30236f96297891c4a21a781c3f38f5c0beae"
LAUNCH4J_ARCHIVE="$LAUNCH4J_CACHE_DIR/launch4j-linux.tgz"
LAUNCH4J_URL="https://sourceforge.net/projects/launch4j/files/launch4j-3/3.50/launch4j-3.50-linux-x64.tgz/download"
LAUNCH4J_SHA256="a6ad95c2fb6300410543288308b4eeae72ecd1df033928dfc524ba539bbc4d36"
LAUNCH4J_HOME="$LAUNCH4J_CACHE_DIR/launch4j"

for command in java curl unzip zip tar sha256sum file; do
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

download_verified() {
    local url="$1"
    local destination="$2"
    local expected_sha256="$3"
    local temporary="${destination}.part"

    if [[ -f "$destination" ]] \
            && printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
        return
    fi

    printf 'Downloading %s\n' "$url"
    curl --fail --location --retry 3 --connect-timeout 20 --output "$temporary" "$url"
    if ! printf '%s  %s\n' "$expected_sha256" "$temporary" | sha256sum --check --status; then
        rm -f -- "$temporary"
        printf 'ERROR: SHA-256 verification failed for %s\n' "$url" >&2
        return 1
    fi
    mv -f -- "$temporary" "$destination"
}

mkdir -p "$CACHE_DIR" "$LAUNCH4J_CACHE_DIR" "$DIST_DIR"
download_verified "$JRE_URL" "$JRE_ARCHIVE" "$JRE_SHA256"
download_verified "$LAUNCH4J_URL" "$LAUNCH4J_ARCHIVE" "$LAUNCH4J_SHA256"

if [[ ! -f "$LAUNCH4J_HOME/launch4j.jar" || ! -x "$LAUNCH4J_HOME/bin/ld" ]]; then
    tar --extract --gzip --file "$LAUNCH4J_ARCHIVE" --directory "$LAUNCH4J_CACHE_DIR"
fi
if [[ ! -f "$LAUNCH4J_HOME/launch4j.jar" || ! -x "$LAUNCH4J_HOME/bin/ld" ]]; then
    printf 'ERROR: Launch4j Linux cross-build tools were not extracted correctly.\n' >&2
    exit 1
fi

"$ROOT_DIR/gradlew" -p "$ROOT_DIR/source/desktop" :desktop:installDist \
    --no-daemon --max-workers=1 \
    -Dorg.gradle.jvmargs="-Xmx1536m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
if [[ ! -f "$INSTALL_DIR/lib/desktop.jar" ]]; then
    printf 'ERROR: Gradle did not create %s\n' "$INSTALL_DIR/lib/desktop.jar" >&2
    exit 1
fi
if [[ ! -f "$ICON_PATH" ]]; then
    printf 'ERROR: GeoGebra icon not found: %s\n' "$ICON_PATH" >&2
    exit 1
fi

STAGING_DIR="$(mktemp --directory "$CACHE_DIR/staging.XXXXXX")"
ZIP_TMP="$DIST_DIR/.geogebra-classic5-portable-windows-x64.$$.zip"
cleanup() {
    if [[ -n "${STAGING_DIR:-}" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
    if [[ -n "${ZIP_TMP:-}" && -f "$ZIP_TMP" ]]; then
        rm -f -- "$ZIP_TMP"
    fi
}
trap cleanup EXIT

cp -a "$INSTALL_DIR/." "$STAGING_DIR/"
mkdir -p "$STAGING_DIR/jre"
JRE_EXTRACT_DIR="$STAGING_DIR/jre-extract"
mkdir "$JRE_EXTRACT_DIR"
unzip -q "$JRE_ARCHIVE" -d "$JRE_EXTRACT_DIR"
JRE_ROOT="$(find "$JRE_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)"
if [[ -z "$JRE_ROOT" ]] \
        || ! grep -Fq 'OS_NAME="Windows"' "$JRE_ROOT/release" \
        || ! grep -Fq 'OS_ARCH="x86_64"' "$JRE_ROOT/release"; then
    printf 'ERROR: Downloaded runtime is not Windows x64.\n' >&2
    exit 1
fi
cp -a "$JRE_ROOT/." "$STAGING_DIR/jre/"
rm -rf -- "$JRE_EXTRACT_DIR"

install --mode=0644 "$ICON_PATH" "$STAGING_DIR/GeoGebra.ico"
cat > "$STAGING_DIR/launch4j.xml" <<'XML'
<launch4jConfig>
    <dontWrapJar>true</dontWrapJar>
    <headerType>gui</headerType>
    <outfile>GeoGebra.exe</outfile>
    <errTitle>GeoGebra Classic 5</errTitle>
    <jar>lib/desktop.jar</jar>
    <icon>GeoGebra.ico</icon>
    <jre>
        <path>jre</path>
        <requires64Bit>true</requires64Bit>
        <opt>--add-exports=java.base/java.lang=ALL-UNNAMED</opt>
        <opt>--add-exports=java.desktop/sun.awt=ALL-UNNAMED</opt>
        <opt>--add-exports=java.desktop/sun.java2d=ALL-UNNAMED</opt>
        <opt>--enable-native-access=ALL-UNNAMED</opt>
    </jre>
</launch4jConfig>
XML

(
    cd "$STAGING_DIR"
    java -Djava.awt.headless=true -jar "$LAUNCH4J_HOME/launch4j.jar" launch4j.xml
)
if ! file "$STAGING_DIR/GeoGebra.exe" | grep -Fq 'PE32 executable'; then
    printf 'ERROR: Launch4j did not create a Windows executable.\n' >&2
    exit 1
fi
rm -f -- "$STAGING_DIR/GeoGebra.ico" "$STAGING_DIR/launch4j.xml"

if [[ -e "$ZIP_TMP" ]]; then
    printf 'ERROR: Temporary ZIP already exists: %s\n' "$ZIP_TMP" >&2
    exit 1
fi
(
    cd "$STAGING_DIR"
    zip --quiet --recurse-paths "$ZIP_TMP" GeoGebra.exe bin lib jre
)
unzip -tq "$ZIP_TMP"
unzip -Z1 "$ZIP_TMP" | grep -Fx 'GeoGebra.exe' >/dev/null
unzip -Z1 "$ZIP_TMP" | grep -Fx 'jre/bin/javaw.exe' >/dev/null
mv -f -- "$ZIP_TMP" "$ZIP_PATH"
ZIP_TMP=""

printf 'Portable Windows build created:\n%s\n' "$ZIP_PATH"
