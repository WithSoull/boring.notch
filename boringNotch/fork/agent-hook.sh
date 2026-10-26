#!/bin/sh
# Forwards Claude Code / Codex hook events to Boring Notch via the boringnotch:// URL scheme.
#
# Claude Code: /bin/sh ".../agent-hook.sh" claude          (hook JSON on stdin)
# Codex:       notify = ["/bin/sh", ".../agent-hook.sh", "codex", <optional previous notify command…>]
#              Codex appends the JSON as the last argument; any previous notify command is run with it too.
#
# Always exits 0 so it never blocks the agent.

src="$1"
shift
if [ "$src" = "codex" ]; then
    for payload in "$@"; do :; done
    # Chain to the notify command this hook replaced (all args except the JSON, then the JSON).
    if [ "$#" -gt 1 ]; then
        "$@" >/dev/null 2>&1 &
    fi
else
    payload=$(cat)
fi

field() {
    printf '%s' "$payload" | tr '\n' ' ' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

b64url() {
    printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'
}

if [ "$src" = "codex" ]; then
    event=$(field type)
    session=$(field thread-id)
else
    event=$(field hook_event_name)
    session=$(field session_id)
fi
cwd=$(field cwd)
[ -z "$session" ] && session="unknown"

# PostToolUse fires on every tool call: only report it when the session was waiting for the user.
marker="${TMPDIR:-/tmp}/boringnotch-waiting-$session"
case "$event" in
    PostToolUse)
        [ -f "$marker" ] || exit 0
        rm -f "$marker"
        ;;
    Notification)
        : > "$marker"
        ;;
    UserPromptSubmit|Stop|SessionEnd)
        rm -f "$marker"
        ;;
esac

open -g "boringnotch://agent?src=$src&event=$event&session=$session&cwd=$(b64url "$cwd")" >/dev/null 2>&1
exit 0
