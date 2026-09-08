import Foundation

/// Channel/title counts for a section list, computed in **one pass** over the catalog.
///
/// The obvious implementation — each row asking "how many items are in me?" and
/// filtering the catalog to find out — is O(items x sections) on every single render.
/// With a few hundred provider categories over a catalog of thousands, that is millions
/// of comparisons per frame on the main thread, which is what made opening a tab hang.
struct SectionCounts {
    private var byCategory: [String: Int] = [:]
    private(set) var total = 0
    private(set) var favorites = 0
    private(set) var history = 0

    init() {}

    init<Item>(
        items: [Item],
        itemID: (Item) -> String,
        categoryID: (Item) -> String?,
        isFavorite: (Item) -> Bool,
        historyIDs: [String]
    ) {
        total = items.count
        var presentIDs = Set<String>(minimumCapacity: items.count)

        for item in items {
            if let category = categoryID(item) {
                byCategory[category, default: 0] += 1
            }
            if isFavorite(item) {
                favorites += 1
            }
            presentIDs.insert(itemID(item))
        }

        // History can name items the catalog no longer carries, so it's counted by
        // what actually resolves — matching what the section itself will show.
        history = historyIDs.count { presentIDs.contains($0) }
    }

    func count(forCategory id: String) -> Int {
        byCategory[id] ?? 0
    }
}

private extension Array where Element == String {
    func count(_ isIncluded: (String) -> Bool) -> Int {
        reduce(0) { $0 + (isIncluded($1) ? 1 : 0) }
    }
}
