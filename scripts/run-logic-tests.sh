#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="/tmp/SnapAILogicTests"

swiftc \
  Sources/SnapAI/Action.swift \
  Sources/SnapAI/Provider.swift \
  Sources/SnapAI/ContextProfile.swift \
  Sources/SnapAI/History.swift \
  Sources/SnapAI/Keychain.swift \
  Sources/SnapAI/Settings.swift \
  Sources/SnapAI/HotKeyUtilities.swift \
  Sources/SnapAI/PrivacyFilter.swift \
  Sources/SnapAI/TextCapture.swift \
  Sources/SnapAI/TextEditTransaction.swift \
  Sources/SnapAI/TextDiff.swift \
  Sources/SnapAI/ModelCapability.swift \
  Sources/SnapAI/AIRequestRouter.swift \
  Sources/SnapAI/AIClient.swift \
  Sources/SnapAI/UpdateChecker.swift \
  Tests/SnapAILogicTests/main.swift \
  -o "$OUT" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Security

"$OUT"
