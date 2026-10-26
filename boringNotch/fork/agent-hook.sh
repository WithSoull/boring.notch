#!/bin/sh
# Forwards Claude Code / Codex hook events to Boring Notch via the boringnotch:// URL scheme.
#
# Claude Code: /bin/sh ".../agent-hook.sh" claude   (hooks in ~/.claude/settings.json, JSON on stdin)
# Codex:       /bin/sh ".../agent-hook.sh" codex    (hooks in ~/.codex/hooks.json, JSON on stdin)
#
# Always exits 0 so it never blocks the agent.

src="$1"
# plutil rejects escaped NUL characters, which tool output can contain.
payload=$(sed 's/\\u0000//g')

# Top-level string field of the JSON payload; empty when missing or the payload isn't valid JSON.
field() {
    printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null
}

b64url() {
    printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'
}

event=$(field hook_event_name)
session=$(field session_id)
cwd=$(field cwd)
tool=$(field tool_name)
ntype=$(field notification_type | tr -cd 'a-z_')
[ -z "$event" ] && exit 0
[ -z "$session" ] && session="unknown"
session=$(printf '%s' "$session" | tr -cd 'A-Za-z0-9_-')

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
    UserPromptSubmit|Stop|Interrupt)
        rm -f "$waiting" "$heartbeat"
        ;;
    SessionEnd)
        rm -f "$waiting" "$heartbeat" "$state_dir/$session.desktop"
        ;;
esac

# Claude desktop sessions have their own id ("local_…") that deep links need, and the title shown in the app.
# The session file is found once and remembered.
chat=""
desktop_file=""
if [ "$src" = "claude" ]; then
    link="$state_dir/$session.desktop"
    if [ ! -f "$link" ]; then
        sessions_dir="$HOME/Library/Application Support/Claude/claude-code-sessions"
        [ -d "$sessions_dir" ] && grep -rlF --include='local_*.json' "\"cliSessionId\":\"$session\"" "$sessions_dir" 2>/dev/null \
            | head -n 1 > "$link"
    fi
    desktop_file=$(cat "$link" 2>/dev/null)
    [ -f "$desktop_file" ] && chat=$(basename "$desktop_file" .json)
fi

# Chat title, looked up only on state changes.
title=""
case "$event" in
    UserPromptSubmit|Stop|Notification|PermissionRequest)
        if [ "$src" = "codex" ]; then
            db="${CODEX_HOME:-$HOME/.codex}/state_5.sqlite"
            [ -f "$db" ] && title=$(/usr/bin/sqlite3 -readonly "$db" \
                "select coalesce(nullif(name,''), substr(title,1,80)) from threads where id='$(printf '%s' "$session" | tr -cd 'A-Za-z0-9-')';" 2>/dev/null)
        elif [ -f "$desktop_file" ]; then
            title=$(sed 's/\\u0000//g' "$desktop_file" | /usr/bin/plutil -extract title raw -o - - 2>/dev/null)
        fi
        if [ "$src" = "claude" ] && [ -z "$title" ]; then
            transcript=$(field transcript_path)
            [ -f "$transcript" ] && title=$(grep '"type":"custom-title"' "$transcript" | tail -n 1 \
                | sed -n 's/.*"customTitle":"\([^"]*\)".*/\1/p')
        fi
        ;;
esac

open -g "boringnotch://agent?src=$src&event=$event&session=$session&cwd=$(b64url "$cwd")&title=$(b64url "$title")&tool=$(b64url "$tool")&chat=$chat&ntype=$ntype" >/dev/null 2>&1
exit 0
