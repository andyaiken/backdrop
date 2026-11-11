# Backdrop

Backdrop is a native macOS app for running projections in live theatre. An operator fires cues from a console on the Mac's own display while the projector window runs full-screen on a second display.

## Requirements

- Xcode 27 with Swift 6.4. The code builds under strict concurrency with no warnings, and should stay that way.
- macOS 26 or later to run it. The booth Mac runs macOS 27.

## The sandbox

Backdrop runs in the App Sandbox, as the Mac App Store requires. Its entitlements, in [Backdrop.entitlements](Config/Backdrop.entitlements), are only for what it does:

- the shows and media the operator opens, saves, drops or chooses
- bookmarks to those shows, to open them again by itself
- the camera, for live feed cues
- incoming network connections, for OSC
- printing, for the cue sheet

A sandboxed app may only open a file the operator gave it. So Backdrop keeps a bookmark to each show while it is open (see [ShowBookmarks.swift](Backdrop/Document/ShowBookmarks.swift)). It uses those bookmarks to reopen the last show at launch, the show that was running after a crash, and a show chosen in Spotlight. A show last opened before Backdrop was sandboxed has no bookmark, so the first time, it is opened by hand. Settings start fresh in the sandbox, too.

[PrivacyInfo.xcprivacy](Backdrop/PrivacyInfo.xcprivacy) is the privacy manifest the App Store asks for. It says Backdrop collects nothing and tracks no one. It also gives Apple's reason codes for the two kinds of API Apple asks about: user defaults, for Backdrop's own settings (CA92.1), and file dates, for the earlier versions of a show that won't open (3B52.1). Code that starts using another kind Apple lists, such as boot time, disk space or the active keyboards, needs a reason added there, or the upload is refused.

Debug builds use [Backdrop-Debug.entitlements](Config/Backdrop-Debug.entitlements), which adds two things only the debug launch tools need: outgoing network, for the show control check, and writing to `/tmp`, where every tool puts its results. The App Store refuses both, so release builds have neither. The Quick Look extensions have a sandbox of their own, which can only read the show Quick Look asks about.

## Building and running

Open `Backdrop.xcodeproj` and run the Backdrop scheme (⌘R). From the command line:

```bash
xcodebuild -project Backdrop.xcodeproj -scheme Backdrop -derivedDataPath DerivedData build
```

```bash
open DerivedData/Build/Products/Debug/Backdrop.app
```

On first launch Backdrop opens a new, empty show. To try it:

1. A new show opens in edit mode. Add cues with Add Cue in the header or from the Edit menu. The Inspector beside the preview has two tabs: Cue, for what every cue has, and one named for the kind of cue standing by, for what it runs with. The show's title, text size and projection area are in Show › Show Settings, since none is touched often.
2. Choose Show › Enter Show Mode, then Show › Open Projector.
3. Press Space to fire the standby cue.

| Key | In show mode |
| --- | --- |
| Space | Fire the standby cue, or go to the step of a cue that stands by. No other key fires a cue; only show control, below, can fire one from another machine |
| → ↓ PageDown, ← ↑ PageUp | Stand by the next or previous row: a cue, or one of the GOs a cue waits for |
| 0–9 and `.`, then Return | Stand by a cue by number |
| R | Run the live cue again |
| B | Blackout |

Entering and leaving show mode is deliberately done from the menu only, with no shortcut: a key that silently unlocked the cue sheet mid-performance would be a liability.

In edit mode a cue is dragged by its grip to anywhere in the sheet, taking its number with it. Right-clicking a cue offers to renumber the whole sheet, 1, 2, 3 in running order; it asks first, because cue numbers are what the DSM writes in the book.

Pictures and clips come in from wherever they are:

- **Dragged onto the cue list,** from Finder, Photos, Safari, Mail or another app. They become image and video cues where they are dropped, named for their files and numbered between their neighbours. Several at once go in order of their names, as one undo step. An empty show takes them too, to start the sheet.
- **Dragged onto a cue.** A single picture or clip dropped on the middle of an image, morph, map or video cue goes to that cue. So does one dropped on the Inspector's picture well, or on a morph's or layered image's strip.
- **Edit › Import from iPhone or iPad,** with Continuity Camera. A photo goes into the cue standing by if that is an image cue still waiting for its picture, and otherwise becomes a new image cue after it.
- **Choose…** in the Inspector, whose panel also reaches the Photos library, under Media in its sidebar.

