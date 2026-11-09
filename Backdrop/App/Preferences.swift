import AppKit
import BackdropStage
import SwiftUI

/// Where each of Backdrop's settings is kept in the user defaults.
enum Preferences {
    /// Open the most recent show on launch. On unless turned off.
    static let reopenLastShow = "ReopenLastShow"
    /// What the projector does when a show's display isn't connected: a
    /// `MissingDisplay` raw value. A window unless set otherwise.
    static let missingDisplay = "MissingProjectorDisplay"
}

/// Backdrop's settings. Almost nothing belongs here: everything that varies
/// by production is in the show document, so it travels with the show. What
/// is left belongs to the Mac.
///
/// The window is AppKit's, as every window in Backdrop is; what is in it is
/// SwiftUI. Each control reads and writes its setting in the user defaults
/// directly, so the window always shows what is set, with nothing to refresh.
@MainActor
final class PreferencesWindowController: NSWindowController {
    init() {
        let content = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.setContentSize(content.view.fittingSize)
        window.title = "Settings"
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PreferencesView: View {
    // The defaults here only show until the app registers its own, at launch.
    @AppStorage(Preferences.reopenLastShow) private var reopenLastShow = true
    @AppStorage(Preferences.missingDisplay) private var missingDisplay = MissingDisplay.window

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $reopenLastShow) {
                    Text("Reopen the last show when Backdrop starts")
                    Text("So the first thing to do on the night is press GO, not find a file.")
                }
            }

            Section {
                Picker("When a show\u{2019}s projector display isn\u{2019}t connected", selection: $missingDisplay) {
                    Text("Open the projector in a window on the console\u{2019}s display").tag(MissingDisplay.window)
                    Text("Use another connected display until it returns").tag(MissingDisplay.anotherDisplay)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Either way, the projector moves to the show\u{2019}s display as soon as it is connected.")
                    Text("These belong to this Mac. Everything else is kept with the show.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
