# Rant PWA

The GitHub Pages build publishes an installable, static PWA. It uses the native Rant for macOS app as its local companion for microphone capture, on-device speech recognition, ChatGPT plan access, and read-aloud support.

## Publish on GitHub Pages

The `Deploy Rant PWA to GitHub Pages` workflow assembles only the PWA files and publishes them at the repository Pages URL. In the repository settings, choose **Settings → Pages → Build and deployment → Source → GitHub Actions**. After the workflow runs on `main`, open:

`https://ebuberpg-prog.github.io/project-rant/`

Install from Chrome’s install control or its **Install page as app** menu. The PWA shell is cached for offline loading. Recording and GPT features still require Rant for macOS running on that same Mac.

## Use it

1. Build and open Rant for macOS, then connect ChatGPT in the app’s Settings.
2. Open the Pages URL in Chrome on that Mac. Allow the browser to connect to the local Rant companion if prompted.
3. Pick a writing mode and start/stop recording in the PWA. Rant captures audio and transcribes it on the Mac; it sends transcript text to OpenAI for cleanup when ChatGPT plan access is enabled.

The PWA’s **Read aloud** action uses the browser’s speech synthesis. The native app has its own macOS read-aloud control.

## Limits and privacy

- Sign in with ChatGPT stays in Rant for macOS. OAuth tokens remain in macOS Keychain; the hosted PWA never receives them.
- The loopback companion listens only on `127.0.0.1:41739` and accepts browser requests from this project’s GitHub Pages origin and `http://localhost:8080` or `http://127.0.0.1:8080` during local development.
- Browsers must allow the HTTPS page to connect to its loopback companion. Chrome may ask for Local Network Access permission; allow it for Rant. Safari currently blocks hosted pages from making this connection. On Safari, use the native Mac app directly or open the PWA in Chrome.
- This PWA is for a Mac running the native companion. Installing it on an iPhone or another computer will not connect to the Mac app.
- GitHub Pages serves static files only. The PWA does not put ChatGPT credentials or a server-side proxy on GitHub Pages.

The older browser prototype at the repository root (`app.js`, `api.js`, and `server.js`) is not included in the Pages deployment artifact. The Pages workflow serves the PWA screen as the site entry point.
