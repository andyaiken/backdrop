import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// The Inspector's Show Settings: the show's title, text size and projection
/// area, in place of a cue's tabs while the header's Show Settings is on.
///
/// AppKit on the outside so the console's layout places it like any other
/// panel; SwiftUI within, in the Mac's own controls.
@MainActor
final class ShowSettingsPanel: PanelHost<ShowSettingsView> {
    var onTextScale: (Int, Bool) -> Void = { _, _ in }
    var onTitle: (String) -> Void = { _ in }
    /// Return in the title gives the keyboard back to the show keys.
    var finishedEditing: () -> Void = {}
    var onGeometry: (Geometry) -> Void = { _ in }
    var onGuides: (Bool) -> Void = { _ in }

    init() {
        super.init(rootView: ShowSettingsView(title: "", fallback: "", settings: ShowSettings(), geometry: Geometry(),
                                              guidesOn: false, outputAspect: 16.0 / 9,
                                              onTitle: { _ in }, onTextScale: { _, _ in }, onFinishedEditing: {},
                                              onGeometry: { _ in }, onGuides: { _ in }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter outputAspect: The projector output's width over its height.
    func update(title text: String, fallback: String, settings: ShowSettings, guidesOn: Bool, outputAspect: Double) {
        rootView = ShowSettingsView(
            title: text,
            fallback: fallback,
            settings: settings,
            geometry: settings.geometry,
            guidesOn: guidesOn,
            outputAspect: outputAspect,
            onTitle: { [weak self] in self?.onTitle($0) },
            onTextScale: { [weak self] value, continuous in self?.onTextScale(value, continuous) },
            onFinishedEditing: { [weak self] in self?.finishedEditing() },
            onGeometry: { [weak self] in self?.onGeometry($0) },
            onGuides: { [weak self] in self?.onGuides($0) }
        )
    }
}

/// Edit mode's Settings and Transitions tabs: what the cue standing by runs
/// with, and how the stage changes to it.
@MainActor
final class CueSettingsPanel: PanelHost<CueSettingsView> {
    var onChange: (SettingKey, SettingValue, Bool) -> Void = { _, _, _ in }
    private let scope: CueSettingsView.Scope

    init(scope: CueSettingsView.Scope) {
        self.scope = scope
        super.init(rootView: CueSettingsView(scope: scope, cue: nil, onChange: { _, _, _ in }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cue: Cue?) {
        rootView = CueSettingsView(
            scope: scope,
            cue: cue,
            onChange: { [weak self] key, value, continuous in self?.onChange(key, value, continuous) }
        )
    }
}
