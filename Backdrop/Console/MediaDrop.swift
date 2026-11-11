import AppKit
import UniformTypeIdentifiers

/// Pictures and clips dragged in from anywhere, brought in as files the show
/// can copy: files from Finder; files promised by Photos, Safari, Mail and
/// other apps, which write them only once they are dropped; and pictures an
/// app offers only as data.
@MainActor
struct MediaDrop {
    /// What each thing offered is, as far as can be told before the drop.
    let types: [UTType]
    private let source: Source

    private enum Source {
        case files([URL])
        case promises([NSFilePromiseReceiver])
        case picture(Data, UTType, name: String)
    }

    /// Every pasteboard type a drop target registers for.
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        + pictureTypes.map { NSPasteboard.PasteboardType($0.identifier) }

    /// Picture data, best first, for an app that offers no file.
    static let pictureTypes: [UTType] = [.png, .heic, .jpeg, .tiff]

    /// What a pasteboard offers: files if it has any, else promised files,
    /// else a picture as data. Nil when it has none of these.
    ///
    /// - Parameter unnamed: The name for a picture offered as data with no
    ///   web address to name it by.
    init?(_ pasteboard: NSPasteboard, unnamed: String = "Picture") {
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            types = files.map { UTType(filenameExtension: $0.pathExtension) ?? .data }
            source = .files(files)
        } else if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
                  !promises.isEmpty {
            types = promises.flatMap { $0.fileTypes.map { UTType($0) ?? .data } }
            source = .promises(promises)
        } else if let type = Self.pictureTypes.first(where: { pasteboard.availableType(from: [.init($0.identifier)]) != nil }),
                  let data = pasteboard.data(forType: .init(type.identifier)) {
            types = [type]
            source = .picture(data, type, name: Self.name(on: pasteboard) ?? unnamed)
        } else {
            return nil
        }
    }

    /// A name for a picture offered as data: the last part of its web
    /// address when the app gives one, as a browser does.
    private static func name(on pasteboard: NSPasteboard) -> String? {
        let web = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { !$0.isFileURL }
        let stem = web?.deletingPathExtension().lastPathComponent ?? ""
        return stem.isEmpty || stem == "/" ? nil : stem
    }

    /// Brings the offered files in, then calls back with them, in no
    /// particular order. Promised files are written by the app they come
    /// from, into a folder of Backdrop's own, and can take a moment: Photos
    /// may first fetch an original from iCloud. Call this while the drop is
    /// being performed, the only time a promise can be received.
    func receive(then: @escaping @MainActor ([URL]) -> Void) {
        switch source {
        case .files(let urls):
            then(urls)
        case .picture(let data, let type, let name):
            guard let folder = Self.inbox() else { return then([]) }
            let url = folder.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "png")
            then((try? data.write(to: url)) != nil ? [url] : [])
        case .promises(let promises):
            guard let folder = Self.inbox() else { return then([]) }
            let arrivals = Arrivals(expected: promises.reduce(0) { $0 + max($1.fileTypes.count, 1) }, then: then)
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                    MainActor.assumeIsolated { arrivals.arrived(error == nil ? url : nil) }
                }
            }
        }
    }

    /// Promised files as they arrive, handed on together once all have, so
    /// several become cues in one step. The count of types an app promises
    /// is only a guide, so any that come after are handed on as they come.
    private final class Arrivals {
        private let expected: Int
        private let then: @MainActor ([URL]) -> Void
        private var count = 0
        private var urls: [URL] = []

        init(expected: Int, then: @escaping @MainActor ([URL]) -> Void) {
            self.expected = expected
            self.then = then
        }

        @MainActor
        func arrived(_ url: URL?) {
            count += 1
            if count > expected {
                if let url { then([url]) }
                return
            }
            if let url { urls.append(url) }
            // They arrive as each is written; in order of their names, the
            // order is the same however long each took.
            if count == expected {
                then(urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            }
        }
    }

    /// A new folder for one drop's files, so names from different drops
    /// can't collide. They stay until the show is saved and they are copied
    /// in, and the system clears the folder away in time.
    static func inbox() -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Backdrop Imports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil ? folder : nil
    }
}
