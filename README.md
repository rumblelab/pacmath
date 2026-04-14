# PacMath

**Mental math, out loud.** A voice-first math game for kids, built in SwiftUI.

Tap the mic, see a problem, say the answer. Chompy eats the dots and waits for the next one. No typing, no tapping, no worksheets — just math you say with your voice.

- Website: [pacmath.lol](https://pacmath.lol)
- App Store: _coming soon_
- Privacy: [pacmath.lol/privacy](https://pacmath.lol/privacy)

## Why

Worksheets and calculators both bypass the part of practice that matters: producing the answer from your head, on the spot, with no buttons in between. PacMath rewards saying it out loud.

## Features

- On-device speech recognition (nothing leaves the phone)
- Classic mode — 10 problems at your chosen level
- Endless mode — problems that adapt as you improve
- Four difficulty tiers: easy, medium, hard, beast
- Daily streaks, high scores, full run recaps
- Customize Chompy with a name and color
- Works fully offline; no accounts, no ads, no data collection

## Build it yourself

Requires Xcode 15+ and iOS 17+ deployment target.

```bash
git clone https://github.com/rumblelab/pacmath.git
cd pacmath
open app/PacMath.xcodeproj
```

Select the `PacMath` scheme, pick any iOS device or simulator, and hit ⌘R.

**On device:** speech recognition works best on a real iPhone. The simulator supports speech but is less reliable — use the `skip` button if it misfires.

## Repo layout

```
app/             Xcode project and SwiftUI source
docs/            Static site served at pacmath.lol via GitHub Pages
marketing/       App Store screenshots, caption compositor, listing copy
DEVNOTES.md      Non-obvious dev affordances (screenshot mode, reset gesture, etc.)
```

See [`DEVNOTES.md`](./DEVNOTES.md) for things that aren't obvious from reading the code.

## Contributing

PRs welcome. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first.

Ideas I'd love help with:

- A "miss pile" mode that retests problems the player got wrong, modeled on physical flashcards
- Showing all missed problems on the results screen, not just the last one
- Additional difficulty tiers or new operations (fractions, decimals)

## Privacy

PacMath does not collect any data. Speech recognition runs entirely on-device via Apple's `Speech` framework with `requiresOnDeviceRecognition = true`. No servers, no analytics, no ads.

This is enforced in code at [`app/PacMath/SpeechRecognizer.swift`](./app/PacMath/SpeechRecognizer.swift) and in the [`PrivacyInfo.xcprivacy`](./app/PacMath/PrivacyInfo.xcprivacy) manifest.

## License

[MIT](./LICENSE) © rumblelab. Fork it, remix it, ship your own math game.

_You cannot, however, use the "PacMath" name or the Chompy character to publish your own App Store listing under these terms — trademarks and trade dress are not covered by MIT. Make your own brand._
