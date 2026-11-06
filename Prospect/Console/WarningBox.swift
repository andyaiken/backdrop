import AppKit
import SwiftUI

/// A warning that stays until it no longer applies, above the preview.
@MainActor
final class WarningBox: PanelHost<WarningBoxView> {
    var message = "" {
        didSet {
            guard message != oldValue else { return }
            rootView = WarningBoxView(message: message)
        }
    }

    init() {
        super.init(rootView: WarningBoxView(message: ""), fills: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct WarningBoxView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .fixedSize(horizontal: false, vertical: true)
    }
}
