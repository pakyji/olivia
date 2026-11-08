/**
 * Olivia Thomas — Memory/Notebook System
 * Inspired by Andee's notebook: 8 topics, persistent localStorage
 * Topics: self, cares, diary, plan, people, wiki, memories, todos
 */

const MEMORY_KEY = "olivia.memory.v1";
const TODO_KEY = "olivia.todos.v1";
const SCENES_KEY = "olivia.scenes.v1";

const VALID_TOPICS = [
  "self",      // Who the user is, preferences, identity
  "cares",     // What matters to them (projects, goals, health)
  "diary",     // Daily logs, reflections
  "plan",      // Upcoming commitments, schedule
  "people",    // Important people, contacts, relationships
  "wiki",      // Reference knowledge, facts
  "memories",  // Shared moments, anecdotes
  "todos"      // Active promises/tasks (mirrored in TODO_KEY)
];

// Default scenes (reusable routines)
const DEFAULT_SCENES = {
  morning: {
    name: "Morning Briefing",
    description: "Start the day with time, battery, weather, and top todos",
    steps: [
      { type: "say", text: "Good morning! Here's your briefing." },
      { type: "cmd", action: "time?" },
      { type: "cmd", action: "battery status" },
      { type: "cmd", action: "todolist" }
    ]
  },
  focus: {
    name: "Focus Mode",
    description: "Minimize distractions, show current task",
    steps: [
      { type: "say", text: "Focus mode activated. Current task:" },
      { type: "cmd", action: "todolist" }
    ]
  },
  evening: {
    name: "Evening Wrap",
    description: "Review day, log diary, plan tomorrow",
    steps: [
      { type: "say", text: "Evening wrap-up. How did today go?" },
      { type: "cmd", action: "todolist" },
      { type: "say", text: "Want to log anything to your diary?" }
    ]
  },
  backup: {
    name: "Backup & Sync",
    description: "Zip current project and push to GitHub",
    steps: [
      { type: "cmd", action: "zip project" },
      { type: "cmd", action: "push to github" }
    ]
  }
};

