# Re-blocked: the implementation plan

How to build [Spec.md](Spec.md), in order. Each phase leaves Backdrop building, tested and usable, so work can stop between any two phases.

## Ground rules

- **Not live, so no compatibility.** No feature flags, no migration code, no old and new side by side. What a step replaces, it deletes in the same step. Model, timing and file-format changes are allowed; any change to a recorded output in `Fixtures/` is made on purpose and called out in that step.
- **Every step ends green:**
  - The Backdrop scheme builds under Swift 6 strict concurrency with no warnings.
  - `cd BackdropCore && swift test` passes.
  - `-BackdropSnapshot /tmp/console` renders every console state without a crash.
- **The safety rules are invariants.** Every step must keep the rules listed at the end of this plan, and the checks there run at the end of each phase.
- **Files:** new Swift files go in the folder named in each step. `Backdrop/` is a synchronized folder in the Xcode project, so a new file there is in the app target with no project edit. New files in `BackdropCore/Sources/*` are picked up by the package.
- **Words:** reuse today's strings. New strings are the ones in Spec.md, exactly as written there.
- **Style:** the repo's own, as described in its README. One type per file where it makes sense. Comments say what and why in plain sentences, British spelling. Every change to the sheet goes through `ShowController.edit`.

## Phases

| Phase | What | Size | Needs |
| --- | --- | --- | --- |
| 0 | Foundations: palettes, layout split, shared pieces | M | none |
| 1 | Go To on G, and the key changes | S | 0 |
| 2 | The Booth | L | 0, 1 |
| 3 | The rail | L | 0 |
| 4 | The cue gallery | M | 0 |
| 5 | The Studio | XL | 0, 3 |
| 6 | Finish: README, dead code, full check | S | all |

Phases 3 and 4 can run alongside 2. Phase 5 is split so each of its steps can land separately.

---

## Phase 0: Foundations

### 0.1 Booth palette and window appearance

**Files:** `Backdrop/Console/Desk.swift` (change); `Backdrop/Console/Booth.swift` (new).

- Add `enum Booth` with the tokens in Spec.md section 9, as `NSColor`s and matching SwiftUI `Color`s. Each token resolves to its high-contrast value while `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` is true.
- Have `ConsoleRootView` repaint on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, as `PanelView` already does for system colours.
- Add `Desk.room(_ mode: ShowController.Mode)`. It returns the palette the rail and panels draw with: `Booth` in show mode, and today's `Desk` colours in edit mode.
- In `ConsoleWindowController.refresh()`, set `window.appearance`:
  - in show mode, to `NSAppearance(named: .darkAqua)`, or `.accessibilityHighContrastDarkAqua` with Increase Contrast;
  - in edit mode, to `nil`, so it follows the Mac.

  This makes SwiftUI controls, menus, popovers and sheets in the Booth dark without restyling each one.

**Done when:** the console snapshots in show mode are dark on a light-mode Mac, and edit mode still follows the Mac.

### 0.2 One layout per room

**Files:** `Backdrop/Console/ConsoleWindow.swift` (change); `BackdropCore/Sources/BackdropStage/Stage/ConsoleGeometry.swift` (new); `BackdropCore/Tests/BackdropStageTests/ConsoleGeometryTests.swift` (new).

- Move the frame arithmetic out of `layoutContent()` and `placePreview(...)` into pure functions:
  - `ConsoleGeometry.booth(in:railWidth:outputAspect:stopBands:)` returns a `BoothFrames` struct of `CGRect`s;
  - `ConsoleGeometry.studio(in:railWidth:inspectorWidth:outputAspect:)` returns a `StudioFrames` struct.

  They need only CoreGraphics, so they can live beside `ProjectorPlacement` in BackdropStage and be unit-tested.
- `layoutContent()` then hides what the room doesn't use and assigns frames. The rail keeps its saved width (`ConsoleListWidth`, 260 to 520) in both rooms, and the Inspector its own (`ConsoleInspectorWidth`).
- **Booth rules,** at window sizes from 900 × 600 upward:
  - **Header:** 56.
  - **Main column:** the main column is everything right of the rail, inset 24.
  - **Bottom of the column:** the key row is 24 high at the bottom, with the GO plate (94) 12 above it.
  - **Card:** at least 220 high.
  - **Monitors:** take what is left. Each is `(columnWidth − 132) / 2` wide at most, at the output aspect, and at least 200 wide. Below that, the card shrinks to its minimum before the monitors shrink further.
  - **Card number:** its font size scales from 104 down to 72 with the card's height.
- **Studio rules:** the toolbar is 56. The Inspector is a full-height column on the right. Within the middle column, from the top:
  - the canvas header (24);
  - the canvas, at the output aspect, as large as fits;
  - 16 of space;
  - the timeline, at its own height, which is 64 plus 38 per track;
  - the join line (20).

  If the window is too short, the canvas shrinks first, down to 240 wide.
- **Tests:** frames never overlap; everything stays inside the window at 900 × 600, 1280 × 800 and 2560 × 1440; and the monitors keep the output aspect.

**Done when:** today's console looks the same as before, laid out through `ConsoleGeometry`. This is a pure refactor; the visual changes come in Phases 2 and 5.

### 0.3 Changing room

**Files:** `Backdrop/Console/ConsoleWindow.swift`.

When `controller.mode` differs from the mode at the last refresh, add a `CATransition` of type `.fade` and duration 0.3 to `root.layer` before relaying out. Skip it when `accessibilityDisplayShouldReduceMotion` is true.

### 0.4 Shared pieces

**Files:**
- `Backdrop/Console/Keycap.swift` (new)
- `Backdrop/Console/CueText.swift` (new)
- `Backdrop/App/Fonts.swift` (new)
- `Backdrop/Fonts/CourierPrime-Regular.ttf`, `CourierPrime-Italic.ttf`, `OFL.txt` (new)

**`Keycap`.** A SwiftUI view, and a matching `Keycap.draw(_:in:)` for AppKit drawing: a rounded 5 pt outline in the current ink with monospaced 11.5 pt text. It replaces the ad hoc keycaps in `KeyBar.swift`.

