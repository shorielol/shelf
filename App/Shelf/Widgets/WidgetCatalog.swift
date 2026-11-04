import ShelfCore
import SwiftUI

/// Every widget Shelf ships. Order is the gallery order.
enum WidgetCatalog {
    static let all: [WidgetDescriptor] = musicWidgets + timeWidgets + infoWidgets + productivityWidgets + ambientWidgets

    static func descriptor(for kind: String) -> WidgetDescriptor? {
        index[kind]
    }

    static func widgets(in category: WidgetCategory) -> [WidgetDescriptor] {
        all.filter { $0.category == category }
    }

    private static let index: [String: WidgetDescriptor] = Dictionary(all.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
}
