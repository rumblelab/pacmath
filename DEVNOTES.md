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
- Current renderer (v2, post-rejection): `app/PacMath/LegacyAssets/render_icon_v2.swift` — honey-gold Chompy peeking over a `6+7` flashcard
- Legacy v1 renderer: `app/PacMath/LegacyAssets/render_icons.swift` — produced a yellow Pac-Man-silhouette icon that was rejected under guideline 4.1(a). Kept for reference, not for regeneration.
- To iterate: edit params in `render_icon_v2.swift`, run `swift render_icon_v2.swift <output-dir>`, copy the output over `pacmath-icon.png`
- **Do not revert to anything resembling the v1 icon** (full yellow circle + wedge mouth silhouette on dark background). That composition was specifically flagged as a Pac-Man copycat. The v2 design breaks the trademark read by (a) using honey-gold instead of #FFD700, (b) adding eyes, (c) showing only the top of the head, (d) putting the character behind a flashcard so the Education context reads first.

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

- **iPad support (v1.1 launch target).** Shipped iPhone-only for v1 because the audience (kids) is more likely to have an iPad than a phone, but retrofitting iPad properly was not a day-one blocker. Everything in the repo is SwiftUI with adaptive layout, so the work is a layout pass, not a rewrite: add `maxWidth` containers to the main views (`ResultsView` already does this at 500), decide whether Chompy's traversal path should clamp to a bounded width or scale across the full iPad canvas, verify the customize keyboard and color picker don't look absurd at tablet size, and re-enable iPad in `TARGETED_DEVICE_FAMILY`. The marketable angle: v1.1 "Now on iPad" is a free second launch announcement 2–3 weeks after v1. Realistic scope: a weekend. Needs a real iPad to test.
- **Miss pile.** This is already how the user teaches his daughter with physical flashcards: when she gets one wrong, it goes into a pile they retest. That's the whole mechanic, and it writes its own UI — a visible stack on the Start screen that shrinks as she masters problems and grows when she misses new ones. The metaphor is the product; the kid already understands the rule. Implementation: `[problemKey: missCount]` in UserDefaults with canonical keys like `"7x8"`, graduate out after two correct answers in a row. Open questions: how much does the pile bias normal gameplay vs. live as its own "review" mode, and how literal is the visual metaphor (a real stack of cards, or just a number on the Start screen). Grounded pedagogy, not a speculative feature — ship v1, watch real sessions, then build.
- **Show all missed problems on results screen.** Currently only the *last* missed problem is surfaced. If a kid got 3/10 wrong in classic, they only see the 10th one. Stack-list below the current card (only when `wrong > 1`) is simpler than a swipe UI.

- **Chain mode (fact-family training).** This is how the user actually drills with his daughter: 6+7=13, then 13−6=7, then 13−7=6 — same triangle, three views. A kid who sees the composition does the inverse in ~200ms; a kid who doesn't has to recompute from scratch, which is the diagnostic. Every slow inverse identifies a fact being memorized instead of understood. No competitor in the category does this. Implementation: generate a seed problem, then derive each subsequent problem from the previous answer using an operation that exposes the fact family (inverse op, decomposition, +/−10). Show the previous answer faded above the new problem so the structural link is visible without being narrated. **Trick discovery is hybrid, never explicit:** show nothing on the first chains. If the kid solves the inverse in <1.5s, they've discovered the link — say nothing, never name the rule. If they take >5s on the inverse (= they're recomputing from scratch and missed the link), surface the structural visual: previous answer fades into position as the new input, relationship highlighted. No words. The kid sees it, names it in their own words, owns the insight. Mirrors how the user teaches — structure speaks, no explanation. Bonus: the visible-link UI doubles as a teaching tool for the parent watching ("see how that's the same number?"). Likely ships before miss pile: chain mode prevents misses upstream, miss pile reviews them downstream.

- **Hidden parent peek dashboard.** Same long-press gesture pattern as the reset-scores affordance (`pacmath.lol` footer, 1.5s), but opens a parent-only summary: weekly accuracy, current adaptive level in endless, most frequent misses, daily streak. All from data that already exists in UserDefaults — view layer only, no new state, no schema changes. **Strictly local. No server, no email push, no off-device transfer.** A "weekly recap by email" feature looks high-value but breaks the privacy story and walks the app into COPPA territory (a 4+ kids app sending kid data to a third-party server requires verifiable parental consent — not just a privacy policy update). If parents want to share progress, give them a "share this week" button that generates a card the parent sends themselves via Messages/Mail — no server involved. The dashboard's real job is to give the parent a reason to open the app on their own phone, which is also the moment the in-app email-signup link can land — warming the list for the future adult app.

- **Screen-time gatekeeper (probably a separate product, not a PacMath feature).** Kid earns unlock time on locked apps (YouTube, TikTok, Roblox) by completing math rounds. Same category as Opal, Brick, and the pushup-unlock apps — and the economics are real: parents pay $5–10/mo to solve a recurring daily household fight, which looks closer to CPSAT-scale than a $40/yr daily cognitive-fitness app ever will. iOS supports this natively via `FamilyControls` / `ManagedSettings` / `DeviceActivity`, but those frameworks require a special entitlement applied for from Apple — weeks of integration + entitlement review, not a weekend. **Architectural decision to resolve before building: separate app, not a PacMath feature.** Bolting the gate onto PacMath would shift the kid's relationship with it from *want to play* → *have to play*, which kills the voluntary-use story the whole app rests on. Cleaner: a second product (working title "MathGate") that's a gatekeeper shell using PacMath's engine internally — PacMath stays loved and voluntary, MathGate is the monetized parent-tool with its own name and pricing. Chain mode + miss pile become more valuable here (longer skill sustained = more earned minutes). Privacy posture stays intact — FamilyControls gates locally, no servers involved. Big enough to potentially leapfrog the deferred adult mental-math app in the business sequencing — revisit STRATEGY.md if this gets prioritized.
