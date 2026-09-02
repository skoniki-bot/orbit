import SwiftUI
import SwiftData

struct GroceryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \GroceryList.createdAt) private var allLists: [GroceryList]
    @Query private var allItems: [GroceryItem]

    @State private var draft = ""
    @State private var store: GroceryStore = .indian
    @State private var showHistory = false
    @FocusState private var fieldFocused: Bool

    private var activeList: GroceryList? {
        allLists.first { $0.savedAt == nil }
    }

    private var items: [GroceryItem] {
        activeList?.sortedItems ?? []
    }

    private func items(in store: GroceryStore) -> [GroceryItem] {
        items.filter { $0.store == store.rawValue }
    }

    private var checkedCount: Int {
        items.filter(\.isChecked).count
    }

    // MARK: - Suggestions from what you've actually bought
    //
    // Scoped to the store you're adding to, since what you buy at the Indian
    // grocery and at Kroger barely overlap.

    private var suggestions: [String] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 3 else { return [] }

        let alreadyHere = Set(items(in: store).map { $0.name.lowercased() })

        var seen: [String: (count: Int, last: Date, display: String)] = [:]
        for item in allItems where item.store == store.rawValue {
            let key = item.name.lowercased()
            guard key.contains(query), !alreadyHere.contains(key) else { continue }
            if var entry = seen[key] {
                entry.count += 1
                if item.addedAt > entry.last {
                    entry.last = item.addedAt
                    entry.display = item.name
                }
                seen[key] = entry
            } else {
                seen[key] = (1, item.addedAt, item.name)
            }
        }

        return seen.values
            .sorted { ($0.count, $0.last) > ($1.count, $1.last) }
            .prefix(6)
            .map(\.display)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composer

                if !suggestions.isEmpty {
                    suggestionStrip
                }

                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing on the list",
                        systemImage: "basket",
                        description: Text("Pick a store, then add items. Save the list when you're done shopping and it's kept with today's date.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(GroceryStore.allCases) { section in
                            let group = items(in: section)
                            if !group.isEmpty {
                                Section {
                                    ForEach(group) { item in
                                        GroceryRow(item: item) {
                                            move(item, to: section == .indian ? .american : .indian)
                                        }
                                    }
                                    .onDelete { offsets in
                                        for index in offsets {
                                            context.delete(group[index])
                                        }
                                    }
                                } header: {
                                    Label(section.title, systemImage: section.symbol)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Grocery")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save list with today's date", systemImage: "tray.and.arrow.down") {
                            saveList()
                        }
                        .disabled(items.isEmpty)

                        if checkedCount > 0 {
                            Button("Remove \(checkedCount) checked", systemImage: "checkmark.circle") {
                                withAnimation { clearChecked() }
                            }
                        }

                        Divider()

                        Button("Past lists", systemImage: "clock.arrow.circlepath") {
                            showHistory = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                GroceryHistoryView()
            }
            .onAppear(perform: prepare)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 10) {
            Picker("Store", selection: $store) {
                ForEach(GroceryStore.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                TextField("Add to \(store.title.lowercased())", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { add(draft) }

                Button {
                    add(draft)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        add(name)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                            Text(name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    // MARK: - Actions

    /// Makes sure there's always exactly one open list, and adopts any items
    /// left orphaned by an earlier version of the data model.
    private func prepare() {
        if activeList == nil {
            context.insert(GroceryList())
        }
        guard let list = allLists.first(where: { $0.savedAt == nil }) else { return }
        for item in allItems where item.list == nil {
            item.list = list
        }
    }

    private func add(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if activeList == nil { context.insert(GroceryList()) }
        guard let list = activeList else { return }

        // Same thing twice in the same store just bumps the count.
        if let existing = items(in: store).first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            withAnimation(.snappy) { existing.quantity += 1 }
        } else {
            context.insert(GroceryItem(name: name, store: store, list: list))
        }

        draft = ""
        fieldFocused = true
    }

    private func move(_ item: GroceryItem, to destination: GroceryStore) {
        withAnimation(.snappy) { item.store = destination.rawValue }
    }

    private func clearChecked() {
        for item in items where item.isChecked {
            context.delete(item)
        }
    }

    private func saveList() {
        guard let list = activeList, !items.isEmpty else { return }
        list.savedAt = Date()
        context.insert(GroceryList())
        draft = ""
    }
}

// MARK: - Row

struct GroceryRow: View {
    let item: GroceryItem
    let moveToOtherStore: () -> Void

    private var otherStore: GroceryStore {
        GroceryStore.from(item.store) == .indian ? .american : .indian
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { item.isChecked.toggle() }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Theme.accent : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            Text(item.name)
                .foregroundStyle(item.isChecked ? .secondary : .primary)
                .strikethrough(item.isChecked, color: .secondary)

            Spacer(minLength: 8)

            stepper
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading) {
            Button {
                moveToOtherStore()
            } label: {
                Label("To \(otherStore.title)", systemImage: otherStore.symbol)
            }
            .tint(Theme.accent)
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus") {
                if item.quantity > 1 { item.quantity -= 1 }
            }
            .disabled(item.quantity <= 1)
            .opacity(item.quantity <= 1 ? 0.3 : 1)

            Text("\(item.quantity)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 22)
                .foregroundStyle(item.quantity > 1 ? Theme.streak : .primary)

            stepButton("plus") {
                item.quantity += 1
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { action() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }
}

// MARK: - History

struct GroceryHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryList.createdAt, order: .reverse) private var lists: [GroceryList]

    private var saved: [GroceryList] {
        lists.filter { $0.savedAt != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView(
                        "No saved lists yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Save a list after shopping and it'll show up here with its date.")
                    )
                } else {
                    List {
                        ForEach(saved) { list in
                            NavigationLink {
                                SavedListDetail(list: list)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.dateLabel)
                                    Text("\(list.itemCount) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(saved[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Past lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SavedListDetail: View {
    let list: GroceryList

    var body: some View {
        List {
            ForEach(GroceryStore.allCases) { store in
                let group = list.items(in: store)
                if !group.isEmpty {
                    Section {
                        ForEach(group) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                if item.quantity > 1 {
                                    Text("\(item.quantity)×")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Label(store.title, systemImage: store.symbol)
                    }
                }
            }
        }
        .navigationTitle(list.dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
