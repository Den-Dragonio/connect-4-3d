#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

BUILD_DIR="$PROJECT_DIR/dist"
CACHE_DIR="$PROJECT_DIR/.build_cache"
WEB_DL_DIR="$PROJECT_DIR/web/downloads"

mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$WEB_DL_DIR"

echo "=== [1/6] Packaging Connect4_3D.love archive ==="
rm -f "$BUILD_DIR/Connect4_3D.love"
zip -9 -r "$BUILD_DIR/Connect4_3D.love" main.lua conf.lua src assets -x "*.DS_Store"
cp "$BUILD_DIR/Connect4_3D.love" "$WEB_DL_DIR/Connect4_3D.love"
echo "Created: $BUILD_DIR/Connect4_3D.love"

echo "=== [2/6] Building macOS Universal .app & .dmg Installer (Intel + Apple Silicon) ==="
LOVE_APP=""
if [ -d "/Applications/love.app" ]; then
    LOVE_APP="/Applications/love.app"
elif [ -d "/opt/homebrew/Caskroom/love" ]; then
    LOVE_APP="$(find /opt/homebrew/Caskroom/love -name "love.app" | head -n 1)"
fi

if [ -n "$LOVE_APP" ] && [ -d "$LOVE_APP" ]; then
    APP_OUT="$BUILD_DIR/Connect 4 3D.app"
    rm -rf "$APP_OUT"
    cp -R "$LOVE_APP" "$APP_OUT"
    cp "$BUILD_DIR/Connect4_3D.love" "$APP_OUT/Contents/Resources/Connect4_3D.love"

    if [ -f "$APP_OUT/Contents/Info.plist" ] && command -v plutil >/dev/null 2>&1; then
        plutil -replace CFBundleName -string "Connect 4 3D" "$APP_OUT/Contents/Info.plist" || true
        plutil -replace CFBundleDisplayName -string "Connect 4 3D" "$APP_OUT/Contents/Info.plist" || true
        plutil -replace CFBundleIdentifier -string "com.connect4.game3d" "$APP_OUT/Contents/Info.plist" || true
    fi

    if command -v hdiutil >/dev/null 2>&1; then
        DMG_STAGING="$CACHE_DIR/dmg_staging"
        rm -rf "$DMG_STAGING"
        mkdir -p "$DMG_STAGING"
        cp -R "$APP_OUT" "$DMG_STAGING/"
        ln -s /Applications "$DMG_STAGING/Applications"

        rm -f "$BUILD_DIR/Connect4_3D_Mac.dmg"
        hdiutil create -volname "Connect 4 3D" -srcfolder "$DMG_STAGING" -ov -format UDZO "$BUILD_DIR/Connect4_3D_Mac.dmg"
        cp "$BUILD_DIR/Connect4_3D_Mac.dmg" "$WEB_DL_DIR/Connect4_3D_Mac.dmg"
        echo "Created macOS Universal Installer: $BUILD_DIR/Connect4_3D_Mac.dmg"
    fi
fi

echo "=== [3/6] Building Windows Installers (Windows 11 / 10 / 8.1 / 8 / 7 — 32-bit & 64-bit) ==="
WIN32_ZIP="$CACHE_DIR/love-11.5-win32.zip"
WIN64_ZIP="$CACHE_DIR/love-11.5-win64.zip"

if [ ! -f "$WIN32_ZIP" ]; then
    curl -L -sS "https://github.com/love2d/love/releases/download/11.5/love-11.5-win32.zip" -o "$WIN32_ZIP"
fi
if [ ! -f "$WIN64_ZIP" ]; then
    curl -L -sS "https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip" -o "$WIN64_ZIP"
fi

WIN_UNIV_DIR="$CACHE_DIR/win_universal"
rm -rf "$WIN_UNIV_DIR" "$CACHE_DIR/love-11.5-win32"
unzip -q -o "$WIN32_ZIP" -d "$CACHE_DIR"
mv "$CACHE_DIR/love-11.5-win32" "$WIN_UNIV_DIR"
cat "$WIN_UNIV_DIR/love.exe" "$BUILD_DIR/Connect4_3D.love" > "$WIN_UNIV_DIR/Connect4_3D.exe"
rm -f "$WIN_UNIV_DIR/love.exe" "$WIN_UNIV_DIR/lovec.exe" "$WIN_UNIV_DIR/changes.txt" "$WIN_UNIV_DIR/readme.txt"

rm -f "$BUILD_DIR/Connect4_3D_Windows_Portable.zip"
(cd "$WIN_UNIV_DIR" && zip -9 -q -r "$BUILD_DIR/Connect4_3D_Windows_Portable.zip" .)
cp "$BUILD_DIR/Connect4_3D_Windows_Portable.zip" "$WEB_DL_DIR/Connect4_3D_Windows_Portable.zip"

WIN64_DIR="$CACHE_DIR/win64_native"
rm -rf "$WIN64_DIR" "$CACHE_DIR/love-11.5-win64"
unzip -q -o "$WIN64_ZIP" -d "$CACHE_DIR"
mv "$CACHE_DIR/love-11.5-win64" "$WIN64_DIR"
cat "$WIN64_DIR/love.exe" "$BUILD_DIR/Connect4_3D.love" > "$WIN64_DIR/Connect4_3D.exe"
rm -f "$WIN64_DIR/love.exe" "$WIN64_DIR/lovec.exe" "$WIN64_DIR/changes.txt" "$WIN64_DIR/readme.txt"

