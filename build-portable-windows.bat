@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%" || exit /b 1

set "BUILD_DIR=%ROOT%source\desktop\desktop\build"
set "INSTALL_DIR=%BUILD_DIR%\install\desktop"
set "DIST_DIR=%BUILD_DIR%\distributions"
set "ZIP_PATH=%DIST_DIR%\geogebra-classic5-portable-windows-x64.zip"
set "ICON_PATH=%ROOT%source\web\web\src\main\resources\org\geogebra\web\resources\war\favicon.ico"
set "BUILD_RESULT=1"

if not defined JAVA_HOME (
    echo ERROR: Set JAVA_HOME to a JDK 25 installation.
    goto finish
)

if not exist "%JAVA_HOME%\bin\jpackage.exe" (
    echo ERROR: jpackage.exe was not found under "%JAVA_HOME%\bin".
    goto finish
)

call gradlew.bat -p source/desktop :desktop:installDist --no-daemon
if errorlevel 1 (
    set "BUILD_RESULT=%ERRORLEVEL%"
    goto finish
)

if not exist "%INSTALL_DIR%\lib\desktop.jar" (
    echo ERROR: Gradle did not create "%INSTALL_DIR%\lib\desktop.jar".
    goto finish
)

if not exist "%ICON_PATH%" (
    echo ERROR: GeoGebra icon was not found at "%ICON_PATH%".
    goto finish
)

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
if errorlevel 1 goto finish

set "STAGING_DIR=%TEMP%\geogebra-portable-%RANDOM%-%RANDOM%"
set "APP_IMAGE=%STAGING_DIR%\GeoGebra"
mkdir "%STAGING_DIR%"
if errorlevel 1 (
    echo ERROR: Could not create the temporary staging directory.
    set "STAGING_DIR="
    goto finish
)

"%JAVA_HOME%\bin\jpackage.exe" ^
    --type app-image ^
    --dest "%STAGING_DIR%" ^
    --name GeoGebra ^
    --input "%INSTALL_DIR%\lib" ^
    --main-jar desktop.jar ^
    --main-class org.geogebra.desktop.GeoGebra3D ^
    --icon "%ICON_PATH%" ^
    --java-options "--add-exports=java.base/java.lang=ALL-UNNAMED" ^
    --java-options "--add-exports=java.desktop/sun.awt=ALL-UNNAMED" ^
    --java-options "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED" ^
    --java-options "--enable-native-access=ALL-UNNAMED"
if errorlevel 1 (
    set "BUILD_RESULT=%ERRORLEVEL%"
    goto finish
)

if not exist "%APP_IMAGE%\GeoGebra.exe" (
    echo ERROR: jpackage did not create GeoGebra.exe.
    goto finish
)

if not exist "%APP_IMAGE%\runtime\lib\modules" (
    echo ERROR: jpackage did not include a Java runtime.
    goto finish
)

set "GG_APP_IMAGE=%APP_IMAGE%"
set "GG_ZIP_PATH=%ZIP_PATH%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { Compress-Archive -Path (Join-Path $env:GG_APP_IMAGE '*') -DestinationPath $env:GG_ZIP_PATH -Force; exit 0 } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
    set "BUILD_RESULT=%ERRORLEVEL%"
    goto finish
)

echo.
echo Portable Windows build created:
echo %ZIP_PATH%
set "BUILD_RESULT=0"

:finish
if defined STAGING_DIR if exist "%STAGING_DIR%" rmdir /s /q "%STAGING_DIR%"
popd
exit /b %BUILD_RESULT%
