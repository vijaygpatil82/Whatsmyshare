import SwiftUI
import SwiftData

@main
struct WhatsMyShareApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Person.self,
            ExpenseGroup.self,
            Expense.self,
            ExpenseShare.self,
            Settlement.self
        ])
    }
}

/// Shows onboarding until the device owner has told us their name.
struct RootView: View {
    @Query(filter: #Predicate<Person> { $0.isMe == true }, sort: \Person.createdAt)
    private var me: [Person]

    var body: some View {
        if let me = me.first {
            GroupsListView(me: me)
        } else {
            OnboardingView()
        }
    }
}
