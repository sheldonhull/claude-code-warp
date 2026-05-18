#!/bin/bash
# Hook script for Claude Code SessionEnd event.
# Emits a "cancelled" event when the user explicitly ends the session
# (prompt_input_exit, logout, /clear). Normal post-turn termination is already
# handled by the Stop hook; SessionEnd fires after the whole session unwinds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

REASON=$(echo "$INPUT" | jq -r '.reason // "other"' 2>/dev/null)

# Map Claude Code's documented reason values:
#   clear, logout, prompt_input_exit, bypass_permissions_disabled  → user-driven cancel
#   resume                                                         → not an end, skip
#   other / anything else                                          → cancelled (safe default)
case "$REASON" in
    resume)
        exit 0
        ;;
esac

BODY=$(build_payload "$INPUT" "cancelled" \
    --arg reason "$REASON")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
