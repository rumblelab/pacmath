# PacMath dev notes

Things that aren't obvious from reading the code.

## Screenshot mode

`app/PacMath/Views/ChompPetView.swift` has a file-level `pacMathScreenshotMode` constant near the top. When `true`:

- All three Chomp views freeze with mouth open
- Speech bubbles stay pinned instead of auto-dismissing
- Start screen Chompy picks a new line from a curated pool on every bounce
- In-game Chompy rotates through a curated pool every 4 seconds

**Must be `false` on any build you ship to TestFlight or the App Store.** A frozen-mouth Chompy with a permanent speech bubble will slip through review but look broken to users.

## Hidden reset-scores gesture

Long-press the `pacmath.lol` footer on the Start screen for 1.5 seconds. Confirm alert, then all high scores wipe. Daily streak and total time played are kept. Implementation: `GameEngine.resetHighScores()`, gesture wired in `StartView.swift`.

## App icon regeneration

- Current icon: `app/PacMath/Assets.xcassets/AppIcon.appiconset/pacmath-icon.png` (1024×1024, sRGB, no alpha)
- Renderer: `app/PacMath/LegacyAssets/render_icons.swift` — parameterized, can emit variants
- Legacy backups (v1 space scene etc.) live alongside the renderer in `LegacyAssets/`
- To iterate: edit params in `render_icons.swift`, run `swift render_icons.swift <output-dir>`, copy the chosen PNG over `pacmath-icon.png`

## Privacy policy accuracy

`docs/privacy/index.html` (served at pacmath.lol/privacy via GitHub Pages) claims:
- No audio ever leaves the device
- No servers
- On-device speech recognition

This is only true as long as `app/PacMath/SpeechRecognizer.swift` keeps `request.requiresOnDeviceRecognition = true` (around line 257). If you loosen that to fall back to Apple's servers, the privacy page is lying — update both in the same commit or don't change either.

## App Store screenshots

- Target size: 1320×2868 (6.9" iPhone) preferred, 1284×2778 (6.5") accepted
- Source screenshots from a real device are easiest — the iPhone 13 Pro Max produces 1284×2778 natively
- Caption compositor: `marketing/caption.swift` (move from `/tmp/caption.swift` if not yet in the repo)
- Usage: `swift marketing/caption.swift <input.png> <output.png> "<headline>" ["<subtitle>"]`
- Output goes in `marketing/screenshots/captioned/`, raw sources in `marketing/screenshots/raw/`

## Future ideas

- **Miss pile.** This is already how the user teaches his daughter with physical flashcards: when she gets one wrong, it goes into a pile they retest. That's the whole mechanic, and it writes its own UI — a visible stack on the Start screen that shrinks as she masters problems and grows when she misses new ones. The metaphor is the product; the kid already understands the rule. Implementation: `[problemKey: missCount]` in UserDefaults with canonical keys like `"7x8"`, graduate out after two correct answers in a row. Open questions: how much does the pile bias normal gameplay vs. live as its own "review" mode, and how literal is the visual metaphor (a real stack of cards, or just a number on the Start screen). Grounded pedagogy, not a speculative feature — ship v1, watch real sessions, then build.
- **Show all missed problems on results screen.** Currently only the *last* missed problem is surfaced. If a kid got 3/10 wrong in classic, they only see the 10th one. Stack-list below the current card (only when `wrong > 1`) is simpler than a swipe UI.
