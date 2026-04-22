import SwiftUI

struct ComposeWorkspaceView: View {
    let totalSize: CGSize
    let showContextTray: Bool
    let toolRail: AnyView
    let editorWorkspace: AnyView
    let contextTray: AnyView

    private let toolRailWidth: CGFloat = 42
    private let contextTrayWidth: CGFloat = 248

    var body: some View {
        let centerWidth = max(640, totalSize.width - toolRailWidth - (showContextTray ? contextTrayWidth : 0) - (showContextTray ? 2 : 1))

        HStack(spacing: 0) {
            toolRail
                .frame(width: toolRailWidth)

            Divider()

            editorWorkspace
                .frame(width: centerWidth, alignment: .leading)
                .frame(minHeight: 300, maxHeight: .infinity)

            if showContextTray {
                Divider()
                contextTray
                    .frame(width: contextTrayWidth)
            }
        }
        .frame(width: totalSize.width, height: totalSize.height, alignment: .leading)
    }
}