function loadMemory() {
  try {
    const raw = localStorage.getItem(MEMORY_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return {};
}

function saveMemory(mem) {
  try {
    localStorage.setItem(MEMORY_KEY, JSON.stringify(mem));
  } catch (e) {}
}

function loadTodos() {
  try {
    const raw = localStorage.getItem(TODO_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return [];
}

function saveTodos(todos) {
  try {
    localStorage.setItem(TODO_KEY, JSON.stringify(todos));
  } catch (e) {}
}

function loadScenes() {
  try {
    const raw = localStorage.getItem(SCENES_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return { ...DEFAULT_SCENES };
}

function saveScenes(scenes) {
  try {
    localStorage.setItem(SCENES_KEY, JSON.stringify(scenes));
  } catch (e) {}
}

// --- Public API ---

function recall(topic, key) {
  const mem = loadMemory();
  if (!topic) {
    // Return all topics summary
    const summary = {};
    for (const t of VALID_TOPICS) {
      summary[t] = mem[t] ? Object.keys(mem[t]).length : 0;
    }
    return { ok: true, data: summary };
  }
  if (!VALID_TOPICS.includes(topic)) {
    return { ok: false, error: `Invalid topic. Valid: ${VALID_TOPICS.join(", ")}` };
  }
  if (!key) {
    return { ok: true, data: mem[topic] || {} };
  }
  const val = mem[topic]?.[key];
  return { ok: true, data: val !== undefined ? val : null };
}

function remember(topic, key, value) {
  if (!VALID_TOPICS.includes(topic)) {
    return { ok: false, error: `Invalid topic. Valid: ${VALID_TOPICS.join(", ")}` };
  }
  const mem = loadMemory();
  if (!mem[topic]) mem[topic] = {};
  mem[topic][key] = { value, updated: Date.now() };
  saveMemory(mem);
  return { ok: true, detail: `Remembered ${topic}.${key}` };
}

function forget(topic, key) {
  if (!VALID_TOPICS.includes(topic)) {
    return { ok: false, error: `Invalid topic. Valid: ${VALID_TOPICS.join(", ")}` };
  }
  const mem = loadMemory();
  if (!mem[topic] || !(key in mem[topic])) {
    return { ok: false, error: `Key not found: ${topic}.${key}` };
  }
  delete mem[topic][key];
  saveMemory(mem);
  return { ok: true, detail: `Forgot ${topic}.${key}` };
}

function notebook() {
  const mem = loadMemory();
  const todos = loadTodos();
  const scenes = loadScenes();
  let out = "📓 **Olivia's Notebook**\n\n";
  for (const t of VALID_TOPICS) {
    const entries = mem[t] || {};
    out += `**${t.toUpperCase()}** (${Object.keys(entries).length} entries)\n`;
    for (const [k, v] of Object.entries(entries)) {
      out += `  • ${k}: ${typeof v === 'object' ? v.value : v}\n`;
    }
    out += "\n";
  }
  out += `**SCENES** (${Object.keys(scenes).length})\n`;
  for (const [k, v] of Object.entries(scenes)) {
    out += `  • ${k}: ${v.name} — ${v.description}\n`;
  }
  out += `\n**ACTIVE TODOS** (${todos.length})\n`;
  for (const t of todos) {
    const due = t.due ? new Date(t.due).toLocaleTimeString() : "no due";
    out += `  • [${t.done ? "✓" : " "}] ${t.text} (due: ${due})\n`;
  }
  return { ok: true, data: out };
}

function todolist() {
  const todos = loadTodos();
  if (!todos.length) return { ok: true, data: "No todos. Add one with: todo <minutes> <description>" };
  let out = "✅ **Your Todos**\n\n";
  for (let i = 0; i < todos.length; i++) {
    const t = todos[i];
    const due = t.due ? ` ⏰ ${new Date(t.due).toLocaleString()}` : "";
    const done = t.done ? "✓ " : "";
    out += `${i + 1}. ${done}${t.text}${due}\n`;
  }
  return { ok: true, data: out };
}

function todo(minutes, text) {
  if (!minutes || !text) {
    return { ok: false, error: "Usage: todo <minutes> <description>" };
  }
  const mins = parseInt(minutes, 10);
  if (isNaN(mins) || mins <= 0) {
    return { ok: false, error: "Minutes must be a positive number" };
  }
  const todos = loadTodos();
  const due = Date.now() + mins * 60 * 1000;
  todos.push({ text, due, done: false, created: Date.now() });
  saveTodos(todos);
  // Schedule notification
  setTimeout(() => {
    const updated = loadTodos();
    const idx = updated.findIndex(t => t.text === text && t.due === due);
    if (idx >= 0 && !updated[idx].done) {
      // Trigger a local notification via the app
      if (window.ullah && window.ullah.localReply) {
        window.ullah.localReply(`[quiet] ⏰ Reminder: ${text}`);
      }
    }
  }, mins * 60 * 1000);
  return { ok: true, detail: `Todo added: "${text}" in ${mins} minute(s)` };
}

function todoDone(index) {
  const todos = loadTodos();
  const idx = parseInt(index, 10) - 1;
  if (idx < 0 || idx >= todos.length) {
    return { ok: false, error: "Invalid todo number" };
  }
  todos[idx].done = true;
  saveTodos(todos);
  return { ok: true, detail: `Marked done: ${todos[idx].text}` };
}

function scene(name) {
  const scenes = loadScenes();
  if (!name) {
    let out = "🎬 **Available Scenes**\n\n";
    for (const [k, v] of Object.entries(scenes)) {
      out += `• **${k}**: ${v.name} — ${v.description}\n`;
    }
    out += "\nRun with: `scene <name>`";
    return { ok: true, data: out };
  }
  const s = scenes[name];
  if (!s) {
    return { ok: false, error: `Scene not found: ${name}. Run \`scene\` to list.` };
  }
  // Execute scene steps - this returns the steps for the frontend to execute
  return { ok: true, data: { scene: name, steps: s.steps, description: s.description } };
}

function saveScene(name, sceneDef) {
  const scenes = loadScenes();
  scenes[name] = sceneDef;
  saveScenes(scenes);
  return { ok: true, detail: `Scene saved: ${name}` };
}

// Export for Node (server.js) and browser (app.js)
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    recall, remember, forget, notebook, todolist, todo, todoDone, scene, saveScene,
    loadMemory, saveMemory, loadTodos, saveTodos, loadScenes, saveScenes,
    VALID_TOPICS, DEFAULT_SCENES
  };
} else {
  window.oliviaMemory = {
    recall, remember, forget, notebook, todolist, todo, todoDone, scene, saveScene
  };
}