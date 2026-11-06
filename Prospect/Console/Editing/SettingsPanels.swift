import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// Edit mode's Show tab: the show's title and its defaults.
///
/// AppKit on the outside so the console's layout places it like any other
/// panel; SwiftUI within, in the Mac's own controls.
@MainActor
final class ShowDefaultsPanel: PanelHost<ShowDefaultsView> {
    var onChange: (SettingKey, SettingValue, Bool) -> Void = { _, _, _ in }
    var onTitleChange: (String) -> Void = { _ in }
    /// Return in the title gives the keyboard back to the show keys.
    var finishedEditing: () -> Void = {}

    init() {
        super.init(rootView: ShowDefaultsView(title: "", fallback: "", settings: ShowSettings(),
                                              onTitle: { _ in }, onChange: { _, _, _ in }, onFinishedEditing: {}))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title text: String, fallback: String, settings: ShowSettings) {
        rootView = ShowDefaultsView(
            title: text,
            fallback: fallback,
            settings: settings,
            onTitle: { [weak self] in self?.onTitleChange($0) },
            onChange: { [weak self] key, value, continuous in self?.onChange(key, value, continuous) },
            onFinishedEditing: { [weak self] in self?.finishedEditing() }
        )
    }

    /// Kept for the console's layout, which sizes every panel alike.
    func preferredHeight(width: CGFloat) -> CGFloat { preferredHeight }
}

/// Edit mode's Cue Settings tab: what the cue standing by runs with.
@MainActor
final class CueSettingsPanel: PanelHost<CueSettingsView> {
    var onChange: (SettingKey, SettingValue?, Bool) -> Void = { _, _, _ in }

    init() {
        super.init(rootView: CueSettingsView(cue: nil, defaults: ShowSettings(), onChange: { _, _, _ in }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cue: Cue?, defaults: ShowSettings) {
        rootView = CueSettingsView(
            cue: cue,
            defaults: defaults,
            onChange: { [weak self] key, value, continuous in self?.onChange(key, value, continuous) }
        )
    }
}
