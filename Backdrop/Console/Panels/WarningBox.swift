import AppKit
import SwiftUI

/// Warnings that stay until they no longer apply, above the preview: the
/// projector's, and the booth's. Most urgent first.
@MainActor
final class WarningBox: PanelHost<WarningBoxView> {
    var messages: [String] = [] {
        didSet {
            guard messages != oldValue else { return }
            rootView = WarningBoxView(messages: messages)
        }
    }

    /// The console gives the box exactly the height it measures at its
    /// width, so the box fills it. Left to its own natural height, the
    /// hosting view would measure every message as one line and spill the
    /// wrapped text out over the header.
    init() {
        super.init(rootView: WarningBoxView(messages: []), fills: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct WarningBoxView: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .fixedSize(horizontal: false, vertical: true)
    }
}
