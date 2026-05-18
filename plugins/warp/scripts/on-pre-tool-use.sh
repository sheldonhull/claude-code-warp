#!/bin/bash
# Hook script for Claude Code PreToolUse event, matched on AskUserQuestion only.
# Fires when the agent invokes AskUserQuestion, before the UI prompt renders.
# Claude Code does not surface AskUserQuestion via Notification today; this is
# the only reliable signal that the session is about to block on a user choice.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# No legacy equivalent for this hook
if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# Extract the first question text if available, for the summary line.
SUMMARY=$(echo "$INPUT" | jq -r '
    (.tool_input.questions // [])
    | (.[0].question // .[0].header // empty)
' 2>/dev/null)
[ -z "$SUMMARY" ] && SUMMARY="Waiting for your answer"
if [ ${#SUMMARY} -gt 200 ]; then
    SUMMARY="${SUMMARY:0:197}..."
fi

BODY=$(build_payload "$INPUT" "question_asked" \
    --arg summary "$SUMMARY")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
