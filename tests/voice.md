# Voice manual checklist (Phase 2)

Open http://127.0.0.1:8080 in **Chrome on the phone**. First time it asks for
Microphone permission — allow it.

1. **Mic in** — Tap the Mic button. It turns "listening". Say "ek python function likho".
   Live transcript appears above the chat as you speak. On pause it auto-sends.
2. **Hindi toggle** — Tap the `hi-IN` / `en-US` button. It flips language. Speak in the
   chosen language; transcript language follows the toggle.
3. **Voice out** — After ULLAH replies, the answer is spoken aloud. Press Stop mid-speech
   and it goes silent immediately.
4. **Conversation loop** — Tick "Baat-cheet loop". ULLAH speaks, then the mic re-opens by
   itself (~0.4s later) and you can just talk back with no button taps. Untick to stop.
5. **Permission denial** — Chrome > site settings > block Microphone, reload, tap Mic.
   A clear status message appears telling you to allow the mic. Re-allow and it works.

Notes:
- Speech needs internet (Chrome sends audio to its speech service).
- TTS voice auto-picks Hindi for hi-IN, English for en-US when such a voice is installed.
- Code blocks are skipped when speaking (replaced with "code block") so symbols aren't read.