Photos, Safari and Mail don't hand over a file until the drop, so what they send is written into a temporary folder first. Backdrop copies it into the show when the show is saved, as it does a file from Finder.

The console is in the Mac's own controls and follows its light or dark appearance and its accent colour; the stage keeps a palette of its own, because that is the projected picture rather than the interface.

Nothing takes the keyboard in show mode except the Go-to field, so these keys always reach the show. In edit mode a control may take it, and while one does, the keys go to that control instead. Click empty space or press Escape to hand them back.

### Show control

Another machine in the booth can fire Backdrop's cues, so one GO in QLab, or on a lighting desk, runs sound and projection together. Both kinds are off until turned on in Backdrop's Settings, which belong to the Mac rather than the show. In show mode the status line says what each command did and where it came from. In edit mode commands are ignored, and the status line says that too.

- **MIDI Show Control (MSC).** Backdrop listens on every MIDI source: interfaces, USB, other apps such as QLab, and Network MIDI sessions, which are turned on in Audio MIDI Setup › MIDI Network Setup.
  - It answers to its own device ID (1 unless set otherwise) and to All Devices.
  - It only answers the video command formats and All Types, so a lighting desk's MSC for its own cue 12 doesn't fire projection cue 12.
  - GO fires the cue standing by, or the cue it names. LOAD stands a cue by. ALL OFF blacks out, and RESTORE brings the picture back.
  - MSC cue numbers can only contain digits and a decimal point, so a cue numbered P12 can't be reached this way.
- **OSC, over UDP.** Backdrop listens on port 53100 unless set otherwise, which is clear of QLab's own 53000 and 53001. Settings shows the address to send to. If another app already has the port, the console warns.

  | Address | Does |
  | --- | --- |
  | `/backdrop/go` | Fires the cue standing by |
  | `/backdrop/go/12` | Fires cue 12 |
  | `/backdrop/standby/12` | Stands cue 12 by |
  | `/backdrop/blackout/on` | Blacks out |
  | `/backdrop/blackout/off` | Brings the picture back |

  The cue number can also be sent as the message's argument, as in `/backdrop/go 12`.

A GO for a number that isn't in the sheet fires nothing. It doesn't fire whatever happens to be standing by.

In QLab, either:

- add a MIDI cue, set its type to MIDI Show Control, its command format to one of the Video formats, its device ID to Backdrop's, and its command to GO with the cue number; or
- add a Network cue that sends OSC to the Backdrop Mac's address and port, with a message such as `/backdrop/go/12`.

Then group it with the sound cue, or have the sound cue auto-continue into it.

The first time OSC is turned on, macOS may ask whether Backdrop may accept incoming network connections. Allow it, or nothing from another machine arrives.

### Shortcuts and Spotlight

Backdrop offers three actions to Shortcuts, Spotlight and Siri. A Stream Deck can run them too, through its Shortcuts plugin.

| Action | Does |
| --- | --- |
| Open Show | Opens a show, in show mode, ready for GO |
| Stand By Cue | Stands a cue by. It fires nothing |
| Blackout | Turns blackout on or off, or whichever it isn't |

- **Stand By Cue and Blackout only act in show mode,** like show control. The status line says what each did, and the shortcut reports the same.
- **A cue is chosen by its number,** so a shortcut for cue 12 stands by cue 12 of whichever show is open.
- **There is no GO action.** A shortcut mistyped into Spotlight shouldn't be able to fire a cue mid-show. Space and show control are the ways to fire one.

Shows go into Spotlight when they are opened and saved, under their titles and with the words on their cues. Searching for a line in a show finds the show, and choosing it opens it.

### In Finder

Two Quick Look extensions come inside the app:

- **Thumbnail:** Finder shows a show's file as its first cue that puts anything on stage, finished, as the projector would show it. A show with nothing but blanks, clips and camera feeds keeps the plain document icon.
- **Preview:** Space on a show's file shows its cue sheet, as Print Cue Sheet prints it for the stage manager. It's on A4, or on US Letter where that is the paper.

