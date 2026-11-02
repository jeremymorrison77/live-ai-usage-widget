#!/bin/bash
# Debug check: draws the widget and Settings with the real Grok Bot usage file and current installed account readings.
# Writes build/grokbot-preview/; changes no installed app, widget or setting.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/grokbot-preview build/module-cache
# Match this completed setup for documentation; only the scratch source is changed.
sed -e 's/^@main struct UsageApp/struct UsageApp/' -e 's/@State private var widgetsPlaced: Int?$/@State private var widgetsPlaced: Int? = 1/' App/UsageApp.swift > build/grokbot-preview/UsageApp.swift
xcrun swiftc -parse-as-library -module-cache-path build/module-cache \
  Shared/Status.swift Shared/Settings.swift Shared/StatusView.swift Helper/Reader.swift Helper/Collector.swift Helper/Updater.swift Helper/Diagnostics.swift \
  build/grokbot-preview/UsageApp.swift tests/RenderGrokBot.swift -o build/grokbot-preview/render
version=$(sed -n "s/.*CFBundleShortVersionString='\([0-9.]*\)'.*/\1/p" scripts/build.py)
group=$(/usr/libexec/PlistBuddy -c 'Print :UsageAppGroup' '/Applications/Live AI Usage Widget.app/Contents/Info.plist')
build/grokbot-preview/render build/grokbot-preview "$version" "${WIDGET_RENDER_STORE:-$HOME/Library/Group Containers/$group}"
# Publish only the seven reviewed views, stripped of all PNG metadata.
python3 - <<'PYPNG'
from pathlib import Path
import struct
for name in [f"{style}-{size}.png" for style in ("clean", "solar") for size in ("small", "medium", "large")] + ["settings.png"]:
    data = (Path("build/grokbot-preview") / name).read_bytes()
    out, i = data[:8], 8
    while i < len(data):
        n = struct.unpack(">I", data[i:i+4])[0]
        if data[i+4:i+8] in (b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS"):
            out += data[i:i+12+n]
        i += 12 + n
    (Path("docs/images") / name).write_bytes(out)
PYPNG