**`CueText`.** Holds what the console says about a cue, moved from the views so every room says the same thing:
- `CueText.summary(_ cue: Cue)`: today's `CueRowView.content`.
- `CueText.transitionNote(_ cue: Cue)`: today's `TransitionRowView.note(for:)`.
- `CueText.line(_ cue: Cue)`: the name with ⏎ for line breaks, as both rows and panel do today.
- `CueText.goTip(...)`: the header's GO tooltip logic from `refresh()`.

**Fonts.** Courier Prime is OFL-licensed; add it with its licence. In `Fonts.register()`, called first in `applicationDidFinishLaunching`, register both faces with `CTFontManagerRegisterFontURLs(_:.process:...)`, looked up by name from `Bundle.main`. Add `Desk.script(_ size:italic:)`, which falls back to `Courier New` if registration ever fails.

**Done when:** nothing changes on screen yet, the font loads, and `Fonts` notes in a comment that the licence must ship with the app.

### 0.5 Snapshot harness

**Files:** `Backdrop/Debug/Snapshots.swift`.

- Add `saveVariants(_:_:to:)`. It saves a state three times: Mac appearance light, dark, and high-contrast dark, as `name.png`, `name-dark.png` and `name-hc.png`. Use it for every Booth and Studio state from Phase 2 on.
- Keep `console.booth = { BoothConditions() }` as the default, so snapshots don't depend on the Mac that takes them.

---

## Phase 1: Go To on G

### 1.1 Remove typed entry from the model

**Files:** `BackdropCore/Sources/BackdropCore/Running/Playhead.swift`, `BackdropCore/Sources/BackdropStage/Stage/ShowController.swift`, `BackdropCore/Tests/BackdropCoreTests/PlayheadTests.swift`, `BackdropCore/Tests/BackdropStageTests/ShowControllerTests.swift`.

- **`Playhead`:** delete `entry`, `entryLimit`, `type(_:)`, `deleteBackward()`, `clearEntry()`, `commitEntry(in:)` and its result type, and every `entry = ""` line (in `go`, `standBy…`, `standByNext/Previous`, `resume` and so on).
- **`ShowController`:** delete `type`, `deleteBackward`, `clearEntry` and `commitEntry`. Make `standBy(number:)` `@discardableResult` and return whether a cue stood by. It still says "No cue is numbered P12." when none does.
- **Tests:**
  - In `PlayheadTests`, delete the three entry tests: `typedDigitsBuildANumberAndFireNothing`, `entryCanBeEditedAndCleared` and `goDiscardsAnEntryAndFiresWhatIsShown`. Extend `listClicksAndTheGoToFieldStandBy`, renamed `listClicksAndGoToStandBy`, to cover `standBy(number:)` with digits, a decimal, a letter-and-digit number (`P12`), surrounding spaces, a missing number, and a number used twice. Whatever `Playhead.standBy(number:in:)` does today with a duplicated number, assert it.
  - In `ShowControllerTests`, rewrite the uses at lines 49 to 50 and 163 to use `standBy(number:)`.

### 1.2 The new key map

**Files:** `Backdrop/App/ShowKeys.swift`, `Backdrop/Projector/SurfaceView.swift`, `Backdrop/Console/ConsoleWindow.swift`, `Backdrop/Projector/Projector.swift`.

- `ShowKeys.handle(_ event:controller:console:)` takes a `ConsoleKeys` protocol with `showGoTo()` and `toggleKeyHelp()`, implemented by `ConsoleWindowController`.
- The map:
  - Space: `go()`.
  - → ↓ Page Down, and ← ↑ Page Up: as today.
  - `g`: `console.showGoTo()`.
  - `r`: rerun.
  - `b`: blackout.
  - `?`, typed with Shift, which `handle` already allows: `console.toggleKeyHelp()`.
  - Escape: closes the key help if it is open, and is otherwise swallowed.
  - Everything else without ⌘, ⌃ or ⌥: swallowed, as today.
  - Repeats: swallowed, as today.
- **The projector window:** `SurfaceView` gets a `weak var console: ConsoleWindowController?`, which `ProjectorManager` sets from its `console` window's controller. G pressed there calls `console.window?.makeKeyAndOrderFront(nil)` and then `showGoTo()`.

### 1.3 The Go To panel

**Files:** `Backdrop/Console/GoTo/GoToPanel.swift` (new, the AppKit host); `Backdrop/Console/GoTo/FlapField.swift` (new, the view that takes the keys); `Backdrop/Console/GoTo/GoToView.swift` (new, SwiftUI chrome).

- **The panel:** a child `NSPanel`, borderless, non-activating, attached to the console window and positioned from `BoothFrames.card` or the Studio canvas header. Its content is `GoToView`, which shows the heading, the `FlapField` and the hints.
- **`FlapField`** is an `NSView` that becomes first responder while the panel is open, and implements `keyDown` exactly as Spec.md 2.7 says:
  - Space with no repeat: close, then `controller.go()`.
  - Return or Enter: `standBy(number:)`. Close if it returns true; otherwise show the message line.
  - Escape: close.
  - Delete and forward delete: remove the last character.
  - Arrows: swallow.
  - Command keys: pass to `super`.
  - Printable characters except a space, up to 12: append.
- **Drawing the flaps:** each character is drawn on a 40 × 52 flap, with a two-tone fill split by a 1 pt line, in the brass ink in monospaced 32 pt. A blinking cursor flap follows. Under Reduce Motion the cursor doesn't blink.
- **Closing:** on `resignKey` of the panel or the console, and on any mouse-down outside the panel, using a local event monitor added while it is open and removed on close. Closing returns first responder to `root`.
- **Accessibility:** the panel's role is `.textField`, labelled "Go to cue". Its value is the typed text, and the error is announced with `NSAccessibility.post(..., .announcementRequested)`.
- **The mouse:** clicking the standby card's number calls `showGoTo()`. Wired in 2.5.
- **Tests:** none at the app level. The behaviour lives in `FlapField.keyDown` and is checked by snapshots: `booth-goto` with "P12" typed, and `booth-goto-missing` after Return. 1.1's model tests cover the matching.