macOS finds them once Backdrop has been opened from wherever it is kept. Each is sandboxed, as macOS requires, and can only read the show it is asked about.

## Repository layout

```
Backdrop.xcodeproj           the app project and its shared scheme
Config/Backdrop-Info.plist   document type and the .backdrop UTI
Config/Backdrop.entitlements the sandbox, and what Backdrop does in it
Config/Backdrop-Debug.entitlements
                             the same, and what the debug launch tools need
Config/BackdropThumbnail-Info.plist,
Config/BackdropPreview-Info.plist,
Config/BackdropQuickLook.entitlements
                             the Quick Look extensions, and their sandbox
Backdrop/                    the app: AppKit windows, menus, documents
  App/                       launch, menus, keys, preferences, the crash record,
                             the booth watch
  Document/                  the show document and its display clock
  Console/                   the console window, its palette, PanelHost, and
                             pictures and clips dragged in from other apps
    CueList/                 the cue list and its rows: cues, transitions, GOs
    Panels/                  the header, standby panel, key bar, wordmark, warning
    Editing/                 edit mode's Inspector: cue editor and settings forms
  Editors/                   edit mode's own windows: morph points, map route
  Projector/                 the projector window and display handling
  ShowControl/               MIDI Show Control and OSC from other machines
  Intents/                   Shortcuts' actions, and shows in Spotlight
  Debug/                     the snapshot, document-check and show-control-check
                             launch tools
  AppIcon.icon               the app icon, an Icon Composer document
QuickLook/                   the Quick Look extensions, each a few lines around
  Thumbnail/                 BackdropStage: Finder's thumbnail of a show
  Preview/                   and the cue sheet, for Space on a show's file
BackdropCore/                a Swift package with two libraries
  Sources/BackdropCore       the show model; no AppKit
    Show/                    shows, cues, settings, the package and the cue sheet
    Running/                 the playhead, the clock, continues, transitions
    Decryption/ Anagrams/    one folder per kind of cue that has a model
    Images/ Morphs/ Maps/
    Keypad/
    ShowControl/             OSC and MSC messages, and what they ask of the show
    Support/                 colour, random numbers, rounding, small helpers
  Sources/BackdropStage      the renderers and the show controller; no windows
    Stage/                   the controller, the runner, surfaces and type
    Decryption/ Anagrams/    one folder per kind of cue: its renderer, and
    Images/ Morphs/ Maps/    its layout and drawing where they need their own
    Keypad/ Text/ Video/
    Blank/
    Printing/                the printed cue sheet
  Tests/                     tests for both, including recorded outputs
tools/package.sh             builds the zip and disk image for another Mac
```

The code is in three layers:

- **BackdropCore** is plain logic: the cue and show model, the cipher and decryption reveal, anagram matching, tile schedules, numbering, the playhead, the tick clock, the `.backdrop` package format and the cue sheet rows. Its tests compare its output exactly against recorded outputs.
- **BackdropStage** paints cues into Core Animation layer trees and runs the show. Its pieces:
  - `SurfaceLayer`: a surface to paint into.
  - One renderer per cue kind: `TitleRenderer`, `AnagramRenderer`, `ImageRenderer`, `LayeredRenderer`, `MorphRenderer`, `MapRenderer`, `KeypadRenderer`, `TextRenderer`, `VideoRenderer` and `BlankRenderer`, all conforming to `CueRenderer`. `MorphRenderer` draws with Metal; it and `MapRenderer` conform to `PaintsBetweenFrames`, so they paint on every display refresh. `AnagramRenderer`, `LayeredRenderer`, `MorphRenderer`, `MapRenderer` and `KeypadRenderer` also conform to `WaitsForGO`, because an anagram cue can stop partway for GO, a layered image cue brings on each layer at a GO, a morph cue of several pictures waits before each stage, a map cue's dot at each stop, and a keypad cue before each stage of keying.
  - `StageRunner`: drives the renderers on every tick.
  - `ShowController`: the keys, the playhead, modes and editing.
  - `ProjectorState`, in [ProjectorPlacement.swift](BackdropCore/Sources/BackdropStage/Stage/ProjectorPlacement.swift): where the projector window goes.
  - `BoothConditions`, in [BoothCheck.swift](BackdropCore/Sources/BackdropStage/Stage/BoothCheck.swift): what the console warns of about the Mac itself. [BoothWatch.swift](Backdrop/App/BoothWatch.swift) reads it from macOS.
  - `CueSheetView`: prints the cue sheet.
  - `ShowThumbnail`: draws a show's first cue, finished, for Finder.

  None of it needs a window, so its tests render offscreen.
