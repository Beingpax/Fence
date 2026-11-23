#!/bin/bash
# Runs model and separate-process enforcement checks against a temporary store.
# The application and its login services are never launched.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 5 -strict-concurrency=complete -o "$OUT/blocktest" \
  Shift/Models/{Block,BlockStore,WebsiteAddress,ScreenContext,Verdict}.swift \
  Shift/Enforcement/{ShiftInstallation,GuardState,ProcessLease}.swift \
  Shift/Intelligence/{BlockEvaluator,WebsiteCategoryCatalog,WebRuleInput}.swift \
  Tools/BlockLogicTests/main.swift
"$OUT/blocktest"
