import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// What the Show Settings window shows, and what its controls do.
@MainActor
final class ShowSettingsState: ObservableObject {
    @Published var title = ""
    @Published var fallback = ""
    @Published var settings = ShowSettings()
    @Published var geometry = Geometry()
    @Published var guidesOn = false
    @Published var outputAspect = 16.0 / 9

    var onDefault: (SettingKey, SettingValue, Bool) -> Void = { _, _, _ in }
    var onTitle: (String) -> Void = { _ in }
    var onFinishedEditing: () -> Void = {}
    var onGeometry: (Geometry) -> Void = { _ in }
    var onGuides: (Bool) -> Void = { _ in }
}

/// The show's defaults and its projection area, in a window of their own.
///
/// Neither is touched often: the defaults are set once for a production, and
/// the projection area once the projector is hung. Keeping them out of the
/// cue editor leaves it to what the operator works in cue by cue.
/// The show's defaults and its projection area, in a window of their own.
///
/// Neither is touched often: the defaults are set once for a production, and
/// the projection area once the projector is hung. Keeping them out of the
/// Inspector leaves it to what the operator works in cue by cue.
///
/// A settings window on the Mac puts its tabs in the toolbar, so this is an
/// `NSTabViewController` in that style with a SwiftUI form in each tab.
@MainActor
final class ShowSettingsWindowController: NSWindowController {
    let state: ShowSettingsState

    init() {
        let state = ShowSettingsState()
        self.state = state

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab(ShowDefaultsTab(state: state), "Show", "slider.horizontal.3", height: 560))
        tabs.addTabViewItem(Self.tab(ProjectionAreaTab(state: state), "Projection Area", "square.dashed", height: 430))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Show Settings"
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// One tab: its form, the name and icon the toolbar shows, and the size
    /// the window takes while it is the one on show.
    private static func tab(_ content: some View, _ label: String, _ symbol: String, height: CGFloat) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: content)
        hosting.preferredContentSize = NSSize(width: Self.width, height: height)
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    private static let width: CGFloat = 540
}

private struct ShowDefaultsTab: View {
    @ObservedObject var state: ShowSettingsState

    var body: some View {
        ShowDefaultsView(
            title: state.title,
            fallback: state.fallback,
            settings: state.settings,
            onTitle: state.onTitle,
            onChange: state.onDefault,
            onFinishedEditing: state.onFinishedEditing
        )
    }
}

private struct ProjectionAreaTab: View {
    @ObservedObject var state: ShowSettingsState

    var body: some View {
        ProjectionAreaView(
            geometry: state.geometry,
            guidesOn: state.guidesOn,
            outputAspect: state.outputAspect,
            onChange: state.onGeometry,
            onGuides: state.onGuides
        )
    }
}
