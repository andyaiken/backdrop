import AppKit
import BackdropCore
import BackdropStage
import QuickLookUI

/// What Quick Look shows when a show's file is previewed with Space: its cue
/// sheet, as File › Print Cue Sheet prints it for the stage manager.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        // The cue sheet is a view, and drawn on the main thread.
        let (sheet, paper) = try await MainActor.run { try Self.cueSheet(of: url) }
        // Called on a thread of Quick Look's own, so never the main actor's.
        return QLPreviewReply(dataOfContentType: .pdf, contentSize: paper) { @Sendable _ in sheet }
    }

    /// The sheet on US Letter where that is the paper, A4 everywhere else.
    @MainActor
    private static func cueSheet(of url: URL) throws -> (Data, CGSize) {
        let paper = Locale.current.measurementSystem == .us ? CueSheetView.letter : CueSheetView.a4
        let package = try FileWrapper(url: url, options: [])
        let show = try ShowPackage.read(package)
        let title = show.title.isEmpty ? url.deletingPathExtension().lastPathComponent : show.title
        guard let data = CueSheetPrinting.pdfData(for: show, title: title, paper: paper) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (data, paper)
    }
}
