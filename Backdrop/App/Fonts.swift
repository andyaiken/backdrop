import AppKit
import CoreText

/// The fonts Backdrop brings with it: Courier Prime, for cue points, as a
/// prompt book's typewriter. It is under the SIL Open Font License, whose
/// text, `Fonts/OFL.txt`, must ship with the app beside the fonts.
enum Fonts {
    static let faces = ["CourierPrime-Regular", "CourierPrime-Italic"]

    /// Makes the bundled faces available to this process. Called first
    /// thing at launch; a face that fails to register falls back in
    /// `Desk.script(_:italic:)`.
    static func register() {
        let urls = faces.compactMap {
            Bundle.main.url(forResource: $0, withExtension: "ttf")
                ?? Bundle.main.url(forResource: $0, withExtension: "ttf", subdirectory: "Fonts")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
