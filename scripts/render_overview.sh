#!/bin/bash
# Redraws docs/images/overview.png from the app's own views with made-up readings.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/overview
sed 's/^@main struct UsageApp/struct UsageApp/' App/UsageApp.swift > build/overview/UsageApp.swift
xcrun swiftc -parse-as-library -module-cache-path build/module-cache \
  Shared/Status.swift Shared/Settings.swift Shared/StatusView.swift Helper/Reader.swift Helper/Collector.swift \
  build/overview/UsageApp.swift tests/RenderOverview.swift -o build/overview/render
build/overview/render build/overview/overview.png
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
