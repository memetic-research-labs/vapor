import CoreFoundation
import Foundation

enum JSONValueKind: String, Sendable {
    case object
    case array
    case string
    case number
    case bool
    case null
}

struct JSONTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let key: String?
    let path: String
    let valueKind: JSONValueKind
    let displayValue: String?
    let count: Int?
    let children: [JSONTreeNode]

    var isExpandable: Bool {
        !children.isEmpty
    }

    var typeLabel: String {
        switch valueKind {
        case .object: return "Object"
        case .array: return "Array"
        case .string: return "String"
        case .number: return "Number"
        case .bool: return "Bool"
        case .null: return "Null"
        }
    }

    var countLabel: String? {
        guard let count else { return nil }
        switch valueKind {
        case .object:
            return "\(count) key\(count == 1 ? "" : "s")"
        case .array:
            return "\(count) item\(count == 1 ? "" : "s")"
        default:
            return nil
        }
    }
}

enum JSONTreeParser {
    static func parse(_ content: String) -> JSONTreeNode? {
        guard let data = content.data(using: .utf8) else { return nil }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return makeNode(key: nil, value: jsonObject, path: "$")
    }

    private static func makeNode(key: String?, value: Any, path: String) -> JSONTreeNode {
        if let dictionary = value as? [String: Any] {
            let children = dictionary.map { childKey, childValue in
                makeNode(key: childKey, value: childValue, path: pathForObjectChild(parent: path, key: childKey))
            }
            return JSONTreeNode(
                id: path,
                key: key,
                path: path,
                valueKind: .object,
                displayValue: nil,
                count: dictionary.count,
                children: children
            )
        }

        if let array = value as? [Any] {
            let children = array.enumerated().map { index, childValue in
                makeNode(key: "[\(index)]", value: childValue, path: pathForArrayChild(parent: path, index: index))
            }
            return JSONTreeNode(
                id: path,
                key: key,
                path: path,
                valueKind: .array,
                displayValue: nil,
                count: array.count,
                children: children
            )
        }

        if let string = value as? String {
            return JSONTreeNode(
                id: path,
                key: key,
                path: path,
                valueKind: .string,
                displayValue: #""# + string + #""#,
                count: nil,
                children: []
            )
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return JSONTreeNode(
                    id: path,
                    key: key,
                    path: path,
                    valueKind: .bool,
                    displayValue: number.boolValue ? "true" : "false",
                    count: nil,
                    children: []
                )
            }

            return JSONTreeNode(
                id: path,
                key: key,
                path: path,
                valueKind: .number,
                displayValue: number.stringValue,
                count: nil,
                children: []
            )
        }

        return JSONTreeNode(
            id: path,
            key: key,
            path: path,
            valueKind: .null,
            displayValue: "null",
            count: nil,
            children: []
        )
    }

    private static func pathForObjectChild(parent: String, key: String) -> String {
        guard parent != "$" else { return "$.\(key)" }
        return parent + "." + key
    }

    private static func pathForArrayChild(parent: String, index: Int) -> String {
        parent + "[\(index)]"
    }
}
