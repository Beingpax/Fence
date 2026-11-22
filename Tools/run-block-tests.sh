#!/bin/bash
# Checks the schedule and lock maths in Shift/Models/Block.swift.
#
# There is no test target in the project yet, and the trickiest logic in the app is pure
# and self-contained, so it compiles standalone against the model file. Run from the repo
# root: ./Tools/run-block-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
swiftc -o "$OUT/blocktest" Shift/Models/Block.swift Tools/BlockLogicTests/main.swift
"$OUT/blocktest"