rm -f "$BUILD_DIR/Connect4_3D_Win64_Portable.zip"
(cd "$WIN64_DIR" && zip -9 -q -r "$BUILD_DIR/Connect4_3D_Win64_Portable.zip" .)
cp "$BUILD_DIR/Connect4_3D_Win64_Portable.zip" "$WEB_DL_DIR/Connect4_3D_Win64_Portable.zip"

if command -v makensis >/dev/null 2>&1; then
    makensis "$PROJECT_DIR/installer.nsi"
    cp "$BUILD_DIR/Connect4_3D_Setup.exe" "$WEB_DL_DIR/Connect4_3D_Setup.exe"
    echo "Created Windows Setup Installer: $BUILD_DIR/Connect4_3D_Setup.exe"
fi

echo "=== [4/6] Building Android APK Installer (Connect4_3D_Android.apk) ==="
ANDROID_BASE_APK="$CACHE_DIR/love-11.5-android-embed.apk"
UBER_SIGNER_JAR="$CACHE_DIR/uber-apk-signer.jar"

if [ ! -f "$ANDROID_BASE_APK" ]; then
    curl -L -sS "https://github.com/love2d/love-android/releases/download/11.5a/love-11.5-android-embed-norecording.apk" -o "$ANDROID_BASE_APK"
fi
if [ ! -f "$UBER_SIGNER_JAR" ]; then
    curl -L -sS "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar" -o "$UBER_SIGNER_JAR"
fi

APK_WORK_DIR="$CACHE_DIR/apk_work"
rm -rf "$APK_WORK_DIR"
mkdir -p "$APK_WORK_DIR/assets"
cp "$ANDROID_BASE_APK" "$APK_WORK_DIR/Connect4_3D_unsigned.apk"
cp "$BUILD_DIR/Connect4_3D.love" "$APK_WORK_DIR/assets/game.love"
(cd "$APK_WORK_DIR" && zip -0 -q "Connect4_3D_unsigned.apk" "assets/game.love")

if command -v java >/dev/null 2>&1; then
    java -jar "$UBER_SIGNER_JAR" -a "$APK_WORK_DIR/Connect4_3D_unsigned.apk" -o "$APK_WORK_DIR/signed" >/dev/null
    SIGNED_APK="$(find "$APK_WORK_DIR/signed" -name "*.apk" | head -n 1)"
    if [ -n "$SIGNED_APK" ] && [ -f "$SIGNED_APK" ]; then
        cp "$SIGNED_APK" "$BUILD_DIR/Connect4_3D_Android.apk"
        cp "$SIGNED_APK" "$WEB_DL_DIR/Connect4_3D_Android.apk"
        echo "Created Signed Android APK: $BUILD_DIR/Connect4_3D_Android.apk"
    fi
fi

echo "=== [5/6] Building iPhone / iOS Bundle (Connect4_3D_iOS_Xcode.zip) ==="
IOS_SRC_ZIP="$CACHE_DIR/love-11.5-ios-source.zip"
if [ -f "$IOS_SRC_ZIP" ]; then
    IOS_WORK_DIR="$CACHE_DIR/ios_work"
    rm -rf "$IOS_WORK_DIR"
    mkdir -p "$IOS_WORK_DIR"
    unzip -q -o "$IOS_SRC_ZIP" -d "$IOS_WORK_DIR"
    rm -rf "$IOS_WORK_DIR/__MACOSX"
    IOS_ROOT="$IOS_WORK_DIR/love-11.5-ios-source"
    if [ -d "$IOS_ROOT/platform/xcode/ios" ]; then
        cp "$BUILD_DIR/Connect4_3D.love" "$IOS_ROOT/platform/xcode/ios/Connect4_3D.love"
    fi
    cp "$BUILD_DIR/Connect4_3D.love" "$IOS_ROOT/Connect4_3D.love"
    rm -f "$BUILD_DIR/Connect4_3D_iOS_Xcode.zip"
    (cd "$IOS_WORK_DIR" && zip -9 -q -r "$BUILD_DIR/Connect4_3D_iOS_Xcode.zip" "love-11.5-ios-source")
    cp "$BUILD_DIR/Connect4_3D_iOS_Xcode.zip" "$WEB_DL_DIR/Connect4_3D_iOS_Xcode.zip"
    echo "Created iOS Xcode Project Bundle: $BUILD_DIR/Connect4_3D_iOS_Xcode.zip"
fi

echo "=== [6/6] Building Online & Mobile Web Version (WebAssembly / PWA) ==="
if command -v npx >/dev/null 2>&1; then
    CUSTOM_PLAY_HTML=""
    if [ -f "$PROJECT_DIR/web/play/index.html" ]; then
        CUSTOM_PLAY_HTML="$(cat "$PROJECT_DIR/web/play/index.html")"
    fi
    rm -rf "$PROJECT_DIR/web/play"
    npx -y love.js "$BUILD_DIR/Connect4_3D.love" "$PROJECT_DIR/web/play" -t "Connect 4 — 3D" -c
    if [ -n "$CUSTOM_PLAY_HTML" ]; then
        printf "%s\n" "$CUSTOM_PLAY_HTML" > "$PROJECT_DIR/web/play/index.html"
    elif [ -f "$PROJECT_DIR/web/play/index.html" ]; then
        sed -i '' 's/INITIAL_MEMORY: 16777216/INITIAL_MEMORY: 67108864/g' "$PROJECT_DIR/web/play/index.html" || true
    fi
    echo "Created WebAssembly & Mobile Web build in: $PROJECT_DIR/web/play"
fi

echo "=== Build Complete! All Desktop, Mobile & Web Artifacts Ready ==="
ls -lh "$BUILD_DIR"
