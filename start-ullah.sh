#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — start in BACKGROUND (survives closing the Termux window)
cd "$(dirname "$0")" || exit 1
termux-wake-lock 2>/dev/null
pkill -f "node server.js" 2>/dev/null
sleep 0.5
nohup node server.js > server.log 2>&1 &
echo $! > server.pid
disown 2>/dev/null
termux-notification --id olivia --title "Olivia is running" --content "http://127.0.0.1:8080" 2>/dev/null
echo "Olivia running in background (pid $(cat server.pid 2>/dev/null)). Log: tail -f server.log"
echo "Stop karne ke liye: bash stop-ullah.sh"
