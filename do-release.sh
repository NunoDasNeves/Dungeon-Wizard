#!/bin/bash

set -xe

ASSETS="$(pwd)/assets"
VERSION="v0.13.0"
REPO_DIR=$(realpath)
RELEASE_REL_DIR="zig-out/release"
APP_DIR="Dungeon Wizard.app"

rm -rf "$RELEASE_REL_DIR"
zig build -Dstatic-link -Ddo-release

RELEASE_DIR=$(realpath "$RELEASE_REL_DIR")

make_dmg() {
	hdiutil create -verbose -fs APFS -volname "Dungeon Wizard" -srcfolder "$APP_DIR" "Dungeon Wizard $VERSION.dmg"
}

make_app_bundle() {
	local EXE_DIR="$1"

	pushd "$EXE_DIR"
	cp -R "$REPO_DIR/app-bundle" "$APP_DIR"
	rsync -av --exclude='*tilemaps.tiled-*' --exclude='.DS_Store' $ASSETS "$APP_DIR/Contents/Resources"
	#strip -u -r "Dungeon Wizard"
	cp "Dungeon Wizard" "$APP_DIR/Contents/MacOS"
	cp "$REPO_DIR/CHANGELOG.md" "$APP_DIR/Contents"
	popd
	mv "$EXE_DIR/$APP_DIR" "$RELEASE_DIR"
}

make_zip() {
	local EXE_DIR="$1"
	pushd "$EXE_DIR"
	rsync -av --exclude='*tilemaps.tiled-*' --exclude='.DS_Store' $ASSETS .
	cp "$REPO_DIR/CHANGELOG.md" .
	ZIPNAME="DungeonWizard-${DIR%/}-${VERSION}.zip"
	zip -r "$ZIPNAME" *
	popd
	mv "$EXE_DIR/$ZIPNAME" "$RELEASE_DIR"
}

pushd "$RELEASE_DIR"

for DIR in */; do
	DDIR="$DIR/Dungeon Wizard"
	REAL_DDIR=$(realpath "$DDIR")
	echo "$DIR"
	if echo "$DIR" | grep -q "macos"; then
		make_app_bundle "$REAL_DDIR"
		make_dmg
	elif echo "$DIR" | grep -q "windows"; then
		make_zip "$REAL_DDIR"
	else
		echo "Nothing to do?"
	fi
done
