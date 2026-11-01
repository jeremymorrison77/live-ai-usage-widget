#!/bin/bash
# Debug check: draws the widget and Settings with the real Grok Bot usage file (other accounts are samples).
# Writes build/grokbot-preview/; reads nothing else and changes no installed app, widget or setting.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/grokbot-preview build/module-cache
sed 's/^@main struct UsageApp/struct UsageApp/' App/UsageApp.swift > build/grokbot-preview/UsageApp.swift
xcrun swiftc -parse-as-library -module-cache-path build/module-cache \
  Shared/Status.swift Shared/Settings.swift Shared/StatusView.swift Helper/Reader.swift Helper/Collector.swift Helper/Updater.swift Helper/Diagnostics.swift \
  build/grokbot-preview/UsageApp.swift tests/RenderGrokBot.swift -o build/grokbot-preview/render
build/grokbot-preview/render build/grokbot-preview
