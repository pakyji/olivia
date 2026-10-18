# Olivia Thomas 🎙️

**Voice-first personal AI assistant & coding agent** — Android APK + PWA. She listens, understands, and **answers out loud**. JARVIS-class capabilities with a premium glass UI.

[![Build APK](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml/badge.svg)](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/pakyji/olivia?label=APK)](https://github.com/pakyji/olivia/releases/latest)

## ✨ Features

- 🎙 **Voice in / voice out** — Web Speech API: speak, and hear the answer spoken back
- 🌐 **3 languages** — English (default), Roman Urdu, Italian — switch from the ☰ menu, strictly enforced by the persona
- 👩 **Olivia Thomas persona** — warm, confident companion (JARVIS-style), female-first TTS voices
- 🔊 **TTS v3 engine** — female voice priority, sentence chunking, GC-safe utterances, resume watchdog, speed slider
- 🗣 **Wake word** — say “Olivia” in conversation mode to address her (optional toggle)
- ⚡ **JARVIS instant commands** — “time?”, “battery status”, “system report” → answered locally, instantly, out loud
- 📱 **Opens mobile apps** — “open whatsapp”, “open youtube”, “open camera”, … (18 apps mapped)
- 🛠 **Builds & delivers projects** — save code blocks into projects, run them, and get a **ZIP download link**
- 🐙 **Pushes to GitHub** — “push to github” commits and pushes from the phone repo
- 💬 **Conversation loop** — hands-free continuous dialogue
- 🟢 **Health pill** — live server + brain (gateway) status
- 🌙 **Premium glass UI** — gradient mesh background, glassmorphism panels, slide-in menu drawer
- 🌗 **Background mode** — `start-olivia.sh` keeps the server alive in background (wake-lock + notification)
- 💾 **Chat history** — localStorage; clear from the drawer
- 📱 **PWA + APK** — install to home screen, or WebView APK from Releases
- 🔐 **Zero dependencies** — Node stdlib server, vanilla JS front-end

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

## 📦 APK build

Every push triggers GitHub Actions: debug APK published to **Releases** (tag `apk-v<run>`).

---

_She listens. She understands. She speaks. 💜_
