#!/bin/bash
# Hook script for Claude Code PostToolUseFailure event.
# Claude Code routes tool failures (e.g. Bash non-zero exit) to this hook
# instead of PostToolUse. We emit a tool_complete with success:false so Warp
# can transition the session to the Error status.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
ERROR_MSG=$(echo "$INPUT" | jq -r '.error // .tool_response.error // .tool_response.stderr // empty' 2>/dev/null)
if [ -n "$ERROR_MSG" ] && [ ${#ERROR_MSG} -gt 200 ]; then
    ERROR_MSG="${ERROR_MSG:0:197}..."
fi

BODY=$(build_payload "$INPUT" "tool_complete" \
    --arg tool_name "$TOOL_NAME" \
    --argjson success false \
    --arg summary "$ERROR_MSG")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
