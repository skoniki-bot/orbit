import SwiftUI
import SwiftData

@main
struct OrbitApp: App {

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
        .modelContainer(for: [Habit.self, Completion.self,
                              GroceryList.self, GroceryItem.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var habits: [Habit]

    /// Bumped when the app returns to the foreground so "today" re-evaluates
    /// if the app was left open across midnight.
    @State private var dayToken = DayKey.today

    /// State lives here rather than in SplashView, so it survives
    /// backgrounding — the splash plays once per cold launch, not every
    /// time you switch back to the app.
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                TodayView()
                    .id(dayToken)
                    .tabItem { Label("Today", systemImage: "circle.dotted.circle") }

                GroceryView()
                    .tabItem { Label("Grocery", systemImage: "basket") }

                RoutineView()
                    .tabItem { Label("Routine", systemImage: "list.bullet.indent") }
            }
            .onAppear(perform: seedIfEmpty)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { dayToken = DayKey.today }
            }

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func seedIfEmpty() {
        guard habits.isEmpty else { return }
        for habit in Habit.starterSet {
            context.insert(habit)
        }
    }
}

enum Theme {
    /// Deep indigo — night-sky, not system blue.
    static let accent = Color(red: 0.24, green: 0.26, blue: 0.55)
    /// Warm amber for streaks and quantities.
    static let streak = Color(red: 0.83, green: 0.55, blue: 0.16)
    /// Matches the launch screen background so there's no flash on start.
    static let launchBackground = Color(red: 0.172, green: 0.188, blue: 0.416)
}
