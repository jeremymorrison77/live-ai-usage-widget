#!/bin/bash
# Redraws docs/images/overview.png from the app's own views with current installed readings.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/overview
# Match this completed setup for documentation; only the scratch source is changed.
sed -e 's/^@main struct UsageApp/struct UsageApp/' -e 's/@State private var widgetsPlaced: Int?$/@State private var widgetsPlaced: Int? = 1/' App/UsageApp.swift > build/overview/UsageApp.swift
xcrun swiftc -parse-as-library -module-cache-path build/module-cache \
  Shared/Status.swift Shared/Settings.swift Shared/StatusView.swift Helper/Reader.swift Helper/Collector.swift Helper/Updater.swift Helper/Diagnostics.swift \
  build/overview/UsageApp.swift tests/RenderOverview.swift -o build/overview/render
version=$(sed -n "s/.*CFBundleShortVersionString='\([0-9.]*\)'.*/\1/p" scripts/build.py)
group=$(/usr/libexec/PlistBuddy -c 'Print :UsageAppGroup' '/Applications/Live AI Usage Widget.app/Contents/Info.plist')
build/overview/render build/overview/overview.png "$version" "${WIDGET_RENDER_STORE:-$HOME/Library/Group Containers/$group}"
# Strip metadata; packaging refuses pictures that carry any.
python3 - <<'PY'
import subprocess, struct, zlib
data = open('build/overview/overview.png', 'rb').read()
out, i = data[:8], 8
while i < len(data):
    n = struct.unpack('>I', data[i:i+4])[0]; kind = data[i+4:i+8]
    if kind in (b'IHDR', b'PLTE', b'IDAT', b'IEND', b'tRNS'): out += data[i:i+12+n]
    i += 12 + n
open('docs/images/overview.png', 'wb').write(out)
PY
echo "Updated docs/images/overview.png"
