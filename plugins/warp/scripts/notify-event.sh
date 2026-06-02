#!/bin/bash
# Emit an arbitrary structured warp://cli-agent event from any driver: a loop
# skill, a scheduler (e.g. `goal`), or a manual test. Thin wrapper over
# build-payload.sh + warp-notify.sh so callers don't reimplement the OSC 777
# plumbing or protocol negotiation.
#
# Usage:
#   notify-event.sh <event> [--arg KEY VALUE]... [--argjson KEY JSON]...
#
# The `scheduled` event drives Warp's SCHEDULED sidebar bucket — emit it when a
# loop has queued the next turn so the row reads "will run again" instead of
# "idle, waiting on a human". Carry a `next_in` hint for the run cadence:
#
#   echo '{"session_id":"'"$SID"'","cwd":"'"$PWD"'"}' \
#     | notify-event.sh scheduled --arg next_in 5m
#
# Hook context (session_id, cwd) is read from stdin JSON when piped. When stdin
# is empty, session_id is blank and cwd defaults to $PWD — fine for manual
# tests, but a real loop driver must supply the live session_id so Warp updates
# the correct sidebar row.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-payload.sh
source "$SCRIPT_DIR/build-payload.sh"

EVENT="${1:?usage: notify-event.sh <event> [--arg KEY VALUE]...}"
shift

# Translate `--arg KEY VALUE` / `--argjson KEY JSON` pairs into build_payload
# (jq) args. build_payload merges them into the payload via $ARGS.named.
JQ_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --arg)
            JQ_ARGS+=(--arg "$2" "$3"); shift 3 ;;
        --argjson)
            JQ_ARGS+=(--argjson "$2" "$3"); shift 3 ;;
        *)
            echo "notify-event.sh: unknown arg '$1'" >&2
            exit 2 ;;
    esac
done

# Read the hook JSON from stdin when piped; otherwise synthesize a minimal one
# so session_id/cwd extraction in build_payload doesn't choke.
INPUT=""
if [ ! -t 0 ]; then
    INPUT="$(cat)"
fi
if [ -z "$INPUT" ]; then
    INPUT=$(jq -nc --arg cwd "$PWD" '{cwd:$cwd}')
fi

# `${JQ_ARGS[@]+...}` guards against the unbound-variable error set -u raises on
# an empty array under macOS bash 3.2.
BODY=$(build_payload "$INPUT" "$EVENT" ${JQ_ARGS[@]+"${JQ_ARGS[@]}"})
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
