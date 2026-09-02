import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Wire format
//
// Keyed by habit *name* rather than persistent ID. IDs mean nothing in a
// fresh install, so name matching is what lets a restore merge into an
// existing app instead of duplicating everything.

struct BackupPayload: Codable {
    var version: Int = 3
    var exportedAt: Date = Date()
    var habits: [HabitBackup] = []
    var groceryLists: [GroceryListBackup] = []
}

struct HabitBackup: Codable {
    var name: String
    var emoji: String
    var days: [Int]
    var sortOrder: Int
    /// "yyyy-MM-dd" strings.
    var completions: [String]
}

struct GroceryListBackup: Codable {
    var savedAt: Date?
    var createdAt: Date
    var items: [GroceryItemBackup]
}

struct GroceryItemBackup: Codable {
    var name: String
    var quantity: Int
    var isChecked: Bool
    /// Optional so backups written before stores existed still decode.
    var store: String?
}

// MARK: - Document

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export / restore

enum Backup {

    static func filename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Orbit-backup-\(formatter.string(from: Date()))"
    }

    static func makeDocument(habits: [Habit], lists: [GroceryList]) -> BackupDocument {
        let payload = BackupPayload(
            habits: habits.map { habit in
                HabitBackup(
                    name: habit.name,
                    emoji: habit.emoji,
                    days: habit.days,
                    sortOrder: habit.sortOrder,
                    completions: (habit.completions ?? []).map(\.day).sorted()
                )
            },
            groceryLists: lists.map { list in
                GroceryListBackup(
                    savedAt: list.savedAt,
                    createdAt: list.createdAt,
                    items: list.sortedItems.map {
                        GroceryItemBackup(name: $0.name,
                                          quantity: $0.quantity,
                                          isChecked: $0.isChecked,
                                          store: $0.store)
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return BackupDocument(data: (try? encoder.encode(payload)) ?? Data())
    }

    struct RestoreResult {
        var habitsAdded = 0
        var habitsMatched = 0
        var completionsAdded = 0
        var listsAdded = 0

        var summary: String {
            "\(habitsAdded) habits added, \(habitsMatched) matched, "
            + "\(completionsAdded) days restored, \(listsAdded) grocery lists."
        }
    }

    /// Additive. Never deletes anything already present, and never
    /// duplicates a completion or a list that's already recorded.
    @discardableResult
    static func restore(
        from data: Data,
        existingHabits: [Habit],
        existingLists: [GroceryList],
        context: ModelContext
    ) throws -> RestoreResult {

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        var result = RestoreResult()

        // --- Habits ---
        var byName = Dictionary(
            existingHabits.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var nextOrder = (existingHabits.map(\.sortOrder).max() ?? -1) + 1

        for incoming in payload.habits {
            let habit: Habit
            if let match = byName[incoming.name] {
                habit = match
                result.habitsMatched += 1
            } else {
                habit = Habit(
                    name: incoming.name,
                    emoji: incoming.emoji,
                    days: incoming.days,
                    sortOrder: nextOrder
                )
                nextOrder += 1
                context.insert(habit)
                byName[incoming.name] = habit
                result.habitsAdded += 1
            }

            let recorded = Set((habit.completions ?? []).map(\.day))
            for day in incoming.completions where !recorded.contains(day) {
                context.insert(Completion(day: day, habit: habit))
                result.completionsAdded += 1
            }
        }

        // --- Grocery lists ---
        // Saved lists are identified by their save timestamp. The open list
        // is skipped so a restore never clobbers what you're building now.
        let existingStamps = Set(existingLists.compactMap(\.savedAt))

        for incoming in payload.groceryLists {
            guard let savedAt = incoming.savedAt else { continue }
            guard !existingStamps.contains(savedAt) else { continue }

            let list = GroceryList(savedAt: savedAt)
            context.insert(list)
            for item in incoming.items {
                let restored = GroceryItem(
                    name: item.name,
                    quantity: item.quantity,
                    store: GroceryStore.from(item.store ?? GroceryStore.indian.rawValue),
                    list: list
                )
                restored.isChecked = item.isChecked
                context.insert(restored)
            }
            result.listsAdded += 1
        }

        return result
    }
}
