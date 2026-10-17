#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — stop server + watchdog
cd "$(dirname "$0")" || exit 1
pkill -f "olivia-watchdog" 2>/dev/null
pkill -f "node server.js" 2>/dev/null
termux-notification --id olivia --delete 2>/dev/null
termux-wake-unlock 2>/dev/null
rm -f server.pid
echo "Olivia stopped (watchdog bhi band)."
