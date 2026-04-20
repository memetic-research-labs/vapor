import AppKit
import SwiftData
import SwiftUI

struct ScreenshotShelfView: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf
    @Environment(MainWindowFocusStore.self) private var focusStore

    @Query private var imageAssets: [ImageAsset]

    private let thumbnailSize = CGSize(width: 132, height: 82)
    private let horizontalInset: CGFloat = 10
    private let headerHeight: CGFloat = 44

    @State private var focusedAssetID: UUID?

    init() {
        let screenshotRaw = ImageSourceKind.screenshot.rawValue
        _imageAssets = Query(
            filter: #Predicate<ImageAsset> { asset in
                asset.sourceKindRaw == screenshotRaw && !asset.dismissedFromShelf
            },
            sort: [SortDescriptor(\ImageAsset.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            headerView

            if screenshotShelf.isExpanded {
                Divider()

                contentView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .vaporFocusScreenshots)) { _ in
            guard !imageAssets.isEmpty else { return }
            screenshotShelf.isExpanded = true
            focusStore.focus(.screenshots)
            focusedAssetID = imageAssets.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporScreenshotMoveLeft)) { _ in
            guard focusStore.activeZone == .screenshots,
                  let focusedAssetID else { return }
            moveFocus(by: -1, currentAssetID: focusedAssetID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporScreenshotMoveRight)) { _ in
            guard focusStore.activeZone == .screenshots,
                  let focusedAssetID else { return }
            moveFocus(by: 1, currentAssetID: focusedAssetID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporScreenshotInsertSelected)) { _ in
            guard focusStore.activeZone == .screenshots,
                  let focusedAsset = currentSelectedAsset else { return }
            screenshotShelf.insertAnnotatedReference(for: focusedAsset)
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Button {
                screenshotShelf.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: screenshotShelf.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Screenshots")
                        .font(.system(size: 11, weight: .semibold))
                    if !imageAssets.isEmpty {
                        Text("\(imageAssets.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }
            }
            .buttonStyle(.plain)

            Text(imageAssets.isEmpty ? "Take a screenshot to stage it here." : headerHintText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            if let lastScanDate = screenshotShelf.lastScanDate {
                Text("Updated \(lastScanDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if screenshotShelf.isScanning {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Refresh") {
                Task { await screenshotShelf.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 8)
        .frame(height: headerHeight)
        .background(.bar)
    }

    @ViewBuilder
    private var contentView: some View {
        if imageAssets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Take a macOS screenshot and it will appear here for quick prompt insertion.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Press Return to insert, or Add to Context when the image deserves to stick around.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(imageAssets) { asset in
                            ScreenshotShelfCard(
                                asset: asset,
                                thumbnailSize: thumbnailSize,
                                isFocused: focusedAssetID == asset.id,
                                onSelect: {
                                    focusStore.focus(.screenshots)
                                    focusedAssetID = asset.id
                                },
                                onInsert: {
                                    screenshotShelf.insertAnnotatedReference(for: asset)
                                }
                            )
                            .id(asset.id)
                        }
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    if focusedAssetID == nil {
                        focusedAssetID = imageAssets.first?.id
                    }
                }
                .onChange(of: imageAssets.map(\.id)) { _, ids in
                    guard let focusedAssetID else {
                        self.focusedAssetID = ids.first
                        return
                    }

                    if !ids.contains(focusedAssetID) {
                        self.focusedAssetID = ids.first
                    }
                }
                .onChange(of: focusedAssetID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var currentSelectedAsset: ImageAsset? {
        if let focusedAssetID,
           let asset = imageAssets.first(where: { $0.id == focusedAssetID }) {
            return asset
        }

        return nil
    }

    private func moveFocus(by delta: Int, currentAssetID: UUID) {
        let ids = imageAssets.map(\.id)
        guard let currentIndex = ids.firstIndex(of: currentAssetID) else {
            focusedAssetID = ids.first
            return
        }

        let nextIndex = min(max(0, currentIndex + delta), ids.count - 1)
        focusedAssetID = ids[nextIndex]
    }

    private var headerHintText: String {
        if focusStore.activeZone == .screenshots {
            return "Return inserts · ⌘⇧I returns to the editor"
        }
        return "Recent screenshots stay here until you insert them or add them to context."
    }
}

private struct ScreenshotShelfCard: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf

    let asset: ImageAsset
    let thumbnailSize: CGSize
    let isFocused: Bool
    let onSelect: () -> Void
    let onInsert: () -> Void

    var body: some View {
        Button {
            onSelect()
            onInsert()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    ImageAssetThumbnailView(asset: asset, size: thumbnailSize, preferThumbnail: true, contentMode: .fill) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                            Image(systemName: "photo")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(asset.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(asset.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 152, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder((isFocused ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.08)), lineWidth: isFocused ? 1.5 : 1)
            )
            .editorGlow(isFocused: isFocused)
            .scaleEffect(isFocused ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .zIndex(isFocused ? 10 : 0)
        .contextMenu {
            Button("Insert Screenshot Reference") {
                screenshotShelf.insertAnnotatedReference(for: asset)
            }

            Button("Insert Plain Path") {
                screenshotShelf.insertPlainPath(for: asset)
            }

            Button("Add to Context") {
                screenshotShelf.addToContext(asset)
            }

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: screenshotShelf.displayPath(for: asset))])
            }

            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: screenshotShelf.displayPath(for: asset)))
            }

            Divider()

            Button("Dismiss") {
                screenshotShelf.dismiss(asset)
            }
        }
    }

}