### 1.4 Remove the old entry from the console

**Files:** `Backdrop/Console/ConsoleWindow.swift`, `Backdrop/Console/Panels/StandbyPanel.swift`.

- Delete `gotoLabel`, `gotoField` and the `NSTextFieldDelegate` conformance.
- Delete the `entry` parameter from `StandbyPanel.update(...)`, along with its heading and number branches. StandbyPanel itself goes in 2.5.

### 1.5 Key help

**Files:** `Backdrop/Console/KeyHelp.swift` (new).

`?` shows a dark, rounded overlay centred in the console, built from `Keycap`s, listing the keys in Spec.md section 3 with today's wording where it exists. It closes on `?`, on Escape, or on any click. It is shown in both rooms and never takes the keyboard, so `ShowKeys` keeps handling keys while it shows.

**Phase 1 done when:**
- G opens the panel in both rooms and from the projector window;
- digits alone do nothing;
- Space fires from inside the panel;
- P12 can be reached;
- the README's key table is updated, as part of 6.1, or here if Phase 1 ships on its own.

---

## Phase 2: The Booth

### 2.1 Graded booth warnings, in the model

**Files:** `BackdropCore/Sources/BackdropStage/Stage/BoothCheck.swift`, `BackdropCore/Tests/BackdropStageTests/BoothCheckTests.swift`.

- Add `struct BoothWarning: Equatable, Sendable`, with:
  - `id`: an enum with a case per row of Spec.md 2.2;
  - `tier`: `.stop` or `.caution`;
  - `lamp: String?`: nil for a stop;
  - `message: String`: today's text, unchanged.
