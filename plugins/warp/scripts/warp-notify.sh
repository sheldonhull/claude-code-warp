#!/bin/bash
# Warp notification utility using OSC escape sequences.
# Usage: warp-notify.sh <title> <body>
#
# Writes the OSC 777 sequence to the user-facing terminal pty so Warp can pick
# it up. Claude Code v2.x runs hook subprocesses without a controlling /dev/tty
# (the hook is forked by the bg-pty-host daemon, not the user-facing claim
# process), so a naive `> /dev/tty` fails with "Device not configured" and the
# notification is silently dropped. We therefore search up the parent PID chain
# for the first process that DOES have a controlling tty and write there
# directly.
#
# For structured Warp notifications, title should be "warp://cli-agent"
# and body should be a JSON string matching the cli-agent notification schema.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Only emit notifications when we've confirmed the Warp build can render them.
if ! should_use_structured; then
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

# Walk the parent PID chain looking for a controlling tty. macOS `ps` reports
# tty as e.g. "ttys001" (no /dev/ prefix), or "??" / "?" when none. We accept
# the first non-empty, non-`?`/`??` entry whose corresponding /dev/<tty> exists
# and is writeable.
find_owner_tty() {
    local pid="$$"
    local depth=0
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
        local tty
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' \t')
        case "$tty" in
            ""|"?"|"??") ;;
            *)
                local candidate="/dev/$tty"
                if [ -w "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
                ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' \t')
        depth=$((depth + 1))
    done
    return 1
}

emit() {
    # OSC 777: \033]777;notify;<title>;<body>\007
    printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY"
}

# Prefer the writable owner tty discovered by walking parents; fall back to
# /dev/tty (works when the script IS run with a controlling terminal); finally
# fall back to stdout (Claude Code captures it, but at worst the notification
# is lost — never blocks the hook).
if tty_path=$(find_owner_tty); then
    emit > "$tty_path" 2>/dev/null || true
else
    emit > /dev/tty 2>/dev/null || emit || true
fi
