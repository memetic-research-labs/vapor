import AppKit
import SwiftData
import SwiftUI

struct ScreenshotShelfView: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf

    @Query(sort: [SortDescriptor(\ImageAsset.createdAt, order: .reverse)]) private var imageAssets: [ImageAsset]

    private let thumbnailSize = CGSize(width: 132, height: 82)
    private let horizontalInset: CGFloat = 10

    private var visibleAssets: [ImageAsset] {
        imageAssets
            .filter { asset in
                asset.sourceKind == .screenshot && !screenshotShelf.dismissedAssetIDs.contains(asset.id)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    screenshotShelf.isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: screenshotShelf.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Screenshots")
                            .font(.system(size: 11, weight: .semibold))
                        if !visibleAssets.isEmpty {
                            Text("\(visibleAssets.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                }
                .buttonStyle(.plain)

                Text(visibleAssets.isEmpty ? "Take a screenshot or paste an image to stage it here." : "Recent screenshots stay here until you insert them or add them to context.")
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
            .background(.bar)

            if screenshotShelf.isExpanded {
                Divider()

                if visibleAssets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Take a macOS screenshot and it will appear here for quick prompt insertion.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Click to insert an annotated path, or promote the image into context when it deserves to stick around.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(visibleAssets) { asset in
                                ScreenshotShelfCard(asset: asset, thumbnailSize: thumbnailSize)
                            }
                        }
                        .padding(.horizontal, horizontalInset)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ScreenshotShelfCard: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf

    let asset: ImageAsset
    let thumbnailSize: CGSize

    @State private var isHovering = false

    private var nsImage: NSImage? {
        NSImage(contentsOf: screenshotShelf.fileURL(for: asset))
    }

    private var isInserted: Bool {
        screenshotShelf.insertedAssetIDs.contains(asset.id)
    }

    private var isInContext: Bool {
        asset.lifecycleState == .context
    }

    private var primaryBadgeTitle: String {
        if isInContext {
            return "In Context"
        }
        if isInserted {
            return "Inserted"
        }
        return "New"
    }

    private var primaryBadgeColor: Color {
        if isInContext {
            return .green
        }
        if isInserted {
            return .accentColor
        }
        return .secondary
    }

    private var previewScale: CGFloat {
        isHovering ? 1 : 0.94
    }

    var body: some View {
        Button {
            screenshotShelf.insertAnnotatedReference(for: asset)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let nsImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(asset.displayTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(primaryBadgeTitle)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(primaryBadgeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(primaryBadgeColor.opacity(0.12)))
                    }

                    HStack(spacing: 6) {
                        Text(asset.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(asset.sourceKind.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }

                    Text(screenshotShelf.displayPath(for: asset))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    quickActionLabel("Insert", systemName: "text.insert")
                    quickActionLabel("Context", systemName: "tray.and.arrow.down")
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 152, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder((isHovering ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if isHovering, let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 180)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                        .scaleEffect(previewScale)
                        .offset(x: 0, y: -196)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                        .zIndex(10)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                isHovering = hovering
            }
        }
        .zIndex(isHovering ? 10 : 0)
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

            if screenshotShelf.dismissedAssetIDs.contains(asset.id) {
                Button("Restore") {
                    screenshotShelf.restoreDismissed(asset)
                }
            }
        }
    }

    @ViewBuilder
    private func quickActionLabel(_ title: String, systemName: String) -> some View {
        Label(title, systemImage: systemName)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
    }
}
