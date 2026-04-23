import SwiftUI

struct JSONTreeExplorerView: View {
    let rootNode: JSONTreeNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                treeContent
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var treeContent: some View {
        if rootNode.isExpandable {
            ForEach(rootNode.children) { child in
                JSONTreeRowView(node: child, depth: 0)
            }
        } else {
            JSONTreeRowView(node: rootNode, depth: 0)
        }
    }
}

private struct JSONTreeRowView: View {
    let node: JSONTreeNode
    let depth: Int

    @State private var isExpanded: Bool

    init(node: JSONTreeNode, depth: Int) {
        self.node = node
        self.depth = depth
        _isExpanded = State(initialValue: depth == 0)
    }

    var body: some View {
        if node.isExpandable {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(node.children) { child in
                        JSONTreeRowView(node: child, depth: depth + 1)
                    }
                }
            } label: {
                rowLabel
            }
            .padding(.leading, CGFloat(depth) * 14)
            .padding(.vertical, 2)
        } else {
            rowLabel
                .padding(.leading, CGFloat(depth) * 14 + 20)
                .padding(.vertical, 2)
        }
    }

    private var rowLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(node.key ?? "$")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            if let displayValue = node.displayValue {
                Text(displayValue)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(valueColor)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(node.typeLabel.lowercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let countLabel = node.countLabel {
                Text(countLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var valueColor: Color {
        switch node.valueKind {
        case .string:
            return .accentColor
        case .number:
            return .purple
        case .bool:
            return .green
        case .null:
            return .secondary
        case .object, .array:
            return .primary
        }
    }
}
