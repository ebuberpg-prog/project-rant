# Rant

**Rant** — Voice to Structured Spec. Record your unstructured thoughts, let AI turn them into executable PRDs.

## Native macOS app

The native Mac app adds global voice dictation and transcript cleanup alongside the original PRD, fix, and structured-note workflows. Press **⌘⌥Space** in any app to record and insert the cleaned text. Speech recognition and read-aloud use macOS; GPT cleanup uses the ChatGPT-plan connection for eligible accounts.

Build and launch it from `macOS/RantMac`:

```bash
cd macOS/RantMac
./build-app.sh
open dist/Rant.app
```

See [the Mac app guide](macOS/RantMac/README.md) for permissions and setup. The existing browser app remains available below.

## What It Does

1. **Record** — Hit the mic button and rant about your app idea, bug, or feature
2. **Process** — Audio is sent directly to GPT Audio (via Wavespeed.ai) — no STT step, the LLM hears your tone and emphasis
3. **Clarify** — If the AI needs more info, it asks questions. You answer by voice or text
4. **Export** — Get a structured PRD with user stories, acceptance criteria, architecture, and implementation phases — ready to paste into Cursor, Claude, or v0

## Setup

### 1. Get a [Wavespeed.ai](https://wavespeed.ai) API key

### 2. Start the proxy server

**You must use the included proxy server** (`server.js`). Browsers block cross-origin API calls to Wavespeed.ai from `file://` URLs and even `localhost`. The proxy solves this by forwarding your requests from the same origin.

**Requirements:** Node.js (install from [nodejs.org](https://nodejs.org) if you don't have it)

```bash
cd /path/to/project-rant
node server.js
```

Then open: **http://localhost:8080**

The proxy server does two things:
1. Serves the static HTML/CSS/JS files
2. Forwards `/proxy/chat/completions` → `https://llm.wavespeed.ai/v1/chat/completions`

### 3. Use the app
1. Paste your Wavespeed.ai API key in the header
2. Select a model (GPT Audio models send audio directly; others transcribe first)
3. Hit the mic button and start ranting

## Architecture

Client-side HTML/CSS/JS app with a minimal Node.js proxy server to bypass CORS when calling Wavespeed.ai's API from localhost.

### Files

| File | Purpose |
|------|---------|
| `index.html` | App shell with all views |
| `styles.css` | Dark theme, recording animations, chat UI |
| `recorder.js` | `VoiceRecorder` class — getUserMedia + MediaRecorder |
| `api.js` | `WavespeedAI` client — routes through `/proxy` on localhost |
| `prompts.js` | LLM system prompts for spec generation & clarification |
| `app.js` | Main app — view switching, conversation flow, export, history |
| `export.js` | Clipboard copy, markdown download, companion file generation |
| `server.js` | Node.js proxy server — serves files + forwards API calls |

## How It Works

### Audio Flow
```
Microphone → MediaRecorder → Blob → Base64 → input_audio → Wavespeed.ai
```

### Spec Generation Flow
```
Voice Rant → GPT Audio (listens) → Structured PRD (13 sections)
  ↓ missing info?
Clarification Questions ←→ Voice/Text Answers
  ↓ complete
Final Spec → Copy / Download .md
```

## Prompt Engineering

The app uses carefully crafted system prompts:

- **Initial Generation** — Converts voice rant into a 13-section PRD (Overview, Goals, Non-Goals, User Stories with Given/When/Then ACs, Technical Spec, UI/UX, Constraints, Phases, Testing, Edge Cases, Open Questions)
- **Clarification** — When the LLM detects missing info, it asks targeted questions (one at a time)
- **Final Generation** — Incorporates all clarifications into a complete, executable spec

## Pricing

Uses Wavespeed.ai's GPT Audio models:
- **GPT Audio Mini**: $0.60/M input tokens, $2.40/M output tokens (recommended for cost)
- **GPT Audio**: $2.50/M input tokens, $10/M output tokens (recommended for quality)

A 2-minute rant typically costs $0.02–$0.08.

## Browser Support

- Chrome 49+, Edge 79+, Firefox 29+, Opera 36+
- Safari 14.1+ (macOS), Safari 14.5+ (iOS)
- Safari 18.4+ supports cross-browser `audio/webm;codecs=opus`

## License

MIT
