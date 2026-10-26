#!/bin/sh
# Forwards Claude Code / Codex hook events to Boring Notch via the boringnotch:// URL scheme.
#
# Claude Code: /bin/sh ".../agent-hook.sh" claude   (hooks in ~/.claude/settings.json, JSON on stdin)
# Codex:       /bin/sh ".../agent-hook.sh" codex    (hooks in ~/.codex/hooks.json, JSON on stdin)
#
# Always exits 0 so it never blocks the agent.

src="$1"
payload=$(cat)

field() {
    printf '%s' "$payload" | tr '\n' ' ' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

b64url() {
    printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'
}

event=$(field hook_event_name)
session=$(field session_id)
cwd=$(field cwd)
tool=$(field tool_name)
[ -z "$session" ] && session="unknown"

state_dir="${TMPDIR:-/tmp}/boringnotch-agents"
mkdir -p "$state_dir"
waiting="$state_dir/$session.waiting"
heartbeat="$state_dir/$session.heartbeat"

case "$event" in
    PreToolUse|PostToolUse)
        # Fires on every tool call: report right away when the session was waiting for the user,
        # otherwise at most every 30 seconds as a heartbeat.
        if [ -f "$waiting" ]; then
            rm -f "$waiting"
        elif [ -n "$(find "$heartbeat" -mtime -30s 2>/dev/null)" ]; then
            exit 0
        fi
        touch "$heartbeat"
        ;;
    Notification|PermissionRequest)
        : > "$waiting"
        ;;
    UserPromptSubmit|Stop|Interrupt|SessionEnd)
        rm -f "$waiting" "$heartbeat"
        ;;
esac

# Chat title, looked up only on state changes.
title=""
case "$event" in
    UserPromptSubmit|Stop|Notification|PermissionRequest)
        if [ "$src" = "codex" ]; then
            db="${CODEX_HOME:-$HOME/.codex}/state_5.sqlite"
            [ -f "$db" ] && title=$(/usr/bin/sqlite3 -readonly "$db" \
                "select coalesce(nullif(name,''), substr(title,1,80)) from threads where id='$(printf '%s' "$session" | tr -cd 'A-Za-z0-9-')';" 2>/dev/null)
        else
            transcript=$(field transcript_path)
            [ -f "$transcript" ] && title=$(grep '"type":"custom-title"' "$transcript" | tail -n 1 \
                | sed -n 's/.*"customTitle":"\([^"]*\)".*/\1/p')
        fi
        ;;
esac

open -g "boringnotch://agent?src=$src&event=$event&session=$session&cwd=$(b64url "$cwd")&title=$(b64url "$title")&tool=$(b64url "$tool")" >/dev/null 2>&1
exit 0
