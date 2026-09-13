#!/bin/bash
# Runs the PoiseKit engine tests (pure functions over fixtures — no network, no simulator).
set -euo pipefail
cd "$(dirname "$0")/../Packages/PoiseKit"
swift test "$@"