- Change `warnings(mode:projector:)` to return `[BoothWarning]`, most urgent first: stops, then cautions, each in today's order.
- Add `checklist(mode:projector:showControl:issues:arm:) -> [BoothCheck]` for Beginners. Each check has an `id`, a state of `.fine`, `.caution` or `.stop`, a `text`, and an optional `detail`, with the strings from Spec.md 2.9. Show control comes in as a small value type (`mscDevice: Int?`, `oscPort: Int?`, plus today's `ShowControlProblem?`), so this stays testable.
- **Tests:** keep every existing message assertion, now on `.message`. Add tier and lamp checks for each condition, and checklist cases: all fine; projector closed; OSC port taken; issues present; video arming.

### 2.2 Header: lock, projector lamp, caution lamps

**Files:** `Backdrop/Console/Panels/HeaderView.swift` becomes `Backdrop/Console/Booth/BoothHeader.swift` and `Backdrop/Console/Studio/StudioToolbar.swift` (the toolbar arrives in 5.1; until then the Studio keeps today's header without the GO button). Add `Backdrop/Console/LockControl.swift` and `Backdrop/Console/ProjectorChip.swift`.

**`LockControl`** (SwiftUI) has two faces:
- **Studio:** a prominent button, "Lock for show".
- **Booth:** the pill. It uses `onLongPressGesture(minimumDuration: 1.0, maximumDistance: 12, perform:onPressingChanged:)`, animating a ring with `trim` while it is pressed.
- In both, `.focusable(false)`.
- An accessibility action named "Unlock for editing" performs at once, because a long press isn't practical with VoiceOver. It does no more than Show › Enter Edit Mode already allows.

**`ProjectorChip`:**
- The Booth face is a lamp with text.
- The Studio face adds a 54 × 30 live picture, added in 5.12.
- Its menu holds Open or Close Projector and Choose Projector Display. Build the display items in a new `DisplayMenu.items(for document:)`, factored out of `AppDelegate.menuNeedsUpdate`, so the Show menu and the chip share one implementation.

**Caution lamps:** amber capsules from the `BoothWarning`s whose tier is `.caution`. Clicking one sets `selectedCaution`, which the caution line (2.3) shows.

**Removed:** the Show and Edit `Picker`, the GO button and the `rule` dividers. `HeaderState` loses `goEnabled`, `goTip`, `onGo` and `onMode(Bool)`, and gains `onLock`, `onUnlock` and `warnings`.

### 2.3 Stop bands and the caution line

**Files:** `Backdrop/Console/Booth/WarningBands.swift` (new; replaces `Panels/WarningBox.swift`, which is deleted).

- **Stop bands:** each one is a full-width red band. A white STOP chip in compressed heavy type, then the message at 15 pt. Several stack.
- **Caution line:** one amber line under the header, showing the selected or most urgent caution, truncating, with the full text as a tooltip.
- `ConsoleGeometry` takes the bands' total height as `stopBands`, and everything below moves down.

### 2.4 Monitors

**Files:** `Backdrop/Console/ConsoleWindow.swift`, `Backdrop/Console/Booth/MonitorFrame.swift` (new).

- **`MonitorFrame`** is a `PanelView` subclass. It draws:
  - the tally border: brass or red, or amber pulsing at 1.4 s through a `CABasicAnimation` on `borderColor`, which is off under Reduce Motion;
  - the label row above, with a `Tag` and "N · Name";
  - an optional slate over the picture: BLACKOUT, or "End of the cue sheet".
- **On stage** is today's `preview`, in the left frame. **Next** is today's `nextPreview`, in the right frame.
  - Keep `nextPreview` on screen in both rooms. It is the console's display-link fallback in `ClockSource`, and a hidden view's link doesn't fire.
- **The transition arrow** is a small view between the frames, showing `CueText.transitionNote(standbyCue)`. It reads "carries on" when `standingByGoPoint?.cue.id == playhead.live`, and is hidden when nothing stands by.
- **Run again** is a borderless button with an R `Keycap`, above the On stage frame's right edge, calling `controller.rerun()`.

### 2.5 Standby card and reach

**Files:** `BackdropCore/Sources/BackdropCore/Running/Reach.swift` (new); `BackdropCore/Tests/BackdropCoreTests/ReachTests.swift` (new); `Backdrop/Console/Booth/StandbyCard.swift` (new; replaces `Panels/StandbyPanel.swift`, which is deleted).

**`Show.reach(from id: UUID) -> [Reach]`** lists the cues one GO on `id` sets running. It is the cue, then each following cue while the one before continues. Each `Reach` holds the cue and how it was reached:
- `.go`;
- `.after(ms)`, timed from the GO before;
- `.whenFinished(waitMs)`.

It stops at the first `.whenCued` cue or the end of the sheet.

**Tests:** no continues; an after chain; a when-finished chain; a chain to the last cue; a looping clip that never finishes. The last should stop there, matching `SheetIssue.neverFinishes`.

**`CueText.reach(_ reach: [Reach])`** writes "One GO runs 5, then 6 after 3.0 s" in the form shown in Spec.md 2.4 and 4.2.

**`StandbyCard`** is the SwiftUI view for Spec.md 2.4, fed by the same values `StandbyPanel.update` gets today, minus `entry`, plus `reach`.
- The number is a `Button` with a plain style calling `onGoTo`.
- The number size comes from `BoothFrames.cardNumberSize`.
- The cue point uses `Desk.script(33)`.

### 2.6 GO plate and key row

**Files:** `Backdrop/Console/Booth/GoPlate.swift` (new); `Backdrop/Console/Booth/KeyRow.swift` (new; replaces `Panels/KeyBar.swift`, which is deleted).

- **`GoPlate`:** a SwiftUI button with a custom `ButtonStyle` that is pressed-darker and `.focusable(false)`.
  - The first line is `CueText.goTip(...)` and the second line comes from the reach or the steps. Spec.md 2.5 has the wording.
  - "MSC and OSC fire this too" shows when `ShowControl.shared.mscDeviceID != nil || oscPort != nil`.
  - It is disabled at the end of the sheet.
- **`KeyRow`:** the single line in Spec.md 2.6, using `Keycap`.

### 2.7 Status line and show-control readout

**Files:** `BackdropCore/Sources/BackdropStage/Stage/ShowController.swift`, `Backdrop/ShowControl/ShowControl.swift`, `Backdrop/Intents/ShowIntents.swift`, `Backdrop/Console/StatusLine.swift` (new), and the matching tests.

- **The source of a command becomes a type:** `struct CommandSource: Sendable { enum Kind { case osc, msc, shortcut }; let kind: Kind; let name: String }`, with `description` producing today's strings: "OSC from 10.0.0.12", "MIDI Show Control from …", and the Shortcuts one.
  - `perform(_:from:)` takes a `CommandSource`.
  - `ShowControl.onCommand` and the intents pass one.
- **`ShowController`** gains `public private(set) var messageOrigin: CommandSource?`. It is set alongside `message` inside `perform(_:from:)` and cleared by every other `say`.
- **`StatusLine`** sits at the foot of the rail in both rooms.
  - With an origin, it shows a badge (OSC, MSC or SHORTCUT), flashes green for 0.6 s, and hides 8 s later unless the message changes. The timer is a `DispatchWorkItem`.
  - Without one, it stays until `message` clears, as today.
- **Tests:** in `RemoteCommandTests` or `ShowControllerTests`, `messageOrigin` is set by `perform` and cleared by `go()`.

### 2.8 Beginners

**Files:** `Backdrop/Console/Booth/BeginnersView.swift` (new).

- A SwiftUI view in the On stage monitor's frame, in two columns of compact rows (22 pt), from `checklist(...)` (2.1). The reminders go last, under their heading.
- It shows while `mode == .show && playhead.live == nil`. Once anything is live, the On stage picture takes its place. Re-entering show mode with nothing live shows it again.
- When the projector is closed, the projector row has an **Open Projector** button, which calls the same closure as the header chip.

### 2.9 Recovery

**Files:** `Backdrop/App/BackdropApp.swift`, `Backdrop/Console/Booth/RecoveryView.swift` (new), `BackdropCore/Sources/BackdropStage/Stage/ShowThumbnail.swift` (see 3.2).

- Replace the `NSAlert` in `offerResume(_:in:)` with a sheet: `NSHostingController(rootView: RecoveryView(...))` presented with `window.beginSheet`.
- The view takes the cue, `record.firedAt`, formatted as a short time in the user's locale, and a thumbnail from `ShowThumbnail.image(of: cue, ...)`, loading asynchronously with a black placeholder.
- The default button is Resume, with `.keyboardShortcut(.defaultAction)`. It runs today's exact code: `document.projector?.open()` then `controller.resume(at:)`. Start from the Top just ends the sheet.

### 2.10 Booth snapshots

**Files:** `Backdrop/Debug/Snapshots.swift`.

Replace `console-show`, `console-booth` and the like with these, each through `saveVariants`:

| Snapshot | State |
| --- | --- |
| `booth-beginners` | Before the first GO |
| `booth-standby` | Cue 1 live, a cue with steps standing by |
| `booth-arming` | A video arming |
| `booth-blackout` | Blacked out |
| `booth-stop` | `inBackground` |
| `booth-caution` | Battery 64% and an external disk |
| `booth-end` | End of the sheet |
| `booth-goto`, `booth-goto-missing` | The Go To panel, before and after Return |
| `booth-keyhelp` | The key help |
| `booth-remote` | A message from OSC |
| `booth-small` | The window at 900 × 600 |
| `recovery` | The recovery sheet |

**Phase 2 done when:**
- the Booth matches Spec.md section 2 in every snapshot;
- the safety checks at the end of this plan pass;
- there is no green in the Booth except the projector lamp and fine Beginners rows;
- `ShowControlCheck` and `IntentsCheck` pass, after updating them for `CommandSource`.

---

## Phase 3: The rail

### 3.1 Row anatomy

**Files:** `Backdrop/Console/CueList/CueRowView.swift`, `Backdrop/Console/Desk.swift`.

- Redraw per Spec.md 4.1, taking colours from `Desk.room(mode)`. The rail is told the room: add `room` to `CueListView.update(...)`, replacing today's `editing` flag.
- Keep `Desk.drawTab` with today's square tab. Change "LIVE" to "ON STAGE", which the tab already hides when the row is too short. Rows have 4 pt corners.
- The margin box is drawn with `NSBezierPath(roundedRect:xRadius:5)`.
- `preferredHeight` depends on the room:
  - **Booth:** 16 + 18 + up to two lines of cue point at 16 each.
  - **Studio:** 16 + 18 + 17 for the summary if any + 16 for the cue point if any.
- Remove the continue symbol at the right; continues are drawn as links (3.4).

### 3.2 Thumbnails

**Files:** `BackdropCore/Sources/BackdropStage/Stage/ShowThumbnail.swift`; `BackdropCore/Tests/BackdropStageTests/QuickLookTests.swift`; `Backdrop/Console/CueList/ThumbnailCache.swift` (new).

- **`ShowThumbnail`:** split `image(of show:...)` into `image(of cue: Cue, settings: ShowSettings, width: Int, media:)` and the existing function, which calls the new one with `cue(of:)`. Add `.feed` and `.blank` handling: return nil for a feed, and a filled image for a blank.
- **`ThumbnailCache`:** `@MainActor`, keyed by cue id, holding `(cue: Cue, geometry: Geometry, image: CGImage)`.
  - An entry is stale when the cue or the geometry differs, or when a media file's modification date changed. The cache keeps the dates of the paths it read.
  - Renders run one at a time, in sheet order, starting with the rows on screen. Each finished thumbnail asks only its row to redraw.
  - Size: 112 × 63 px, at 2× for the rail. The storyboard (5.11) asks for 320 px wide.
  - **Video:** the first frame at 0.5 s from `AVAssetImageGenerator`, off the main actor.
  - **Feed:** the `video` SF Symbol on black, drawn by the row with no cache entry.
- **Test:** `ShowThumbnail.image(of: cue, ...)` returns an image for each kind in `kinds`, and for a blank.

### 3.3 Joins in both rooms

**Files:** `Backdrop/Console/CueList/JoinView.swift` (new; replaces `TransitionRowView.swift`, which is deleted); `Backdrop/Console/CueList/CueListView.swift`.

- `CueListView` lays out a join between every pair of cues in both rooms, using `CueText.transitionNote`, with the glyph from Spec.md 4.2.
- Click and right-click work only in the Studio, with today's behaviour: select the transition, or clear it.
- Joins are 20 pt high, or 24 pt when they carry a link (3.4).

### 3.4 Links, spines and reach

**Files:** `Backdrop/Console/CueList/CueListView.swift`, `JoinView.swift`.

- For a cue whose `continueMode.continues`, the join below it draws the link label. `CueListView` draws the spine on its document view, from the centre of one margin box to the next, in a background layer under the rows.
- **Reach line:** in the Booth, after the last row of `show.reach(from: standby)` when that has more than one cue. It is a dim one-line label, added as a lightweight `NSTextField`.

### 3.5 GO steps

**Files:** `Backdrop/Console/CueList/SubCueRowView.swift`.

Restyle with the diamond glyph and the room's colours. Behaviour is unchanged.

### 3.6 Issues on the row

**Files:** `CueRowView.swift`, `CueListView.swift`.

- Pass `[UUID: String]` instead of `Set<UUID>`, built from `show.issues` and `show.message(for:)`. Where a cue has several issues, join them with " · ".
- Draw the amber tab, the hatch and the message line. It is one line, truncated; the tooltip shows the full text.

### 3.7 Studio hover

**Files:** `CueRowView.swift`, `CueListView.swift`.

- Draw the delete and grip only while the pointer is over the row. The hit rects and cursor rects stay active only while it is.
- **The + between rows:** a tracking area on each join, in the Studio, shows a brass + at the left. Clicking it calls `onInsert(after: index)`. The console stands that cue by, then opens the gallery (4.4), so the new cue lands after it. A + above the first cue adds at the start: the gallery is told the position, and `addCues(_:at:_:)` is used instead of `addCue`.

### 3.8 Drop choreography

**Files:** `CueListView.swift`.

- While `drop == .before(i)`, `layoutRows()` inserts a 28 pt slot at `i`, labelled "Drop to add N cues here". `N` is the count of usable files, which the pasteboard already knows before the drop. The rows below animate down with `animator()`.
- While `.onto(id)`, the row outlines in brass and says "Use this picture" or "Use this clip", from the cue's kind.
- The 2 pt `insertion` line remains for reordering by the grip.

### 3.9 Accessibility

**Files:** `CueRowView.swift`, `JoinView.swift`, `SubCueRowView.swift`.

Today's rows have none. Give each row a `.row` role and a label in the form:

> "Cue 5, Safe, next. Keypad, 4 boxes. Cue point: TOM: The combination, Mara. Quickly. Runs on after 3 seconds."

Give joins a label such as "Transition into cue 6: crossfade, 1 second". Add press actions in the Studio for stand-by, delete and move up or down. The last two call `moveCue(_:by:)`, which exists already.

### 3.10 Performance

Add a 300-cue sheet to `Snapshots` (`rail-long`) and time `update(...)` with `os_signpost`. A refresh with nothing changed must not rebuild rows, as today, and must not re-request thumbnails.

**Phase 3 snapshots:** `rail-booth`, `rail-studio-hover`, `rail-chain` (a sheet with an after-wait chain), `rail-issues`, `rail-drop-slot`, `rail-long`.

**Done when:** every snapshot matches Spec.md section 4, and VoiceOver reads a row in full.

---

## Phase 4: The cue gallery

### 4.1 The sheet

**Files:** `Backdrop/Console/Gallery/CueGallery.swift` (new; replaces `AddCueSheet` in `HeaderView.swift`), `Backdrop/Console/Gallery/GalleryCard.swift` (new).

- The layout, groups, search, Return and Escape are as in Spec.md section 5. The search is `Cue.Kind.matching`, unchanged.
- The groups are a table in `CueGallery`, not in `Cue.Kind`, because they are presentation. `Cue.Kind.common` and `others` stay for the menus' order.

### 4.2 Sample cues and media

**Files:** `Backdrop/Console/Gallery/GallerySamples.swift` (new); `Backdrop/GallerySamples/` (new folder) holding `dusk.jpg`, `night.jpg` and `storm.jpg` at 640 × 360 from the sample show, plus `streets.png` from the street map that `Snapshots.streets()` draws, saved once.

- `GallerySamples.cue(for: Cue.Kind) -> Cue` builds each sample in code, from the sample show where possible:
  - **Decryption:** THE LAST LIGHT, with key LANTERN.
  - **Keypad:** 4417 then GOOD.
  - **Anagram:** LISTEN to SILENT.
  - **Cascade:** "COME HOME".
  - **Text message:** from MARA, "Where are you?".
  - **Text conversation:** "Is it done?" then "Not yet."
  - **Text:** "Six weeks later".
  - **Image:** dusk.
  - **Morph:** dusk to night, with the three pairs from the mockup.
  - **Layered image:** night base, with two layers.
  - **Map:** streets, with three stops.
  - **Blank:** black.
- Sample timings are shortened (a clock of 30 ms, a hold of 20) so each loop takes about four seconds.
- `GallerySamples.media(_ path:)` resolves the bundled files.

### 4.3 Previews

**Files:** `Backdrop/Console/Gallery/GalleryPreview.swift` (new).

- Each card hosts a `SurfaceLayer` with a `StageRunner` holding only that kind's renderer, created when the card first scrolls into view and released when the sheet closes.
- One display link on the sheet drives the visible runners' `tick(at:)`. When a runner settles, wait 1.5 s, then `change(to:...)` it again with a snap.
- **Video:** a still `storm.jpg` with a drawn play mark. **Live feed:** a drawn camera graphic. Neither creates a renderer.
- Under Reduce Motion, each card is loaded settled once, using `runner.redraw`.

### 4.4 Wiring

**Files:** `ConsoleWindow.swift`, `HeaderView.swift` or `StudioToolbar.swift`, `MainMenu.swift`.

- Add cue, Edit › Add Cue… (⇧⌘N, unchanged) and the rail's + all open the gallery.
- The gallery gets the position text from where the cue will land, and on a pick calls today's `addCueChosen(kind)`, or `addCues(_:at:_:)` for the start of the sheet.

**Snapshots:** `gallery`, `gallery-search-safe`, `gallery-empty-search`, and `gallery-reduce-motion`, the last using a forced flag in `GalleryPreview` for the snapshot.

**Done when:** every kind shows a live preview, and search, Return and Escape behave as today.

---

## Phase 5: The Studio

### 5.1 Toolbar

**Files:** `Backdrop/Console/Studio/StudioToolbar.swift` (new).

- The items are as in Spec.md 6.1.
- **Stage setup** replaces the Show Settings toggle, using the same `showingShowSettings` state, renamed `showingStageSetup`. Show › Show Settings… is retitled Stage Setup… and its selector renamed to match.
- **Sheet health:** the badge and popover read `show.issues` and `show.message(for:)`. Each row's button calls `controller.standBy(id)`, then closes the popover.

### 5.2 The stage and the bare stage

**Files:** `ConsoleWindow.swift`, `Backdrop/Console/Studio/BareStage.swift` (new).

- The canvas is today's edit-mode `nextPreview` in a frame, as large as `StudioFrames.canvas`. The header shows "Cue N · Kind" and Run again.
- **`BareStage`:** a layer-backed view drawing the model box with `CAShapeLayer`s for the walls and boards, in the icon's colours, as in the mockup. Today's `WordmarkView` is its back wall. It registers for `MediaDrop.pasteboardTypes` and calls `addMediaCues(urls, 0)`.
- The Booth with no cues shows "No cues yet. Hold the lock to edit, then add some." in place of today's sentence.

### 5.3 Inspector regrouped

**Files:** `Backdrop/Console/Editing/CueEditorView.swift`, `SettingsForms.swift`, `CueEditor.swift`; `BackdropCore/Sources/BackdropCore/Show/SettingKey.swift`.

- **`CueEditorView.body`:**
  - Section "In the book": Number, Cue point, Continue, Seconds, and Steps for kinds with `.advance`.
  - Section "On stage": today's `content(cue)`.
  - Then the Look sections.
- **`SettingKey`:** add `public var isTiming: Bool`, true for clock, wave, hold, pause, morphTime, layerTime, flip, move, length and fade. Add `public static let look: [SettingKey]`.
- Rename the label of `.advance` to "Steps". The printed cue sheet uses the label too, which is intended. Update `SettingKeyTests` and any `CueSheet` fixture that prints it, on purpose.
- `SettingGroup.applying(to:)` gains a filter so the Inspector shows only `!isTiming` keys, except Clock, which shows in the timeline header instead.
- `CueSettingsView`, which shows a selected transition, keeps Transition and Wipe from in the Inspector, and drops Fade, which goes to the timeline's In bar.

### 5.4 Look chips

**Files:** `Backdrop/Console/Editing/LookChips.swift` (new); `Backdrop/Console/Editing/ChipArt.swift` (new).

- **`LookChips`:** a SwiftUI grid of buttons, three across, each with a 26 pt high picture and a label. Selected chips get a brass outline. Entrance is toggle chips, one per effect.
- **`ChipArt`:** renders each chip's picture once per launch, offscreen, through the kind's own renderer: a sample cue with only that option changed, painted at a fixed frame with `SeededRandom(seed: 1)`, at 78 × 26 pt @2×, and cached.

  | Setting | Sample and frame |
  | --- | --- |
  | Letters | "G" mid-travel |
  | Order, Reveal | The dusk sample at 40% |
  | Camera | The street map |
  | Context, Entrance, Frame | The layered sample at its second step |

### 5.5 The timeline model

**Files:** `BackdropCore/Sources/BackdropCore/Running/CueTimeline.swift` (new); `BackdropCore/Tests/BackdropCoreTests/CueTimelineTests.swift` (new); a Fixture JSON for the recorded expectations.

**Shape:**

```swift
public struct CueTimeline: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int            // 0 for kinds with no hold
    public var transitionIn: Span?       // nil for the first cue
    public var tracks: [Track]           // the kind's own, in order
    public var goes: [Int]               // frames of GO steps, after the hold
    public var then: Then                // waits, .after(ms), .whenFinished(ms)
    public var endFrame: Int             // when the last part finishes, all parts let go
    public struct Track { var name: String; var spans: [Span] }
    public struct Span { var start: Int; var end: Int; var label: String?; var edits: Edit? }
    public enum Edit { case setting(SettingKey, Handle) ; case contentPause ; case entrance ; case picture(Int) ; case layer(Int) }
    public enum Handle { case end, start, slope }
}
```

**Building it:** `CueTimeline(cue: Cue, show: ShowSettings, isFirst: Bool)` uses the same plans the renderers use, with `SeededRandom(seed: 0)` wherever a plan rolls dice:
- **Decryption:** `TitleReveal`. Make `Travel.total` public. There is one span per moving character, from `start` to `start + total`.
- **Anagram:** `AnagramCuePlan.parts` and `.tracks`.
- **Image:** `TileSchedule.settleFrame(flipMs:clockMs:)`, or `QuarterSchedule.lastStart` plus the flip.
- **Morph, map, layered image:** their `parts`, with `stages`, `legs` or `steps` as spans.
- **Keypad:** the presses at `interval`, and the flash of `KeypadCuePlan.flashTicks`.
- **Cascade:** `parts` and `resolveTicks`.
- **Conversation and text message:** their pause and entrance.
- **Video:** the clip's duration, passed in by the app, because the model can't open files. Add an optional `clipSeconds` parameter.

`goes` comes from accumulating `parts`, with each part let go straight after the one before, as `GoTimeline.carryOnToEnd()` does.

**Tests:** one per kind, asserting frames against hand-worked numbers from that kind's settings. Use sample show cue 1 (hold 44, wave 3) and cue 5 (keypad 4417 then GOOD, pause 14). Record the full output for one show in a fixture, as the repo does for other plans.

### 5.6 The timeline view

**Files:** `Backdrop/Console/Studio/TimelineView.swift` (new, AppKit, drawn); `Backdrop/Console/Studio/TimelinePopover.swift` (new, SwiftUI); `BackdropCore/Sources/BackdropStage/Stage/StageRunner.swift`.

**Drawing:** the ruler in seconds, at 0.25 s ticks, labelled each whole second. Then the tracks of Spec.md 6.5, with the bars, fans, diamonds and hatching as in the mockup. Colours come from the room palette.

**Dragging:**
- On mouse-down, find the span or handle under the pointer. On drag, turn the pointer's x into frames, snapping to whole frames, and map it to a value:
  - **Hold:** ticks = frames.
  - **Pause:** the gap's frames.
  - **Morph, Layer, Flip, Frame move:** ms = frames × clock.
  - **Wave:** the change in slope across the fan, divided by the number of letters, rounded.
  - **Fade:** ms.
  - **Continue:** seconds.
- Clamp to the setting's range, then call `controller.setSetting(key, to: value, for: id, coalescing: true)`, or `edit(..., coalescing: true)` for content pauses, entrances, and a picture's or layer's own time. Drags merge into one undo step.

**Popover:** a click without a drag opens `TimelinePopover` with today's `SettingRowView` for that key, including its `InfoTip`.

**Playhead:** add `public func position(at time: Double) -> Double?` to `StageRunner`, returning the live clock's position, or nil with nothing running. While `nextRunner` runs (after Run again), the view redraws on `nextPreview`'s display link, with a hook on `SurfaceView.step`, and draws the playhead at `position + holdTicks`.

**Accessibility:** each handle is an `NSAccessibilityElement` with `.slider` role, a label ("Hold"), a value ("44 steps, 1.9 seconds"), and increment and decrement actions that change it by one step. Keyboard focus works with Tab, because the Studio may take the keyboard; Escape hands it back to the show keys, as forms do today.

**Run again** from the canvas header and from R both start the playhead.

### 5.7 Transitions in the Studio

**Files:** `ConsoleWindow.swift`, `SettingsPanels.swift`.

Selecting a join, from the rail or the line under the timeline, does what selecting a transition row does today (`selectedTransition`). It also highlights the In bar, and makes the timeline show the cue the transition leads into.

### 5.8 Stage setup on the canvas

**Files:** `Backdrop/Console/Studio/StageSetupOverlay.swift` (new); `ProjectionAreaView.swift` (kept for the numbers, in the Inspector).

- While Stage setup is on, an overlay view sits over the canvas. It draws the output, the area outline, eight handles and the readout. Drags convert to `Geometry` percentages, snapping to 50% centre lines within 1%, and call `controller.setGeometry(_, coalescing: true)`.
- `showsGuides` turns on automatically while the overlay shows, and back off after, unless the user had turned it on.

### 5.9 Morph points in focus mode

**Files:** `Backdrop/Editors/MorphPointsEditor.swift` (new, an `NSView` holding what `MorphPointsWindowController` lays out today); `MorphPointsWindow.swift` (deleted once the editor is in place); `ConsoleWindow.swift`.

- Move the views, actions and `refresh()` from the window controller into `MorphPointsEditor`. Its `undoManagerSource` is the document's, as today.
- `showPoints(for:stage:)` swaps the canvas for the editor, and the timeline for its scrub slider row, until Done or Escape.

### 5.10 Map route in focus mode

**Files:** `Backdrop/Editors/MapRouteWindow.swift` (deleted); `RouteView.swift` and `RouteModel.swift` (kept); `ConsoleWindow.swift`.

`showRoute(for:)` hosts `RouteView(model:)` in an `NSHostingView` in the canvas area until Done or Escape. `RouteView`'s own inspector sits inside it, as today, so the console's Inspector shows the cue's normal groups meanwhile.

### 5.11 Storyboard

**Files:** `Backdrop/Console/Studio/StoryboardView.swift` (new).

An `NSCollectionView` of the `ThumbnailCache` images at 320 px, labelled with cue numbers. A click calls `controller.standBy(id)`, and a double-click also switches back to the stage. The List | Storyboard switch at the top of the rail toggles it, and the choice is saved in the defaults as `ConsoleStoryboard`.

### 5.12 Projector chip with a live picture

**Files:** `ProjectorChip.swift`, `ConsoleWindow.swift`.

In the Studio, reparent today's `preview` SurfaceView, which is attached to `controller.runner`, into the chip at 54 × 30. Move it back to the On stage monitor in the Booth. The runner paints every attached surface on its own tick, so no second runner is needed.

### 5.13 Studio snapshots

| Snapshot | State |
| --- | --- |
| `studio-title` | With the timeline |
| `studio-image` | |
| `studio-keypad` | With GO steps on the timeline |
| `studio-layered` | |
| `studio-transition` | A join selected |
| `studio-stage-setup` | |
| `studio-morph-focus` | |
| `studio-map-focus` | |
| `studio-storyboard` | |
| `studio-empty` | The bare stage |
| `studio-issues` | The sheet health popover |
| `studio-new-cue` | |
| `studio-small` | The window at 900 × 600 |

Each is saved through `saveVariants`, so every one is checked in light, dark and high contrast.

**Done when:** every snapshot matches Spec.md section 6, and every timing setting can be set from the timeline by mouse and by VoiceOver.

---

## Phase 6: Finish

### 6.1 README

Update these sections of `README.md` to match:
- the first-launch steps (Lock for show, the Booth and Studio, Stage setup instead of Show Settings);
- the key table: G and ? added, the number row removed, and the note on keyboard focus rewritten. "Nothing takes the keyboard in show mode except the Go To panel, and Space still fires GO while it is open";
- the paragraph about the console following the Mac's appearance: the Booth is always dark, the Studio follows the Mac;
- the show-control status line;
- the booth checks, now tiered;
- the debug tools: the new snapshot names;
- the repository layout: the `Booth/`, `Studio/`, `Gallery/` and `GoTo/` folders under `Console/`, the removed windows and panels, and `Fonts/` and `GallerySamples/`;
- the description of `ConsoleWindow.swift`, `CueEditor.swift`, `MorphPointsWindow.swift` and `MapRouteWindow.swift`.

### 6.2 Dead code

Make sure these are gone:
- `Panels/HeaderView.swift`, replaced by `BoothHeader` and `StudioToolbar`, and `AddCueSheet` with it;
- `Panels/StandbyPanel.swift`, `Panels/KeyBar.swift` and `Panels/WarningBox.swift`;
- `CueList/TransitionRowView.swift`;
- `Editors/MorphPointsWindow.swift`, keeping `MorphPointsView`, and `Editors/MapRouteWindow.swift`;
- the typed entry in `Playhead` and `ShowController`.

Then search the code for leftover references and for the old strings that went: "Go to cue", "e.g. P12", "Show Settings".

### 6.3 Full check

- `cd BackdropCore && swift test`, and `xcodebuild -project Backdrop.xcodeproj -scheme Backdrop test`.
- Each debug tool into its own folder under `/tmp`, all PASS: `-BackdropDocumentCheck`, `-BackdropMediaCheck`, `-BackdropShowControlCheck`, `-BackdropIntentsCheck`. Update `DocumentCheck` where it reads the cue list's menus or the header.
- `-BackdropSnapshot /tmp/console`, then look through every image in light, dark and high contrast.
- `-BackdropStoreAssets` to regenerate the App Store screenshots in `AppStore/Screenshots/`. The ones there now show the old console.
- **Booth test on real hardware**, with two displays and the projector full screen:
  - run *The Last Light* start to finish by Space alone;
  - repeat it with GO from QLab over OSC;
  - unplug the projector mid-cue;
  - switch to another app;
  - run on battery;
  - open Go To and press Space;
  - type P12 where it doesn't exist;
  - hold Space;
  - press digits, Return, Escape and Delete with nothing open.
- **Accessibility:** VoiceOver through both rooms, the rail, the timeline handles, Go To and the gallery. Then Increase Contrast, Reduce Motion, and a larger text size in System Settings.

---

## Safety invariants

Run these at the end of every phase. The ones that can be automated are listed with their check.

| Rule | How it is checked |
| --- | --- |
| Space is the only key that fires a cue, and it always does, Go To included | `FlapField` and `ShowKeys` code review; the booth test |
| Holding a key never fires more than once | `isARepeat` is checked first in `ShowKeys` and `FlapField`; the booth test |
| No plain key ever beeps | Every path in `ShowKeys` and `FlapField` returns handled |
| Nothing in the Booth takes the keyboard but Go To, and it gives it back when closed | Snapshots of first responder after closing; the booth test |
| Show mode can't be left by a key or a single click | `LockControl` has only the long press and the accessibility action; menu unchanged |
| No GO from Shortcuts or Spotlight | `IntentsCheck` |
| Show control acts only in show mode | `ShowControlCheck`, `RemoteCommandTests` |
| Every booth warning keeps its words | `BoothCheckTests` message assertions |
| An edit is one undo step; drags merge | `EditingTests`; manual timeline drag and undo |
| Renderers' output is unchanged | The recorded fixtures pass untouched. Only changes listed on purpose in a step may alter them |

## Open questions

Each has a default the plan assumes. Change it before the step that needs it.

1. **Cue point type.** The default is Courier Prime, bundled (0.4). The alternative is the system's American Typewriter, with no bundling.
2. **A menu item for Go To.** The default is none: G and the key help only. Adding Show › Go to Cue… with no key equivalent would make it discoverable from the menu bar.
3. **Timing units.** The default keeps timings in steps of the clock, with seconds shown on the timeline. That keeps every recorded output as it is. Storing milliseconds instead would make the clock a pure tempo setting, but it would change every timing fixture.
