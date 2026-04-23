import SwiftUI

struct ResearchWorkspaceView: View {
    let totalSize: CGSize
    let explorer: AnyView
    let interrogationSidebar: AnyView

    private let interrogationWidth: CGFloat = 350

    var body: some View {
        let explorerWidth = max(720, totalSize.width - interrogationWidth - 1)

        HStack(spacing: 0) {
            explorer
                .frame(width: explorerWidth, alignment: .leading)
                .frame(minHeight: 300, maxHeight: .infinity)

            Divider()

            interrogationSidebar
                .frame(width: interrogationWidth)
        }
        .frame(width: totalSize.width, height: totalSize.height, alignment: .leading)
    }
}
