import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Takes pictures and clips dropped from anywhere, as `MediaDrop` brings
    /// them in: Finder, Photos, Safari, Mail.
    ///
    /// SwiftUI's own drop handling can't receive the files Photos and Safari
    /// promise, and AppKit doesn't look inside a hosting view for an AppKit
    /// view to drop on. So this only marks the place, with a view that takes
    /// nothing itself, and the panel hosting it takes the drop (see
    /// `MediaDropRouter`) and hands it to the place under the pointer.
    func mediaDrop(isTargeted: Binding<Bool>? = nil, accepting accepts: @escaping (UTType) -> Bool,
                   perform: @escaping @MainActor ([URL]) -> Void) -> some View {
        background(MediaDropZone(isTargeted: isTargeted, accepts: accepts, perform: perform))
    }
}

private struct MediaDropZone: NSViewRepresentable {
    var isTargeted: Binding<Bool>?
    var accepts: (UTType) -> Bool
    var perform: @MainActor ([URL]) -> Void

    func makeNSView(context: Context) -> MediaDropZoneView {
        MediaDropZoneView()
    }

    func updateNSView(_ view: MediaDropZoneView, context: Context) {
        view.isTargeted = isTargeted
        view.accepts = accepts
        view.perform = perform
    }
}

/// Where a SwiftUI view takes media: found by the panel's router, never
/// clicked or dropped on itself.
final class MediaDropZoneView: NSView {
    var isTargeted: Binding<Bool>?
    var accepts: (UTType) -> Bool = { _ in false }
    var perform: @MainActor ([URL]) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Takes pictures and clips dragged onto an AppKit view that hosts SwiftUI,
/// and hands them to the `mediaDrop` place under the pointer, if one takes
/// them. A drag anywhere else on the view is refused.
@MainActor
final class MediaDropRouter {
    private unowned let host: NSView
    private var offer: MediaDrop?
    private weak var zone: MediaDropZoneView? {
        didSet {
            guard zone !== oldValue else { return }
            oldValue?.isTargeted?.wrappedValue = false
            zone?.isTargeted?.wrappedValue = true
        }
    }

    init(host: NSView) {
        self.host = host
        host.registerForDraggedTypes(MediaDrop.pasteboardTypes)
    }

    func entered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        offer = MediaDrop(sender.draggingPasteboard)
        return updated(sender)
    }

    func updated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        zone = offer.flatMap { offer in
            Self.zones(in: host).last { zone in
                host.convert(zone.visibleRect, from: zone).contains(host.convert(sender.draggingLocation, from: nil))
                    && offer.types.contains(where: zone.accepts)
            }
        }
        return zone == nil ? [] : .copy
    }

    func ended() {
        offer = nil
        zone = nil
    }

    func perform(_ sender: any NSDraggingInfo) -> Bool {
        guard let offer, let zone else {
            ended()
            return false
        }
        let accepts = zone.accepts, perform = zone.perform
        ended()
        offer.receive { urls in
            let taken = urls.filter { UTType(filenameExtension: $0.pathExtension).map(accepts) ?? false }
            if !taken.isEmpty { perform(taken) }
        }
        return true
    }

    /// Every place in the view, outermost first, so the last that contains
    /// the pointer is the innermost.
    private static func zones(in view: NSView) -> [MediaDropZoneView] {
        view.subviews.flatMap { sub -> [MediaDropZoneView] in
            guard !sub.isHiddenOrHasHiddenAncestor else { return [] }
            return (sub as? MediaDropZoneView).map { [$0] } ?? zones(in: sub)
        }
    }
}