- **Backdrop**, the app. Its interface is SwiftUI in the Mac's own controls, hosted in AppKit windows by `PanelHost`. What stays AppKit is the cue list, which draws its own rows and handles its own dragging; the surfaces the renderers paint into; and the document, menu and window plumbing. Its main files:
  - [ShowDocument.swift](Backdrop/Document/ShowDocument.swift) and [DocumentController.swift](Backdrop/App/DocumentController.swift): the document, with one show open at a time.
  - [ConsoleWindow.swift](Backdrop/Console/ConsoleWindow.swift): the console window and where everything in it goes. Given the room, the Inspector stands beside the preview in a column of its own and scrolls; narrower, it sits beneath it.
  - [Projector.swift](Backdrop/Projector/Projector.swift): the projector window and display handling.
  - [CueListView.swift](Backdrop/Console/CueList/CueListView.swift): the cue list, which lays out and drags the rows beside it in `CueList/`.
  - [CueEditor.swift](Backdrop/Console/Editing/CueEditor.swift): the Inspector's two tabs, Cue and the one named for the cue's kind. [SettingsPanels.swift](Backdrop/Console/Editing/SettingsPanels.swift): what takes their place for a selected transition or the Show Settings. Each is a SwiftUI form, in `Editing/`, behind a small AppKit `PanelHost`.
  - [MorphPointsWindow.swift](Backdrop/Editors/MorphPointsWindow.swift) and [MapRouteWindow.swift](Backdrop/Editors/MapRouteWindow.swift): the windows a morph's points and a map's route are laid in, opened from the Inspector.
  - [BackdropApp.swift](Backdrop/App/BackdropApp.swift) and [MainMenu.swift](Backdrop/App/MainMenu.swift): launch and the menus.

Every kind of cue keeps its code in a folder of its own name in each library, so everything about anagrams is in `BackdropCore/Sources/BackdropCore/Anagrams` and `BackdropCore/Sources/BackdropStage/Anagrams`. Files are named for what they hold, mostly one type each; a type's small helpers stay beside it.

### How a cue gets on screen

`TickClock` counts logical frames. A display link samples it, from the projector's screen when the projector is open and from the console's otherwise, and `StageRunner.tick` asks the live renderer to paint that frame.

The projector window and the console's live preview are both surfaces. A renderer paints every surface from one shared plan, so any randomness is rolled once per frame and the two surfaces never disagree. Only `VideoRenderer` treats the two differently: the preview shows a poster and a position readout instead of a second player.

`ShowController` owns the `Playhead`. Its model is standby and live: only GO puts a cue on stage, and a cue marked to follow fires when the one before it settles. An anagram, morph or map cue set to advance on GO waits partway, and each GO it waits for is a step that can stand by like a cue, with a cue point of its own: in edit mode, stand the GO by and the Cue tab's cue point field edits it. Advance and Pause are settings on each cue, shared by all these kinds: on a morph, either GO choice waits for GO before each stage, and on a map before the dot leaves for each stop. GO on a step of the live cue carries it on there, or straight there, forward or back; GO on a step of another cue fires that cue at that step, with the steps before it already done.

In edit mode, every change goes through `ShowController.edit`. That makes it one undo step, and slider drags are merged into a single step. If the cue on stage is affected, it is redrawn in its finished state.

## Tests

The two package test targets hold all the tests. To run them, use either:

```bash
cd BackdropCore && swift test
```

```bash
xcodebuild -project Backdrop.xcodeproj -scheme Backdrop test
```

Set `BACKDROP_SNAPSHOTS` to a folder and the stage tests write PNGs of what they rendered:

```bash
cd BackdropCore && BACKDROP_SNAPSHOTS=/tmp/stage swift test
```

### Recorded outputs

