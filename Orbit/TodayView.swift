import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var isFuture: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    private var scheduled: [Habit] {
        habits.filter { $0.isScheduled(on: selectedDate) }
    }

    private var doneCount: Int {
        scheduled.filter { $0.isDone(on: selectedDate) }.count
    }

    /// "Today", "Yesterday", "Tomorrow", otherwise the weekday name.
    private var eyebrow: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: selectedDate)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        dateNavigator
                        OrbitRing(done: doneCount,
                                  total: scheduled.count,
                                  readOnly: !isToday,
                                  isFuture: isFuture)
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if scheduled.isEmpty {
                    Section {
                        Text(isToday
                             ? "Nothing scheduled today. Add something in Routine."
                             : "Nothing scheduled for this day.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        ForEach(scheduled) { habit in
                            HabitRow(
                                habit: habit,
                                date: selectedDate,
                                editable: isToday,
                                toggle: { toggle(habit) }
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Orbit")
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") {
                            withAnimation(.snappy) {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Date navigation

    private var dateNavigator: some View {
        HStack {
            arrow("chevron.left", days: -1)

            Spacer()

            VStack(spacing: 2) {
                Text(eyebrow)
                    .font(.headline)
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            arrow("chevron.right", days: 1)
        }
    }

    private func arrow(_ symbol: String, days: Int) -> some View {
        Button {
            shift(by: days)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private func shift(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate)
        else { return }
        withAnimation(.snappy) { selectedDate = next }
    }

    // MARK: - Editing

    /// Only reachable from today — other days render as plain rows, not buttons.
    private func toggle(_ habit: Habit) {
        guard isToday else { return }
        let key = DayKey.string(selectedDate)
        if let existing = (habit.completions ?? []).first(where: { $0.day == key }) {
            context.delete(existing)
        } else {
            context.insert(Completion(day: key, habit: habit))
        }
    }
}

// MARK: - Ring

struct OrbitRing: View {
    let done: Int
    let total: Int
    let readOnly: Bool
    let isFuture: Bool

    private var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    private var caption: String {
        if total == 0 { return "Nothing scheduled" }
        if isFuture && done == 0 { return "\(total) scheduled" }
        return "of \(total) done"
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(isFuture && done == 0 ? "—" : "\(done)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
            .frame(width: 88, height: 88)
            .opacity(readOnly ? 0.65 : 1)
            .animation(.snappy, value: fraction)

            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(.title3.weight(.medium))
                if readOnly {
                    Label(isFuture ? "Upcoming" : "Past day", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Row

struct HabitRow: View {
    let habit: Habit
    let date: Date
    let editable: Bool
    let toggle: () -> Void

    private var done: Bool { habit.isDone(on: date) }

    var body: some View {
        if editable {
            Button {
                withAnimation(.snappy) { toggle() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? Theme.accent : Color.secondary.opacity(0.45))

            Text("\(habit.emoji)  \(habit.name)")
                .foregroundStyle(done ? .secondary : .primary)
                .strikethrough(done, color: .secondary)

            Spacer()

            // Streaks count back from today, so they'd be misleading on any other day.
            if editable, habit.streak > 1 {
                Text("\(habit.streak)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.streak)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.streak.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .opacity(editable ? 1 : 0.72)
    }
}
