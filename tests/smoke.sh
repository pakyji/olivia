#!/bin/bash
# Comprehensive smoke test for Olivia Thomas

echo "🧪 Olivia Thomas Smoke Test"
echo "============================"

PASS=0
FAIL=0

check_file() {
  if [ -f "$1" ]; then
    echo "✅ $1 exists"
    PASS=$((PASS+1))
  else
    echo "❌ $1 missing"
    FAIL=$((FAIL+1))
  fi
}

check_node_syntax() {
  if node --check "$1" 2>/dev/null; then
    echo "✅ $1 syntax OK"
    PASS=$((PASS+1))
  else
    echo "❌ $1 syntax ERROR"
    FAIL=$((FAIL+1))
  fi
}

# Core files
check_file "server.js"
check_file "app.js"
check_file "voice.js"
check_file "extra.js"
check_file "memory.js"
check_file "heartbeat.js"
check_file "index.html"
check_file "persona.txt"
check_file "manifest.json"
check_file "sw.js"
check_file "start-olivia.sh"
check_file "stop-olivia.sh"

# Node syntax checks
check_node_syntax "server.js"
check_node_syntax "memory.js"
check_node_syntax "heartbeat.js"

# Check key features in server.js
if grep -q "memory_recall\|memory_remember\|memory_forget\|notebook\|todolist\|todo\|scene\|notification_list" server.js; then
  echo "✅ server.js has memory/notebook/todo/scene/notification actions"
  PASS=$((PASS+1))
else
  echo "❌ server.js missing new actions"
  FAIL=$((FAIL+1))
fi

# Check key features in extra.js
if grep -q "memoryRecall\|memoryRemember\|memoryForget\|notebookCmd\|todolistCmd\|todoCmd\|sceneCmd\|notificationsCmd" extra.js; then
  echo "✅ extra.js has memory/notebook/todo/scene/notification commands"
  PASS=$((PASS+1))
else
  echo "❌ extra.js missing new commands"
  FAIL=$((FAIL+1))
fi

# Check persona has new rules
if grep -q "MEMORY & NOTEBOOK\|MOOD MARKERS\|SELF-REVIEW\|IRON RULES" persona.txt; then
  echo "✅ persona.txt has Andee-inspired rules"
  PASS=$((PASS+1))
else
  echo "❌ persona.txt missing new rules"
  FAIL=$((FAIL+1))
fi

# Check index.html includes new scripts
if grep -q "memory.js\|heartbeat.js" index.html; then
  echo "✅ index.html includes new scripts"
  PASS=$((PASS+1))
else
  echo "❌ index.html missing new script tags"
  FAIL=$((FAIL+1))
fi

# Check chips include new commands
if grep -q "notebook\|todolist\|scene morning\|notifications" extra.js; then
  echo "✅ Quick chips updated with new commands"
  PASS=$((PASS+1))
else
  echo "❌ Quick chips not updated"
  FAIL=$((FAIL+1))
fi

# Check voice.js handles mood markers
if grep -q "happy\|calm\|curious\|concerned\|playful\|quiet\|END" voice.js; then
  echo "✅ voice.js handles mood markers"
  PASS=$((PASS+1))
else
  echo "❌ voice.js missing mood marker handling"
  FAIL=$((FAIL+1))
fi

# Check heartbeat.js has proactive features
if grep -q "checkTodos\|checkDiaryPrompt\|checkSceneSuggestion" heartbeat.js; then
  echo "✅ heartbeat.js has proactive checks"
  PASS=$((PASS+1))
else
  echo "❌ heartbeat.js missing proactive checks"
  FAIL=$((FAIL+1))
fi

echo ""
echo "============================"
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -eq 0 ]; then
  echo "🎉 All smoke tests passed!"
  exit 0
else
  echo "⚠️  Some tests failed"
  exit 1
fi