The JSON files in `BackdropCore/Tests/BackdropCoreTests/Fixtures/` are known-good outputs: cipher text, reveal timing, tile schedules and numbering, each from a seeded run. The tests replay the same seeds with `SeededRandom` and compare exactly, so anything that would change what the audience sees fails a test. If a change to one of them is deliberate, update the recorded values with it.

## Debug tools

Debug builds accept five launch arguments. All are for checking the app without a second display or anyone at the keyboard. Each one does its job and quits. Each writes into the folder it is given, which must be under `/tmp`: that is the one place outside the sandbox a debug build may write.

```bash
DerivedData/Build/Products/Debug/Backdrop.app/Contents/MacOS/Backdrop -BackdropSnapshot /tmp/console
```

This renders the console offscreen in several states (show mode, an image turning, the booth warnings, edit mode for several kinds of cue, the Inspector's tabs), along with the morph points and map route windows and the Settings window, and writes the PNGs to the folder.

```bash
DerivedData/Build/Products/Debug/Backdrop.app/Contents/MacOS/Backdrop -BackdropDocumentCheck /tmp/documents
```

This takes a show through importing media, Save As, Save and reopening, with a check at each step, and writes PASS or FAIL lines to `result.txt` in the folder. It also clears Backdrop's Open Recent list, so the scratch show isn't the one reopened next launch.

```bash
DerivedData/Build/Products/Debug/Backdrop.app/Contents/MacOS/Backdrop -BackdropShowControlCheck /tmp/showcontrol
```

This turns show control on for a show held in memory. It sends Backdrop real OSC over the network and real MSC from a virtual MIDI source, checks that each command does what it should, and writes PASS or FAIL lines to `result.txt` in the folder. It leaves the settings, the disk and Open Recent alone.

```bash
DerivedData/Build/Products/Debug/Backdrop.app/Contents/MacOS/Backdrop -BackdropMediaCheck /tmp/media
```

This offers Backdrop pictures and clips the ways other apps do: files as Finder offers them, files promised as Photos and Safari promise them, and pictures as data, as a browser offers them. It also sends photos as an iPhone does. It checks that each lands where it should, and writes PASS or FAIL lines to `result.txt` in the folder. A promised file can only be received during a real drag, so promises are checked only as far as what they say they will be. Dragging from Photos or Safari itself has to be tried by hand.

```bash
DerivedData/Build/Products/Debug/Backdrop.app/Contents/MacOS/Backdrop -BackdropIntentsCheck /tmp/intents
```

This runs the Shortcuts actions and their cue lists against a show held in memory, as Shortcuts would. It puts a show into Spotlight, finds it by a word on one of its cues, and takes it out again. It writes PASS or FAIL lines to `result.txt` in the folder.

## The app icon

`Backdrop/AppIcon.icon` is a layered Icon Composer document, so macOS 26 draws it with Liquid Glass and makes the dark, clear and tinted versions itself. It shows a projection screen of tiles caught in an image cue's diagonal sweep, upstage of a perspective floor: the tiles that have turned are bone, the diagonal that is turning is brass, and the rest are still slate. These are the console's own colours.

Each layer is an SVG in `Assets/`. Open the document in Icon Composer, which comes with Xcode, to change it. To render it from the command line:

```bash
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Backdrop/AppIcon.icon --export-image --output-file /tmp/icon.png --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

## The show document

A show is a `.backdrop` package that behaves as one file in Finder:

```
DaVinciCode.backdrop/
  show.json    the cue sheet (each cue with its own settings), text size, geometry and projector display
  media/       every image and clip, copied in on import
  version      the format version
```

`show.json` is readable JSON, so a show can be diffed in a repository and repaired by hand if it ever has to be. Backdrop autosaves in place and keeps versions with macOS's version history. If a show won't open, the file is left untouched and Backdrop offers to restore an earlier version. A show saved by a newer version of Backdrop is refused rather than rewritten. See [ShowPackage.swift](BackdropCore/Sources/BackdropCore/Show/ShowPackage.swift).

## Copying to another Mac

```bash
tools/package.sh
```

This builds a Release copy from clean and writes two packages to `dist/`. Either one carries the app intact on a thumb drive:

- `Backdrop-<version>.zip`
- `Backdrop-<version>.dmg`, a disk image that opens to the app beside a link to Applications

The app runs on Intel and Apple silicon Macs with macOS 26 or later. On the other Mac, drag Backdrop into Applications and open it. Keep shows on that Mac's internal disk, not on the stick.

### Gatekeeper

Until it is notarised, the app is signed ad hoc, and Gatekeeper rejects it. That only matters when macOS has marked a copy as coming from the internet:

- **Copied from a thumb drive in Finder:** normally not marked, so it opens straight away.
- **Downloaded, emailed or AirDropped:** marked, so macOS blocks it until it is allowed with Open Anyway in System Settings › Privacy & Security.

### Notarising

A notarised app opens on any Mac with no warnings, however it got there. To notarise as well as package:

```bash
tools/package.sh --notarise
```

With `--notarise`, the script:

- signs the app, and the Quick Look extensions inside it, with the team's Developer ID (team `3G846V4G68`)
- sends it to Apple and waits for the result, which usually takes a few minutes
- staples the result to the app
- signs, notarises and staples the disk image in the same way

If Apple refuses either one, the script prints Apple's log and stops.

Each Mac that notarises needs two things, set up once. Andy's Mac has both.

1. **The Developer ID Application certificate in its keychain.** To add it, sign in to the team in Xcode, go to Settings › Accounts, then Manage Certificates… › + › Developer ID Application. Only the account holder can create one.
2. **The notarisation password, saved as the `backdrop-notary` profile.** Make an app-specific password at [account.apple.com](https://account.apple.com), under Sign-In and Security › App-Specific Passwords. Then run this command, which asks for the password and keeps it in the keychain:

   ```bash
   xcrun notarytool store-credentials backdrop-notary --apple-id <your Apple ID> --team-id 3G846V4G68
   ```

The script checks both before it builds anything, and says which one is missing. `BACKDROP_SIGN_IDENTITY` and `BACKDROP_NOTARY_PROFILE` override the certificate and the profile it uses.

## The Mac App Store

On the store Backdrop is **Backdrop: Stage Projections**: plain "Backdrop" is another app's. Under its icon it is still Backdrop.

The App Store signs with different certificates from `tools/package.sh`. The Developer ID certificate is only for copies handed out directly. For the store, the team needs:

- **Apple Distribution**, for the app and its extensions
- **Mac Installer Distribution**, for the package that is uploaded
- a Mac App Store provisioning profile for each of `com.andyaiken.backdrop`, `com.andyaiken.backdrop.thumbnail` and `com.andyaiken.backdrop.preview`

Xcode makes all of these when it uploads, if the account is the team's account holder or an admin.

To submit a version:

1. The first time only, create the app in App Store Connect: Apps › + › New App. Choose macOS, the name above, and the bundle ID `com.andyaiken.backdrop`.
2. Raise `CURRENT_PROJECT_VERSION` in the Backdrop target. The store refuses a build number it has had before. Raise `MARKETING_VERSION` for each new version people will see.
3. In Xcode, Product › Archive.
4. In the Organizer, Distribute App › App Store Connect › Upload, and let Xcode manage signing.
5. In App Store Connect, the first time only:
   - set the privacy label to Data Not Collected, which matches [PrivacyInfo.xcprivacy](Backdrop/PrivacyInfo.xcprivacy)
   - add the screenshots and description
   - write notes for the reviewer: a demo show to open; that the projector opens in a window when there is only one display; that the camera is only for live feed cues; and that the local network is only for OSC, which is off until turned on in Settings

## Before the first real show

- Package the copy for the booth Mac with `tools/package.sh --notarise`.
- Run the booth checklist: a Focus mode is on, the projector's wallpaper is black and automatic updates are off. macOS doesn't let Backdrop check these itself.

Backdrop checks the rest of the booth itself, and says so above the preview for as long as anything is wrong. Two warnings come up in either mode, because they decide where the picture goes:

- The console's display is mirrored, so the projector has no display of its own.
- The projector's display is the main display, so notification banners would appear on it.

The rest only matter on the night, so they come up in show mode only:

- Another app is in front, so Space won't fire GO.
- The Mac is on battery.
- The Mac is hot enough that macOS is slowing it down.
- Low Power Mode is on.
- The show is on an external drive or a server rather than the internal disk.

While a show is open, Backdrop also keeps the Mac and its displays awake, and asks macOS not to nap it or hold back its timers.
