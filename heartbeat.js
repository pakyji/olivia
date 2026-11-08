/**
 * Olivia Thomas — Proactive Scheduler (Andee-inspired Heartbeat)
 * Runs background checks for overdue todos, diary prompts, scene suggestions
 * Inspired by Andee's Heartbeat.kt and SelfWork.kt
 */

(function () {
  const HEARTBEAT_INTERVAL = 20 * 60 * 1000; // 20 minutes (Andee default)
  const NUDGE_KEY = "olivia.nudges.v1";

  let nudges = [];
  let lastHeartbeat = 0;

  function loadNudges() {
    try {
      const raw = localStorage.getItem(NUDGE_KEY);
      if (raw) nudges = JSON.parse(raw);
    } catch (e) {}
  }

  function saveNudges() {
    try {
      localStorage.setItem(NUDGE_KEY, JSON.stringify(nudges));
    } catch (e) {}
  }

  function addNudge(text, type = "info") {
    nudges.push({ text, type, time: Date.now(), shown: false });
    saveNudges();
  }

  function getPendingNudges() {
    return nudges.filter(n => !n.shown);
  }

  function markNudgeShown(index) {
    if (index >= 0 && index < nudges.length) {
      nudges[index].shown = true;
      saveNudges();
    }
  }

  // Check for overdue todos
  function checkTodos() {
    try {
      const todosRaw = localStorage.getItem("olivia.todos.v1");
      if (!todosRaw) return;
      const todos = JSON.parse(todosRaw);
      const now = Date.now();
      for (const t of todos) {
        if (!t.done && t.due && t.due < now) {
          const key = `overdue_${t.due}_${t.text}`;
          if (!nudges.some(n => n.text.includes(key))) {
            addNudge(`⏰ Overdue: ${t.text} (was due ${new Date(t.due).toLocaleTimeString()})`, "warning");
          }
        }
      }
    } catch (e) {}
  }

  // Check for diary prompt (evening)
  function checkDiaryPrompt() {
    const hour = new Date().getHours();
    if (hour >= 18 && hour <= 22) { // 6 PM - 10 PM
      const today = new Date().toDateString();
      const lastDiary = localStorage.getItem("olivia.lastDiaryPrompt");
      if (lastDiary !== today) {
        addNudge("📝 How was your day? Want to log something to your diary?", "diary");
        localStorage.setItem("olivia.lastDiaryPrompt", today);
      }
    }
  }

  // Check for scene suggestions based on time
  function checkSceneSuggestion() {
    const hour = new Date().getHours();
    if (hour >= 6 && hour <= 9) { // Morning
      const key = "scene_morning_" + new Date().toDateString();
      if (!nudges.some(n => n.text.includes(key))) {
        addNudge("🌅 Good morning! Run `scene morning` for your daily briefing?", "scene");
      }
    } else if (hour >= 9 && hour <= 11) { // Focus time
      const key = "scene_focus_" + new Date().toDateString();
      if (!nudges.some(n => n.text.includes(key))) {
        addNudge("🎯 Focus time! Run `scene focus` to see your current task?", "scene");
      }
    } else if (hour >= 18 && hour <= 21) { // Evening
      const key = "scene_evening_" + new Date().toDateString();
      if (!nudges.some(n => n.text.includes(key))) {
        addNudge("🌙 Evening wrap-up? Run `scene evening` to review your day.", "scene");
      }
    }
  }

  // Main heartbeat function
  function heartbeat() {
    lastHeartbeat = Date.now();
    checkTodos();
    checkDiaryPrompt();
    checkSceneSuggestion();

    // Show pending nudges via localReply if available
    const pending = getPendingNudges();
    if (pending.length > 0 && window.ullah && window.ullah.localReply) {
      // Only show one nudge per heartbeat to avoid spam
      const nudge = pending[0];
      window.ullah.localReply(`[${nudge.type === "warning" ? "concerned" : "calm"}] ${nudge.text}`);
      markNudgeShown(nudges.indexOf(nudge));
    }
  }

  // Public API
  window.oliviaHeartbeat = {
    start: () => {
      // Run immediately
      heartbeat();
      // Then on interval
      setInterval(heartbeat, HEARTBEAT_INTERVAL);
      console.log("Olivia heartbeat started (every 20 min)");
    },
    force: heartbeat,
    getNudges: getPendingNudges,
    addNudge,
    lastHeartbeat: () => lastHeartbeat
  };

  // Auto-start when loaded
  loadNudges();
  // Small delay to ensure app is ready
  setTimeout(() => {
    window.oliviaHeartbeat.start();
  }, 5000);

})();