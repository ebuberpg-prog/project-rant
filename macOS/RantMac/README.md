# Rant for macOS

Rant is a native macOS voice workspace. Press **⌘⌥Space** in any app to start or finish a dictation. Speech recognition runs locally through macOS. When connected, GPT cleans the transcript using the ChatGPT plan authorization for this open-source app. The result is copied automatically and typed into the previously active app when macOS Accessibility permission is enabled.

The app also keeps the original Rant workflows: PRD drafting, bug-fix briefs, and structured notes. Read-aloud uses the macOS system voice. Audio is not uploaded to ChatGPT.

## Build

Requires macOS 14 or later and Xcode command-line tools.

```sh
./build-app.sh
open dist/Rant.app
```

The first recording asks for Microphone and Speech Recognition permissions. Enable Accessibility in **Rant → Settings → Allow Accessibility** to let the global shortcut insert text into the app you were using. Without Accessibility, the result still goes to the clipboard.

## ChatGPT plan usage

Choose **Continue with ChatGPT** in Settings and approve plan use for Rant in the browser. Eligible ChatGPT Plus and Pro accounts can use the open-source app integration. The model picker reflects the models available to that signed-in account. GPT cleanup sends transcript text to the Responses API with `store: false`; audio stays on-device.

## Privacy and storage

- Microphone audio is processed by macOS speech recognition and is not saved by Rant.
- Recent transcripts are stored in this Mac user account’s preferences.
- ChatGPT OAuth credentials are stored in the macOS Keychain.
- GPT cleanup sends text only after ChatGPT plan use is authorized.
