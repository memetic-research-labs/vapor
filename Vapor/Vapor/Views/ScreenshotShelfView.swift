import AppKit
import SwiftData
import SwiftUI

struct ScreenshotShelfView: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf

    @Query(sort: [SortDescriptor(\ImageAsset.createdAt, order: .reverse)]) private var imageAssets: [ImageAsset]

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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
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

                    Text("Recent screenshots stay here until you insert them or promote them into context.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

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

                if screenshotShelf.isExpanded {
                    if visibleAssets.isEmpty {
                        Text("Take a macOS screenshot and it will appear here for quick prompt insertion.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(visibleAssets) { asset in
                                    ScreenshotShelfCard(asset: asset)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct ScreenshotShelfCard: View {
    @Environment(ScreenshotShelfStore.self) private var screenshotShelf

    let asset: ImageAsset

    private var nsImage: NSImage? {
        NSImage(contentsOf: screenshotShelf.fileURL(for: asset))
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
                .frame(width: 180, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(asset.displayTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if screenshotShelf.insertedAssetIDs.contains(asset.id) {
                            Text("Inserted")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }

                    Text(asset.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(screenshotShelf.displayPath(for: asset))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 180, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
