#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — background + WATCHDOG (crash hone pe 2s mein auto-restart)
cd "$(dirname "$0")" || exit 1
termux-wake-lock 2>/dev/null
pkill -f "olivia-watchdog" 2>/dev/null
pkill -f "node server.js" 2>/dev/null
sleep 0.5
nohup bash -c 'olivia-watchdog; while true; do node server.js >> server.log 2>&1; echo "[watchdog] restart $(date)" >> server.log; sleep 2; done' > /dev/null 2>&1 &
disown 2>/dev/null
termux-notification --id olivia --title "Olivia is running" --content "http://127.0.0.1:8080 (watchdog on)" 2>/dev/null
echo "Olivia running with WATCHDOG. Log: tail -f server.log"
echo "To stop: bash stop-olivia.sh"
