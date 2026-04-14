# Contributing to PacMath

Thanks for your interest. PacMath is a weekend-project math game that a parent built for their kid, and the code is MIT-licensed precisely so someone else can make it better.

## Ground rules

- **This is an app for kids.** Nothing in a PR should introduce tracking, ads, third-party analytics, or anything that sends data off-device. Check [`DEVNOTES.md`](./DEVNOTES.md) § "Privacy policy accuracy" before touching `SpeechRecognizer.swift`.
- **Keep it offline.** PacMath is deliberately 100% on-device. No backend, no network calls, no accounts.
- **One thing per PR.** Smaller PRs get reviewed and merged faster.

## Getting set up

1. Install Xcode 15 or newer
2. Clone the repo
3. Open `app/PacMath.xcodeproj`
4. Pick the `PacMath` scheme and hit ⌘R

You'll need to switch the development team in project settings to your own Apple ID to run on a physical device. The bundled team ID (`VR82S46UR7`) is mine.

## Before you open a PR

- Read [`DEVNOTES.md`](./DEVNOTES.md) — there are some non-obvious things (screenshot mode flag, hidden reset gesture, privacy coupling) you'll want to know about
- Test on a real device if your change touches speech recognition, audio, or anything the simulator handles differently
- Run the app through both classic and endless modes at least once
- Don't commit changes to `project.pbxproj` unless your change genuinely requires it (renaming files, adding resources); avoid accidental churn

## What I'd love help with

See the "Ideas I'd love help with" section in [`README.md`](./README.md). Top of the list:

- **Miss pile mode** — retest problems the player got wrong, modeled on how a parent teaches with physical flashcards. Sketch in [`DEVNOTES.md`](./DEVNOTES.md) § "Future ideas"
- **All missed problems on results screen** — currently only the last missed problem shows
- **New operations** — fractions, decimals, percentages, measurement conversions

## What I'm unlikely to merge

- Changes that add a backend, login, or any data collection
- Analytics or telemetry libraries
- Ad SDKs
- Heavy third-party dependencies for small wins
- UI overhauls without screenshots showing the before/after

## Filing an issue

If you don't have time to write code but have a bug or an idea, issues are welcome. For bugs, include:

- iOS version and device (or simulator version)
- What you did, what you expected, what actually happened
- A screenshot if UI is involved

## License

By contributing, you agree that your contributions will be licensed under the same [MIT license](./LICENSE) as the rest of the project.
