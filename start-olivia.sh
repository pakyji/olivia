#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — DUAL WATCHDOG: server + brain, dono crash pe 2s mein auto-restart
cd "$(dirname "$0")" || exit 1
termux-wake-lock 2>/dev/null
pkill -f "olivia-watchdog" 2>/dev/null
pkill -f "olivia-braindog" 2>/dev/null
pkill -f "node server.js" 2>/dev/null
pkill -f "omniroute" 2>/dev/null
sleep 0.5
nohup bash -c 'olivia-watchdog; while true; do node server.js >> server.log 2>&1; echo "[watchdog] server restart $(date)" >> server.log; sleep 2; done' > /dev/null 2>&1 &
nohup bash -c 'olivia-braindog; while true; do omniroute >> omniroute.log 2>&1; echo "[braindog] omniroute restart $(date)" >> omniroute.log; sleep 2; done' > /dev/null 2>&1 &
disown 2>/dev/null
termux-notification --id olivia --title "Olivia is running" --content "server+brain watchdog ON" 2>/dev/null
echo "Olivia: server-watchdog + brain-watchdog ON."
echo "Logs: tail -f server.log | tail -f omniroute.log"
echo "To stop: bash stop-olivia.sh"
