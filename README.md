# Rant

Rant turns spoken thoughts into clear dictation, product requirements, bug-fix briefs, and structured notes. The current experience is a native macOS app with an installable GitHub Pages PWA companion.

## macOS app

The native app captures and transcribes speech on your Mac, can read results aloud, and can use an eligible ChatGPT account for GPT cleanup. OAuth credentials stay in macOS Keychain; the app sends transcript text to OpenAI when you authorize plan use.

Requires macOS 14 or later and Xcode command-line tools. Build and open it with:

```bash
cd macOS/RantMac
./build-app.sh
open dist/Rant.app
```

Rant tries **⌘⌥Space** first and uses **⌃⌥Space** if that shortcut is already taken. Grant Microphone and Speech Recognition access to dictate. Accessibility access enables automatic insertion into other apps; if insertion is unavailable, Rant copies the result to the clipboard.

See [the Mac app guide](macOS/RantMac/README.md) for setup, shortcut troubleshooting, ChatGPT account connection, and privacy details.

## GitHub Pages PWA

The PWA offers an installable interface that controls the local Mac app. It requires Rant for macOS to be open on the same Mac. The PWA does not receive ChatGPT OAuth tokens or send recorded audio to ChatGPT.

See [PWA setup and limitations](PWA.md). GitHub Pages deploys the PWA through the included Actions workflow after Pages is configured to use **GitHub Actions** as its source.

## Repository contents

- `macOS/RantMac/` — native SwiftUI macOS app and local companion service.
- `pwa.html`, `pwa.js`, `pwa.css` — installable PWA interface.
- `manifest.webmanifest`, `service-worker.js`, `icons/` — install metadata, offline shell, and app icon.
- `.github/workflows/deploy-pages.yml` — publishes only the PWA to GitHub Pages.
- `app.js`, `api.js`, `index.html`, `server.js`, and related web files — older browser prototype, not included in the Pages deployment.

## License

MIT. See [LICENSE](LICENSE).
