#!/bin/bash
# Simple smoke test to check if server.js exists
if [ -f "server.js" ]; then
    echo "Smoke test passed: server.js found."
    exit 0
else
    echo "Smoke test failed: server.js not found."
    exit 1
fi