#!/bin/bash
# Hook script for Claude Code PostToolUse event.
# Fires only when the tool succeeded (failures route to PostToolUseFailure).
# We still inspect tool_response defensively in case a built-in tool surfaces
# an error inline (e.g. some tools embed is_error/success without routing to
# PostToolUseFailure). Either way the event name stays tool_complete so the
# Warp parser can decide the resulting status from the `success` field.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# is_error / success may live under tool_response for tools that surface
# failures inline rather than via PostToolUseFailure (e.g. Bash with non-zero
# exit codes pre-routing fix). Treat absence as "succeeded".
IS_ERROR=$(echo "$INPUT" | jq -r '
    if (.tool_response.is_error // false) then true
    elif (.tool_response.success // true) == false then true
    else false
    end
' 2>/dev/null)

if [ "$IS_ERROR" = "true" ]; then
    BODY=$(build_payload "$INPUT" "tool_complete" \
        --arg tool_name "$TOOL_NAME" \
        --argjson success false)
else
    BODY=$(build_payload "$INPUT" "tool_complete" \
        --arg tool_name "$TOOL_NAME" \
        --argjson success true)
fi

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
