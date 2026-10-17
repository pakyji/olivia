#!/data/data/com.termux/files/usr/bin/bash
# Start ULLAH with wake lock so it runs in background
termux-wake-lock
cd "$(dirname "$0")"
echo "ULLAH starting..."
node server.js
