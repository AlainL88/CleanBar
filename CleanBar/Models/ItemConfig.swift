import Foundation

public struct ItemConfig: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var category: ItemCategory
    public var orderIndex: Int

    public init(id: String, category: ItemCategory, orderIndex: Int = 0) {
        self.id = id
        self.category = category
        self.orderIndex = orderIndex
    }
}
