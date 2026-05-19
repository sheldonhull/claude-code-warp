#!/bin/bash
# Warp notification utility using OSC escape sequences.
# Usage: warp-notify.sh <title> <body>
#
# (See top-of-file comments in repo history for full background. Short version:
# claude code v2.x hooks have no controlling tty, so we walk parents on macOS
# and delegate to a PowerShell helper on Windows that uses AttachConsole.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

# Debug log (set WARP_NOTIFY_DEBUG=1 to enable).
WARP_NOTIFY_DEBUG="${WARP_NOTIFY_DEBUG:-1}"
WARP_NOTIFY_LOG="${WARP_NOTIFY_LOG:-$HOME/.warp-notify-debug.log}"
debug() {
    [ "$WARP_NOTIFY_DEBUG" = "1" ] || return 0
    printf '[%s] [pid=%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >> "$WARP_NOTIFY_LOG" 2>/dev/null || true
}

debug "ENTRY title=${1:-} OSTYPE=${OSTYPE:-} OS=${OS:-} WARP_CLIENT_VERSION=${WARP_CLIENT_VERSION:-} WARP_CLI_AGENT_PROTOCOL_VERSION=${WARP_CLI_AGENT_PROTOCOL_VERSION:-} TERM_PROGRAM=${TERM_PROGRAM:-}"

if ! should_use_structured; then
    debug "EXIT should_use_structured=false"
    exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

case "${OSTYPE:-}${OS:-}" in
    *msys*|*cygwin*|*Windows_NT*)
        debug "WINDOWS path selected"
        PS1_HELPER="$SCRIPT_DIR/windows/notify-windows.ps1"
        if [ ! -f "$PS1_HELPER" ]; then
            debug "FAIL ps1 helper missing at $PS1_HELPER"
        else
            PS_BIN=""
            if command -v pwsh.exe >/dev/null 2>&1; then
                PS_BIN="pwsh.exe"
            elif command -v powershell.exe >/dev/null 2>&1; then
                PS_BIN="powershell.exe"
            fi
            debug "PS_BIN=$PS_BIN PS1_HELPER=$PS1_HELPER"
            if [ -n "$PS_BIN" ]; then
                WIN_PS1="$PS1_HELPER"
                if command -v cygpath >/dev/null 2>&1; then
                    WIN_PS1=$(cygpath -w "$PS1_HELPER")
                fi
                debug "INVOKE $PS_BIN -File $WIN_PS1"
                "$PS_BIN" -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass \
                    -File "$WIN_PS1" -Title "$TITLE" -Body "$BODY" \
                    >/dev/null 2>&1 &
                disown 2>/dev/null || true
                debug "EXIT after background ps1"
                exit 0
            fi
            debug "FAIL no PS_BIN found"
        fi
        ;;
esac

debug "UNIX path"

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
    printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY"
}

if tty_path=$(find_owner_tty); then
    debug "UNIX wrote to $tty_path"
    emit > "$tty_path" 2>/dev/null || true
else
    debug "UNIX fallback /dev/tty + stdout"
    emit > /dev/tty 2>/dev/null || emit || true
fi
