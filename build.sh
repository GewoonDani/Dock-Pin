#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/module-cache "build/Dock Pin.app/Contents/MacOS" "build/Dock Pin.app/Contents/Resources" build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/app-icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" assets/app-icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
swift -module-cache-path build/module-cache MakeIcon.swift
rm -f "build/Dock Pin.app/Contents/Resources/AppIcon.icns" "build/Dock Pin.app/Contents/Resources/DockPinIcon.icns"
swiftc -module-cache-path build/module-cache EdgePolicy.swift MenuBarIcon.swift main.swift -o build/DockPin-check
build/DockPin-check --self-test
swiftc -O -module-cache-path build/module-cache EdgePolicy.swift MenuBarIcon.swift main.swift -o "build/Dock Pin.app/Contents/MacOS/DockPin"
cp Info.plist "build/Dock Pin.app/Contents/Info.plist"
codesign --force --sign - "build/Dock Pin.app"
codesign --verify --strict "build/Dock Pin.app"
touch "build/Dock Pin.app"
echo "Ready: $PWD/build/Dock Pin.app"
