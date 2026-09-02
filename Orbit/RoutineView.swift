import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RoutineView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @Query private var lists: [GroceryList]

    @State private var editing: Habit?
    @State private var isAdding = false

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits) { habit in
                    Button {
                        editing = habit
                    } label: {
                        HStack(spacing: 12) {
                            Text(habit.emoji)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name).foregroundStyle(.primary)
                                Text(habit.scheduleLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                Section {
                    Button {
                        isExporting = true
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Deleting the app erases everything. Export before you delete, then restore afterwards.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Routine")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { habit in
                HabitEditor(
                    name: habit.name,
                    emoji: habit.emoji,
                    days: Set(habit.days)
                ) { name, emoji, days in
                    habit.name = name
                    habit.emoji = emoji
                    habit.days = days.sorted()
                }
            }
            .sheet(isPresented: $isAdding) {
                HabitEditor(name: "", emoji: "✅", days: Set(Habit.everyDay)) { name, emoji, days in
                    let order = (habits.map(\.sortOrder).max() ?? -1) + 1
                    context.insert(
                        Habit(name: name, emoji: emoji, days: days.sorted(), sortOrder: order)
                    )
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: Backup.makeDocument(habits: habits, lists: lists),
                contentType: .json,
                defaultFilename: Backup.filename()
            ) { outcome in
                switch outcome {
                case .success:
                    alertMessage = "Backup saved."
                case .failure(let error):
                    alertMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json]
            ) { outcome in
                handleImport(outcome)
            }
            .alert("Backup", isPresented: .constant(alertMessage != nil)) {
                Button("OK") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func handleImport(_ outcome: Result<URL, Error>) {
        switch outcome {
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"

        case .success(let url):
            // Files handed over by the picker live outside the sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let result = try Backup.restore(
                    from: data,
                    existingHabits: habits,
                    existingLists: lists,
                    context: context
                )
                alertMessage = result.summary
            } catch {
                alertMessage = "Couldn't read that file: \(error.localizedDescription)"
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(habits[index])
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = habits
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }
    }
}

struct HabitEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var days: Set<Int>

    private let onSave: (String, String, Set<Int>) -> Void
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    init(
        name: String,
        emoji: String,
        days: Set<Int>,
        onSave: @escaping (String, String, Set<Int>) -> Void
    ) {
        _name = State(initialValue: name)
        _emoji = State(initialValue: emoji)
        _days = State(initialValue: days)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                }

                Section("When") {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let selected = days.contains(day)
                            Button {
                                if selected { days.remove(day) } else { days.insert(day) }
                            } label: {
                                Text(weekdaySymbols[day - 1].prefix(1))
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(
                                        selected ? Theme.accent : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    Button("Every day") { days = Set(Habit.everyDay) }
                    Button("Weekdays only") { days = Set(Habit.weekdays) }
                }
            }
            .navigationTitle(name.isEmpty ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), emoji, days)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
