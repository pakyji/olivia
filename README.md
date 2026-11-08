# Olivia Thomas 🎙️

**Voice-first personal AI assistant & coding agent** — Android APK + PWA. She listens, understands, and **answers out loud**. JARVIS-class capabilities with a premium glass UI.

[![Build APK](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml/badge.svg)](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/pakyji/olivia?label=APK)](https://github.com/pakyji/olivia/releases/latest)

## ✨ Features

- 🎙 **Voice in / voice out** — Web Speech API: speak, and hear the answer spoken back
- 🌐 **3 languages** — English (default), Roman Urdu, Italian — switch from the ☰ menu, strictly enforced by the persona
- 👩 **Olivia Thomas persona** — warm, confident companion (JARVIS-style), female-first TTS voices
- 🔊 **TTS v3 engine** — female voice priority, sentence chunking, GC-safe utterances, resume watchdog, speed slider
- 🗣 **Wake word** — say "Olivia" in conversation mode to address her (optional toggle)
- ⚡ **JARVIS instant commands** — "time?", "battery status", "system report" → answered locally, instantly, out loud
- 📱 **Opens mobile apps** — "open whatsapp", "open youtube", "open camera", … (18 apps mapped)
- 🛠 **Builds & delivers projects** — save code blocks, `run <file>`, `zip project` → download link, `push to github`
- 💬 **Conversation loop** — hands-free continuous dialogue
- 🟢 **Health pill** — live server + brain (gateway) status
- 🌙 **Premium glass UI** — gradient mesh background, glassmorphism panels, slide-in menu drawer
- 🌗 **Background mode** — `start-olivia.sh` keeps the server alive in background (wake-lock + notification)
- 💾 **Chat history** — localStorage; clear from the drawer
- 📱 **PWA + APK** — install to home screen, or WebView APK from Releases
- 🔐 **Zero dependencies** — Node stdlib server, vanilla JS front-end

### 🧠 Andee-Inspired Intelligence (NEW)

- 📓 **Persistent Notebook** — 8 topics: `self`, `cares`, `diary`, `plan`, `people`, `wiki`, `memories`, `todos`
  - `recall [topic] [key]` — read a fact
  - `remember <topic> <key> <value>` — store a fact
  - `forget <topic> <key>` — delete a fact
  - `notebook` — show full notebook summary
- ✅ **Todo System** — promises with due times
  - `todo <minutes> <description>` — schedule a promise/reminder
  - `todolist` — show all pending todos
  - `todo done <number>` — mark complete
- 🎬 **Scenes/Routines** — reusable command sequences
  - `scene` — list available scenes
  - `scene <name>` — run a scene (morning, focus, evening, backup)
  - `save_scene` — create custom scenes
- 📬 **Notification Reading** — `notifications` — list active notifications (via Termux:API)
- 🎭 **Mood-Aware TTS** — responses include `[happy]`, `[calm]`, `[curious]`, `[concerned]`, `[playful]`, `[quiet]` markers
- ⏰ **Proactive Heartbeat** — background checks every 20 min for:
  - Overdue todos
  - Evening diary prompts (6-10 PM)
  - Scene suggestions (morning briefing, focus mode, evening wrap)
- 🔄 **Self-Review** — end-of-conversation reflection (internal, updates notebook)

## 🚀 Quick start (phone / Termux)

```bash
cd ~/olivia && bash start-olivia.sh
# stop with: bash stop-olivia.sh
```

Then either:

- **APK** — [Releases → app-debug.apk](https://github.com/pakyji/olivia/releases/latest), install and open.
- **Browser / PWA** — Chrome: `http://127.0.0.1:8080` → Add to Home screen.

## 🎙 Voice & menu guide

| Control | What it does |
|---|---|
| 🎙 Mic | speak → text → Olivia answers |
| 🔊 TTS / 🔔 Test / ⏹ Stop | speech on-off / test voice / stop speaking |
| Conversation | hands-free loop |
| ☰ Menu | language, speech speed, wake word, new chat |

## 🤖 JARVIS command examples

| Say / type | Result |
|---|---|
| `time?` / `battery status` / `system report` | instant spoken device info |
| `open whatsapp` / `open youtube` / `open camera` | launches the app |
| `open https://...` | opens URL |
| `Save` button on any code block | saves it into `projects/myapp/` |
| `zip project` | builds a ZIP and returns a download link |
| `run server.js` | runs a saved file and reports output |
| `push to github` | git add + commit + push from the phone |
| `send sms to +39...: hello` | sends an SMS via Termux:API |
| `scroll down` / `scroll up` / `go back` / `go home` | controls the open app (JARVIS-style) |
| `tap 360 800` | taps screen coordinates |
| `suggest a movie` | movie suggestions, conversational |
| `remind me in 15 minutes to drink water` | natural language reminders |

### 🧠 Memory & Notebook Commands (NEW)

| Command | Example |
|---|---|
| `recall` | Show all notebook topics summary |
| `recall self` | Show all entries in "self" topic |
| `recall self name` | Get specific key from topic |
| `remember self name Alex` | Store "Alex" in self.name |
| `forget self name` | Delete self.name |
| `notebook` | Full notebook dump (all 8 topics + scenes + todos) |
| `todo 30 Call mom` | Schedule reminder in 30 minutes |
| `todolist` | List all active todos with due times |
| `todo done 1` | Mark first todo as complete |
| `scene` | List available scenes |
| `scene morning` | Run morning briefing scene |
| `scene focus` | Run focus mode scene |
| `scene evening` | Run evening wrap scene |
| `notifications` | List active Android notifications |

### 🎭 Mood Markers (for expressive TTS)

Include these in your responses for voice expression:
- `[happy]` — cheerful, warm
- `[calm]` — steady, reassuring
- `[curious]` — interested, engaged
- `[concerned]` — empathetic, gentle
- `[playful]` — light, witty
- `[quiet]` — suppress TTS for this segment
- `[END]` — end of turn marker

## 🧪 Tests

```bash
bash tests/smoke.sh
```

## 🛠 Troubleshooting

| Symptom | Fix |
|---|---|
| `ERR_CONNECTION_REFUSED` | run `bash start-olivia.sh` in Termux |
| No replies | start `omniroute` in session 1 (pill shows 🟠) |
| No voice | press 🔔 Test; check 🔊 TTS on; install Google TTS voices |
| Old UI showing | force-stop the APK and reopen (service-worker cache refresh) |
| Mic denied | Settings → Apps → Olivia → Permissions → Microphone → Allow |
| SMS fails | install Termux:API app + `pkg install termux-api`, grant SMS permission |
| Notifications not working | install Termux:API app + `pkg install termux-api`, grant notification permission |

## 📦 APK build

Every push triggers GitHub Actions: debug APK published to **Releases** (tag `apk-v<run>`).

## 🏗 Architecture

```
olivia/
├── server.js          # Node stdlib HTTP server (chat proxy, actions, memory)
├── memory.js          # Shared memory/notebook/todo/scene logic (Node + browser)
├── heartbeat.js       # Proactive scheduler (20-min interval, nudges)
├── app.js             # Front-end: chat, streaming, markdown, localStorage
├── voice.js           # Web Speech API: STT, TTS v3, wake word, conversation loop
├── extra.js           # JARVIS commands, drawer, chips, device actions
├── index.html         # Single-file PWA (glass UI, voice bar, chips, drawer)
├── persona.txt        # System prompt (Olivia Thomas identity + rules)
├── start-olivia.sh    # Dual watchdog: server + brain (OmniRoute)
├── stop-olivia.sh     # Clean shutdown
├── android/           # WebView APK project (GitHub Actions builds)
└── tests/             # Smoke test
```

## 🔧 Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | Server port |
| `OMNIROUTE_URL` | `http://127.0.0.1:20128` | LLM gateway endpoint |
| `OMNIROUTE_KEY` | `omniroute-local` | Gateway API key |
| `OLIVIA_AUTH_TOKEN` | `change-me-in-prod` | Bearer token for API auth |

## 📜 License

MIT — Use freely, modify, share. Attribution appreciated.

---

_She listens. She understands. She speaks. Remembers. Plans. Cares. 💜_