#!/bin/bash
# Adds the iOS Info.plist keys OpenGym needs (macOS only: uses PlistBuddy).
#
#   - plain http to a Mac on the same wifi (DEV ONLY: allows arbitrary loads)
#   - local network, camera and photo library usage descriptions
#
# Run after `flutter create`, from the mobile/ folder:  tool/patch_ios_plist.sh
# Safe to run again: every key is deleted before it is added.

set -euo pipefail

PLIST="${1:-ios/Runner/Info.plist}"
PB="/usr/libexec/PlistBuddy"

if [ ! -x "$PB" ]; then
  echo "PlistBuddy not found at $PB. This script only runs on macOS." >&2
  exit 1
fi
if [ ! -f "$PLIST" ]; then
  echo "Cannot find $PLIST. Run 'flutter create .' first, from the mobile/ folder." >&2
  exit 1
fi

# Remove a key if present (ignore "does not exist").
del() { "$PB" -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true; }

add_string() {
  del "$1"
  "$PB" -c "Add :$1 string $2" "$PLIST"
}

del NSAppTransportSecurity
"$PB" -c "Add :NSAppTransportSecurity dict" "$PLIST"
"$PB" -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"
"$PB" -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST"

add_string NSLocalNetworkUsageDescription \
  "OpenGym talks to your own server on your local network."
add_string NSCameraUsageDescription \
  "OpenGym uses the camera to attach photos, such as a machine screen, to chat or import."
add_string NSPhotoLibraryUsageDescription \
  "OpenGym reads photos you choose to attach to chat or import."

echo "Patched $PLIST"
echo "Note: NSAllowsArbitraryLoads is for development. Remove it before any release build."
