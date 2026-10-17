# Olivia Thomas 🎙️

**Voice-first personal AI assistant & coding agent** — Android APK + PWA. Sun-ti hai, samajh-ti hai, aur **bol kar** jawab deti hai. JARVIS-class features, premium glass UI.

[![Build APK](https://github.com/pakyji/ullah/actions/workflows/build-apk.yml/badge.svg)](https://github.com/pakyji/ullah/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/pakyji/ullah?label=APK)](https://github.com/pakyji/ullah/releases/latest)

## ✨ Features

- 🎙 **Voice in / voice out** — Web Speech API: bolo, jawab awaz mein suno
- 🌐 **3 languages** — English (default), Roman Urdu, Italian — menu se switch, strict persona enforcement
- 👩 **Olivia Thomas persona** — warm, confident personal assistant (female-first TTS voices)
- 🔊 **TTS v3 engine** — female voice priority, sentence-chunking, GC-safe utterances, resume-watchdog, speed slider
- 🗣 **Wake word** — conversation mode mein "Olivia" bol kar bulao (optional toggle)
- ⚡ **JARVIS-style instant commands** — "time?", "battery status", "system report" → local, instant, spoken
- 💬 **Conversation loop** — hands-free continuous baat-cheet
- 🟢 **Health pill** — live server + brain status
- ⚡ **Quick chips** — time?, battery status, system report, write code, find bug, explain it
-  **Model-agnostic** — OmniRoute gateway se koi bhi provider; API key server-side rehti hai
- 🌙 **Premium glass UI** — gradient mesh background, glassmorphism panels, slide-in menu drawer
- 🌗 **Background mode** — `start-ullah.sh` server ko background mein chalata hai (wake-lock + notification)
- 💾 **Chat history** — localStorage; drawer se clear
- 📱 **PWA + APK** — home-screen install ya WebView APK
- 🔐 **Zero dependencies** — Node stdlib server, vanilla JS front-end

## 🚀 Quick start (phone / Termux)

```bash
# Session 1 — brain (OmniRoute gateway)
omniroute

# Session 2 — Olivia server (background, port 8080)
cd ~/ullah && bash start-ullah.sh
# stop: bash stop-ullah.sh
```

Phir:

- **APK** — [Releases → app-debug.apk](https://github.com/pakyji/ullah/releases/latest) install karo, kholo.
- **Browser / PWA** — Chrome: `http://127.0.0.1:8080` → Add to Home screen.

## 🎙 Voice & menu guide

| Control | Kaam |
|---|---|
| 🎙 Mic | bolo → text → Olivia |
| 🔊 TTS / 🔔 Test / ⏹ Stop | bolna on-off / awaz test / roko |
| Conversation | hands-free loop |
| ☰ Menu | language, speech speed, wake word, clear chat |

## 🏗 Architecture

```
APK (WebView) ──▶ http://127.0.0.1:8080 ──▶ /api/chat (SSE) ──▶ OmniRoute :20128 ──▶ provider
   shell            server.js (Node stdlib)  + persona.txt         gateway           (Gemini etc.)
```

- `server.js` — static + `/api/chat` proxy (+ `lang` system-prompt injection)
- `app.js` — chat UI, markdown, history, local-reply API
- `voice.js` — recognition + TTS v3 (female-first, wake word)
- `extra.js` — menu drawer, JARVIS commands, chips, health pill
- `sw.js` — PWA shell (cache `ullah-v3`)
- `android/` — WebView wrapper; Actions har push pe APK → Releases

## 🧪 Test

```bash
bash tests/smoke.sh
```

## 🛠 Troubleshooting

| Symptom | Fix |
|---|---|
| `ERR_CONNECTION_REFUSED` | `bash start-ullah.sh` chalu nahi |
| Jawab nahi aata | Session 1 mein `omniroute` chalu karo (pill 🟠) |
| Awaz nahi aati | 🔔 Test dabao; 🔊 TTS on; phone mein Google TTS voices |
| Purana UI | APK force-stop → dobara kholo (sw cache v3 refresh) |
| Mic denied | Settings → Apps → Olivia → Microphone → Allow |

## 📦 APK build

Har push pe GitHub Actions debug APK → **Releases** (tag `apk-v<run>`).

---

_Sunti hai, samajhti hai, bolti hai. 💜_
