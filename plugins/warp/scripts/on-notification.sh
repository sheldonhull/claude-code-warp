#!/bin/bash
# Hook script for Claude Code Notification event.
# Dispatches by notification_type:
#   - idle_prompt        → emit "idle_prompt" (current Warp behavior: no status change)
#   - permission_prompt  → already handled by the dedicated PermissionRequest hook; skip
#   - anything else      → suppress (no reliable mapping today)
#
# Note: as of Claude Code today there is no `notification_type` value emitted for
# AskUserQuestion. That flow is intercepted via the PreToolUse hook on the
# `AskUserQuestion` tool (see on-pre-tool-use.sh) instead of through Notification.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Legacy fallback for old Warp versions
if ! should_use_structured; then
    [ "$TERM_PROGRAM" = "WarpTerminal" ] && exec "$SCRIPT_DIR/legacy/on-notification.sh"
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
INPUT=$(cat)

NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null)
MSG=$(echo "$INPUT" | jq -r '.message // "Input needed"' 2>/dev/null)
[ -z "$MSG" ] && MSG="Input needed"

case "$NOTIF_TYPE" in
    idle_prompt)
        BODY=$(build_payload "$INPUT" "idle_prompt" --arg summary "$MSG")
        "$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
        ;;
    permission_prompt)
        # PermissionRequest hook handles this with richer payload — don't double-emit.
        exit 0
        ;;
    *)
        # Unmapped notification — keep quiet rather than misclassify the session.
        exit 0
        ;;
esac
