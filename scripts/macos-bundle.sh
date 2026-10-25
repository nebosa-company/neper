#!/bin/bash
# Makes an application bundle of a Neper program built for macOS, on a Mac (it uses sips, iconutil, plutil and codesign).
#   macos-bundle.sh --exe PROGRAM --name NAME --id com.example.name --out DIR
#                   [--version 1.0] [--icon icon.png] [--agent]
#                   [--usage-camera TEXT] [--usage-microphone TEXT] [--usage-location TEXT] [--zip]
# DIR/NAME.app holds Contents/Info.plist, Contents/MacOS/NAME (the program), Contents/Resources/NAME.icns (from the png, a square
# of 1024 pixels or more is best) and an ad-hoc signature. --agent leaves the program out of the Dock (LSUIElement). The usage texts
# are what the system shows when the program first asks for the camera, the microphone or the location, and without them the system
# ends a program that asks. --zip also writes DIR/NAME.zip with ditto, the form a download takes.
# Not done here: a Developer ID signature with the hardened runtime and notarization, which need an Apple developer identity;
# run `codesign --force --options runtime --sign "Developer ID Application: ..." DIR/NAME.app` and `xcrun notarytool submit` on the
# result.
set -eu
exe=""; name=""; id=""; out=""; version="1.0"; icon=""; agent=0; zip=0
camera=""; microphone=""; location=""
while [ $# -gt 0 ]; do
  case "$1" in
    --exe) exe=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    --id) id=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --version) version=$2; shift 2 ;;
    --icon) icon=$2; shift 2 ;;
    --agent) agent=1; shift ;;
    --usage-camera) camera=$2; shift 2 ;;
    --usage-microphone) microphone=$2; shift 2 ;;
    --usage-location) location=$2; shift 2 ;;
    --zip) zip=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
for v in exe name id out; do
  if [ -z "${!v}" ]; then echo "missing --$v" >&2; exit 2; fi
done
[ -x "$exe" ] || { echo "not an executable: $exe" >&2; exit 2; }
case "$name" in */*|*..*) echo "the name is a file name: $name" >&2; exit 2 ;; esac

app="$out/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$exe" "$app/Contents/MacOS/$name"
chmod 755 "$app/Contents/MacOS/$name"

icon_key=""
if [ -n "$icon" ]; then
  set_dir=$(mktemp -d)/icon.iconset
  mkdir -p "$set_dir"
  for size in 16 32 64 128 256 512; do
    sips -z $size $size "$icon" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$icon" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$set_dir" -o "$app/Contents/Resources/$name.icns"
  icon_key="<key>CFBundleIconFile</key><string>$name</string>"
fi

extra=""
[ "$agent" = 1 ] && extra="$extra<key>LSUIElement</key><true/>"
[ -n "$camera" ] && extra="$extra<key>NSCameraUsageDescription</key><string>$camera</string>"
[ -n "$microphone" ] && extra="$extra<key>NSMicrophoneUsageDescription</key><string>$microphone</string>"
[ -n "$location" ] && extra="$extra<key>NSLocationWhenInUseUsageDescription</key><string>$location</string>"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$id</string><key>CFBundleName</key><string>$name</string><key>CFBundleDisplayName</key><string>$name</string><key>CFBundleExecutable</key><string>$name</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$version</string><key>CFBundleVersion</key><string>$version</string><key>NSHighResolutionCapable</key><true/>$icon_key$extra</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - --deep "$app" 2>/dev/null
codesign --verify --deep --strict "$app"
if [ "$zip" = 1 ]; then
  rm -f "$out/$name.zip"
  ditto -c -k --keepParent "$app" "$out/$name.zip"
fi
echo "$app"
