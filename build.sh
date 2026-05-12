#!/bin/bash
set -euo pipefail

# Build the usagi macOS menu bar app.
# Output: bin/Usagi.app
#
# Environment variables:
#   UNIVERSAL=1          — build universal binary (arm64 + x86_64)
#   DMG=1                — create a DMG after building the .app
#   SIGN_IDENTITY=...    — codesign identity (e.g. "Developer ID Application: Name (TEAM)")
#   NOTARIZE_PROFILE=... — notarytool keychain profile for notarization
#   NOTARIZE_KEY=...     — alternative: path to App Store Connect .p8 key
#   NOTARIZE_KEY_ID=...  — App Store Connect key ID (used with NOTARIZE_KEY)
#   NOTARIZE_ISSUER=...  — App Store Connect issuer ID (used with NOTARIZE_KEY)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/bin"
VERSION="${VERSION:-$(cat "$SCRIPT_DIR/VERSION")}"

cd "$SCRIPT_DIR"

BUILD_ARGS=(-c release)
if [ "${UNIVERSAL:-}" = "1" ]; then
	echo "Building Usagi (universal: arm64 + x86_64)..."
	BUILD_ARGS+=(--arch arm64 --arch x86_64)
else
	echo "Building Usagi..."
fi
swift build "${BUILD_ARGS[@]}"

APP_DIR="$BUILD_DIR/Usagi.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BINARY_PATH=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/Usagi
cp "$BINARY_PATH" "$MACOS_DIR/Usagi"

cp "$SCRIPT_DIR/Sources/Usagi/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$CONTENTS_DIR/Info.plist"

if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
	cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/"
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
	echo "Signing with: $SIGN_IDENTITY"
	codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
	echo "Ad-hoc signing (set SIGN_IDENTITY for Developer ID signing)"
	codesign --force --deep -s - "$APP_DIR"
fi

echo "Built $APP_DIR"

if [ "${DMG:-}" = "1" ]; then
	DMG_PATH="$BUILD_DIR/Usagi-${VERSION}.dmg"
	TEMP_DMG="/tmp/Usagi-temp-$$.dmg"
	VOL_NAME="Usagi"
	MOUNT_POINT="/Volumes/$VOL_NAME"

	echo "Creating DMG..."

	hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
	rm -f "$TEMP_DMG"

	hdiutil create "$TEMP_DMG" -size 100m -volname "$VOL_NAME" -fs "HFS+" >/dev/null
	hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen >/dev/null
	sleep 1

	cp -R "$APP_DIR" "$MOUNT_POINT/"
	ln -s /Applications "$MOUNT_POINT/Applications"

	if [ -f "$SCRIPT_DIR/dmg-background.png" ]; then
		mkdir -p "$MOUNT_POINT/.background"
		cp "$SCRIPT_DIR/dmg-background.png" "$MOUNT_POINT/.background/background.png"
	fi

	osascript <<-APPLESCRIPT
	tell application "Finder"
		tell disk "$VOL_NAME"
			open
			delay 1
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 200, 760, 540}
			set opts to icon view options of container window
			set icon size of opts to 80
			set text size of opts to 12
			set arrangement of opts to not arranged
			try
				set background picture of opts to file ".background:background.png"
			end try
			set position of item "Usagi.app" of container window to {140, 170}
			set position of item "Applications" of container window to {420, 170}
			delay 1
			close
		end tell
	end tell
	APPLESCRIPT

	if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
		cp "$SCRIPT_DIR/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
		SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
	fi

	sync
	hdiutil detach "$MOUNT_POINT" -quiet
	rm -f "$DMG_PATH"
	hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -quiet
	rm -f "$TEMP_DMG"

	if [ -n "${SIGN_IDENTITY:-}" ]; then
		codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
	fi

	if [ -n "${NOTARIZE_PROFILE:-}" ]; then
		echo "Submitting for notarization (keychain profile)..."
		xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait
		xcrun stapler staple "$DMG_PATH"
	elif [ -n "${NOTARIZE_KEY:-}" ] && [ -n "${NOTARIZE_KEY_ID:-}" ] && [ -n "${NOTARIZE_ISSUER:-}" ]; then
		echo "Submitting for notarization (App Store Connect API key)..."
		xcrun notarytool submit "$DMG_PATH" \
			--key "$NOTARIZE_KEY" \
			--key-id "$NOTARIZE_KEY_ID" \
			--issuer "$NOTARIZE_ISSUER" \
			--wait
		xcrun stapler staple "$DMG_PATH"
	fi

	echo "Created $DMG_PATH"
else
	echo "Run with: open $APP_DIR"
fi
