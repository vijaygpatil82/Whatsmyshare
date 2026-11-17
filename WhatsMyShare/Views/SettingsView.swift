import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var me: Person

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Your name", text: $me.name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    ForEach(people.filter { !$0.isMe }) { person in
                        PersonNameEditor(person: person)
                            .deleteDisabled(!(person.groups ?? []).isEmpty)
                    }
                    .onDelete(perform: deletePeople)
                } header: {
                    Text("People")
                } footer: {
                    Text("Rename anyone here. People can be deleted once they aren't in any group.")
                }

                Section("Privacy") {
                    Label("Everything you enter stays on this iPhone. No accounts, no bank connections, no tracking.", systemImage: "lock.shield")
                        .font(.subheadline)
                    Label("Contacts are only read when you pick someone, and only the people you pick.", systemImage: "person.crop.circle")
                        .font(.subheadline)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if me.name.trimmingCharacters(in: .whitespaces).isEmpty { me.name = "Me" }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func deletePeople(at offsets: IndexSet) {
        let others = people.filter { !$0.isMe }
        for index in offsets where (others[index].groups ?? []).isEmpty {
            context.delete(others[index])
        }
        try? context.save()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct PersonNameEditor: View {
    @Bindable var person: Person

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: person.name)
            TextField("Name", text: $person.name)
        }
    }
}
