import AppKit
import SwiftUI

/// Holds a SwiftUI panel inside the console's AppKit layout: an `NSView` the
/// frame-based layout places like any other, with the panel's natural height
/// available to it.
///
/// Nothing in a panel takes the keyboard. The console's root view keeps it so
/// the show keys always reach the cue sheet, and a panel that stole focus
/// would send the arrow keys to a slider instead of the standby cue.
class PanelHost<Content: View>: NSView {
    private let host: NSHostingView<Content>

    /// - Parameter fills: True for a panel that should take the height it is
    ///   given and scroll within it, as a form does; false for one that sits
    ///   at the top at its own natural height.
    init(rootView: Content, fills: Bool = true) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            fills ? host.bottomAnchor.constraint(equalTo: bottomAnchor)
                  : host.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// Swapped whenever the console refreshes, so the panel shows the show.
    var rootView: Content {
        get { host.rootView }
        set { host.rootView = newValue }
    }

    /// The height the panel would like, within reason. A form longer than
    /// this scrolls inside the room it is given: the preview above it must
    /// keep its own space, whatever a panel would rather have.
    var preferredHeight: CGFloat {
        min(host.fittingSize.height, Self.mostUseful)
    }

    /// As tall as a panel is allowed to push the layout.
    static var mostUseful: CGFloat { 320 }

    /// Set by a panel whose views take pictures and clips with `mediaDrop`.
    private var mediaDrops: MediaDropRouter?

    /// Take pictures and clips dropped on the places in the panel marked
    /// with `mediaDrop`.
    func takeMediaDrops() {
        mediaDrops = mediaDrops ?? MediaDropRouter(host: self)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        mediaDrops?.entered(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        mediaDrops?.updated(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        mediaDrops?.ended()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        mediaDrops?.ended()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        mediaDrops?.perform(sender) ?? false
    }

    /// The height the panel needs at a width, for the views the console
    /// places by hand rather than giving a column to.
    func height(width: CGFloat) -> CGFloat {
        let probe = NSHostingController(rootView: host.rootView)
        return probe.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}
