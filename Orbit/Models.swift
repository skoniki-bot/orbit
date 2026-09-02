import Foundation
import SwiftData

// MARK: - Day keys
//
// Completions are stored as "yyyy-MM-dd" strings in the *local* timezone.
// Storing a UTC timestamp instead would record a 10pm check-off as tomorrow,
// and streaks would quietly be wrong for weeks before you noticed.

enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static var today: String { string(Date()) }
}

// MARK: - Habit

@Model
final class Habit {
    var name: String = ""
    var emoji: String = "✅"
    /// Calendar weekdays. 1 = Sunday ... 7 = Saturday.
    var days: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Completion.habit)
    var completions: [Completion]? = []

    init(name: String, emoji: String, days: [Int], sortOrder: Int) {
        self.name = name
        self.emoji = emoji
        self.days = days
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    static let everyDay = [1, 2, 3, 4, 5, 6, 7]
    static let weekdays = [2, 3, 4, 5, 6]

    func isScheduled(on date: Date) -> Bool {
        days.contains(Calendar.current.component(.weekday, from: date))
    }

    func isDone(on date: Date = Date()) -> Bool {
        let key = DayKey.string(date)
        return (completions ?? []).contains { $0.day == key }
    }

    /// Consecutive scheduled days completed, counting back from today.
    /// An unfinished today doesn't break the streak — it just isn't counted yet.
    var streak: Int {
        let done = Set((completions ?? []).map(\.day))
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: Date())
        var count = 0

        if isScheduled(on: cursor), !done.contains(DayKey.string(cursor)) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }

        for _ in 0..<730 {
            if isScheduled(on: cursor) {
                if done.contains(DayKey.string(cursor)) {
                    count += 1
                } else {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// "Every day", "Mon, Wed, Fri", "Sun"
    var scheduleLabel: String {
        if days.count == 7 { return "Every day" }
        if days.isEmpty { return "Never" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    static var starterSet: [Habit] {
        [
            Habit(name: "Warm lemon water", emoji: "🍋", days: everyDay, sortOrder: 0),
            Habit(name: "Soaked almonds", emoji: "🌰", days: everyDay, sortOrder: 1),
            Habit(name: "Cook at home", emoji: "🍲", days: everyDay, sortOrder: 2),
            Habit(name: "Pack lunch", emoji: "🥡", days: weekdays, sortOrder: 3),
            Habit(name: "Gym", emoji: "🏋️", days: [2, 4, 6], sortOrder: 4),
            Habit(name: "Walk", emoji: "🚶", days: everyDay, sortOrder: 5),
            Habit(name: "Skincare", emoji: "🧴", days: everyDay, sortOrder: 6),
            Habit(name: "Phone out of bedroom", emoji: "📵", days: everyDay, sortOrder: 7),
            Habit(name: "Kitchen clean before bed", emoji: "🧽", days: everyDay, sortOrder: 8),
            Habit(name: "Weigh-in", emoji: "⚖️", days: [1], sortOrder: 9)
        ]
    }
}

// MARK: - Completion

@Model
final class Completion {
    /// "yyyy-MM-dd", local timezone.
    var day: String = ""
    var habit: Habit?

    init(day: String, habit: Habit?) {
        self.day = day
        self.habit = habit
    }
}

// MARK: - Store

/// Stored as a raw string on the item so the schema stays CloudKit-friendly.
enum GroceryStore: String, CaseIterable, Identifiable {
    case indian = "Indian"
    case american = "American"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indian:   return "Indian store"
        case .american: return "American store"
        }
    }

    var symbol: String {
        switch self {
        case .indian:   return "bag"
        case .american: return "cart"
        }
    }

    static func from(_ raw: String) -> GroceryStore {
        GroceryStore(rawValue: raw) ?? .indian
    }
}

// MARK: - Grocery
//
// A list is one shopping trip. Exactly one list has savedAt == nil at any
// time — that's the one you're currently building. Saving stamps it with the
// date and a fresh empty list takes its place.

@Model
final class GroceryList {
    /// nil while the list is still being built.
    var savedAt: Date?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.list)
    var items: [GroceryItem]? = []

    init(savedAt: Date? = nil) {
        self.savedAt = savedAt
        self.createdAt = Date()
    }

    var sortedItems: [GroceryItem] {
        (items ?? []).sorted { $0.addedAt < $1.addedAt }
    }

    func items(in store: GroceryStore) -> [GroceryItem] {
        sortedItems.filter { $0.store == store.rawValue }
    }

    var itemCount: Int { (items ?? []).count }

    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: savedAt ?? createdAt)
    }
}

@Model
final class GroceryItem {
    var name: String = ""
    var quantity: Int = 1
    /// GroceryStore raw value.
    var store: String = GroceryStore.indian.rawValue
    var isChecked: Bool = false
    var addedAt: Date = Date()
    var list: GroceryList?

    init(name: String, quantity: Int = 1, store: GroceryStore, list: GroceryList?) {
        self.name = name
        self.quantity = quantity
        self.store = store.rawValue
        self.isChecked = false
        self.addedAt = Date()
        self.list = list
    }
}
