#!/bin/bash
set -euo pipefail
PACKAGE_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PACKAGE_ROOT"
python3 -m unittest discover -s tests
mkdir -p build/module-cache
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Shared/Status.swift Shared/Settings.swift tests/UsageHistoryTests.swift -o build/history-tests
build/history-tests

xcrun swiftc -parse-as-library -module-cache-path build/module-cache Helper/Reader.swift Helper/Collector.swift tests/ReaderTests.swift -o build/reader-tests
build/reader-tests
