# Rant for macOS

Rant is a native macOS voice workspace for dictation and spoken product notes. Its global shortcut starts and finishes dictation while you work in another app. Rant tries **⌘⌥Space** first; if macOS reports a conflict, it tries **⌃⌥Space**. The active shortcut is shown in the Dictate view and Settings.

Speech recognition and read-aloud use macOS. Connect an eligible ChatGPT account to clean up dictation, draft PRDs, create bug-fix briefs, or structure notes. Rant sends transcript text for GPT cleanup; it does not send recorded audio to ChatGPT. Dictations are copied to the clipboard automatically, and Rant can type them into the app you were using when Accessibility access is enabled.

## Build

Requires macOS 14 or later and Xcode command-line tools.

```sh
./build-app.sh
open dist/Rant.app
```

The first recording asks for Microphone and Speech Recognition access. macOS may require you to enable them in **System Settings → Privacy & Security**. Enable Accessibility in **Rant → Settings → Allow Accessibility** to let Rant type into other apps. If Rant cannot safely activate the target app or Accessibility is unavailable, the finished text remains on the clipboard.

The build script creates an ad hoc signed app for local use. It does not create a Developer ID signed or notarized release.

## Shortcut troubleshooting

- Check the active key combination in the Dictate view or Settings. The displayed combination is the one Rant registered.
- If both shortcuts are unavailable, quit another app that owns a shortcut or change that app’s shortcut, then relaunch Rant.
- If the global shortcut is unavailable, open Rant and use **Start speaking** as a fallback.
- If the shortcut records but does not type into another app, grant Rant Accessibility access. You can still paste the clipboard result manually.
- The current macOS language must support on-device Speech Recognition. Rant reports an error if that language is unavailable.

## ChatGPT plan usage

Choose **Continue with ChatGPT** in Settings and approve plan use for Rant in the browser. Access depends on account eligibility and availability of the open-source app integration. The model picker lists models available to the signed-in account. GPT cleanup streams transcript text through the Responses API with `store: false`; audio remains on this Mac.

## GitHub Pages PWA companion

When Rant is open, it provides a loopback-only companion for the GitHub Pages PWA on port `41739`. The PWA can start/stop Mac-side recording and read the completed result. The listener binds to `127.0.0.1` and only allows the project Pages origin plus `localhost:8080` development origins. It does not expose the ChatGPT token to the browser. Safari currently blocks this hosted-page-to-loopback connection; use Chrome for the PWA or use Rant’s native window directly.

## Privacy and storage

- Microphone audio is processed by macOS speech recognition and is not saved by Rant.
- Recent cleaned transcripts are stored locally in this Mac user account’s preferences. Clear history in the History view.
- ChatGPT OAuth credentials are stored in the macOS Keychain. Signing out attempts to revoke the renewable session and clears the local credentials.
- Rant sends transcript text to OpenAI only after you authorize ChatGPT plan use. Requests set `store: false`.
