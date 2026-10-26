#!/bin/sh
# Claude Code statusLine bridge for Boring Notch.
#
#   "statusLine": {"type": "command", "command": "/bin/sh '/Applications/Boring Notch.app/Contents/Resources/claude-statusline.sh'"}
#
# Claude Code (terminal and desktop) runs it after each response with session JSON on stdin, which includes
# the subscription limits (rate_limits.five_hour / seven_day: used_percentage, resets_at). The script saves
# just those numbers where the sandboxed app can read them, and prints a short status line for the terminal.
# No tokens, no network. Always exits 0.

payload=$(sed 's/\\u0000//g')

# A number from the payload (digits and dot only, so it can go into JSON as is); empty when missing.
value() {
    printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null | tr -cd '0-9.'
}

five_used=$(value rate_limits.five_hour.used_percentage)
five_resets=$(value rate_limits.five_hour.resets_at)
week_used=$(value rate_limits.seven_day.used_percentage)
week_resets=$(value rate_limits.seven_day.resets_at)

# Absent before the session's first response and for non-subscription logins: keep the last saved numbers.
if [ -n "$five_used$week_used" ]; then
    dir="$HOME/Library/Containers/theboringteam.boringnotch/Data/Library/Application Support"
    mkdir -p "$dir"
    window() {
        [ -n "$1" ] || return
        printf '"%s":{"used":%s' "$3" "$1"
        [ -n "$2" ] && printf ',"resetsAt":%s' "$2"
        printf '},'
    }
    tmp="$dir/.claude-limits.$$"
    {
        printf '{'
        window "$five_used" "$five_resets" fiveHour
        window "$week_used" "$week_resets" week
        printf '"updatedAt":%s}\n' "$(date +%s)"
    } > "$tmp" && mv -f "$tmp" "$dir/claude-limits.json"
fi

left() {
    printf '%s' "$1" | awk '{ v = 100 - $1; if (v < 0) v = 0; printf "%d%%", v + 0.5 }'
}
line=""
[ -n "$five_used" ] && line="5h $(left "$five_used") left"
[ -n "$week_used" ] && line="${line:+$line · }week $(left "$week_used") left"
printf '%s\n' "$line"
exit 0
