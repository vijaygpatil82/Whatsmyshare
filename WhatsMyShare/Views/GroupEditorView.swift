import SwiftUI
import SwiftData

/// Create a new group, or edit an existing one's name, currency and members.
struct GroupEditorView: View {
    /// nil when creating a new group.
    let group: ExpenseGroup?
    let me: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var name = ""
    @State private var emoji = "👥"
    @State private var currencyCode = Money.defaultCurrencyCode
    @State private var members: [DraftMember] = []
    @State private var loaded = false

    @State private var showingContacts = false
    @State private var showingAddByName = false
    @State private var newPersonName = ""
    @State private var blockedRemoval: String?

    private static let emojiChoices = ["👥", "🏠", "✈️", "🏖️", "🍕", "🎉", "👨‍👩‍👧‍👦", "🏕️", "🚗", "💼", "🎓", "⚽️"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name (e.g. Goa Trip, Flatmates)", text: $name)
                        .textInputAutocapitalization(.words)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.emojiChoices, id: \.self) { choice in
                                Button {
                                    emoji = choice
                                } label: {
                                    Text(choice)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            emoji == choice ? Color.accentColor.opacity(0.25) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Icon \(choice)")
                            }
                        }
                    }
                }

                Section {
                    if hasExpenses {
                        LabeledContent("Currency", value: "\(currencyCode) – \(Money.currencyName(currencyCode))")
                    } else {
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(Money.allCurrencyCodes, id: \.self) { code in
                                Text("\(code) – \(Money.currencyName(code))").tag(code)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } footer: {
                    if hasExpenses {
                        Text("The currency can't be changed once a group has expenses.")
                    }
                }

                Section("People") {
                    ForEach(members) { member in
                        PersonRow(name: member.name, detail: member.detail, isMe: member.isMe)
                            .deleteDisabled(member.isMe)
                    }
                    .onDelete(perform: removeMembers)

                    Button {
                        showingContacts = true
                    } label: {
                        Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        newPersonName = ""
                        showingAddByName = true
                    } label: {
                        Label("Add by name", systemImage: "character.cursor.ibeam")
                    }
                }

                if !knownPeopleNotInGroup.isEmpty {
                    Section {
                        ForEach(knownPeopleNotInGroup) { person in
                            Button {
                                members.append(DraftMember(existing: person))
                            } label: {
                                HStack {
                                    PersonRow(name: person.name, detail: person.detail)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("From your other groups")
                    }
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .background(
                ContactPicker(isPresented: $showingContacts) { picked in
                    addContacts(picked)
                }
            )
            .alert("Add someone", isPresented: $showingAddByName) {
                TextField("Name", text: $newPersonName)
                    .textInputAutocapitalization(.words)
                Button("Add") { addByName() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("For people who aren't in your contacts.")
            }
            .alert(
                "Can't remove \(blockedRemoval ?? "")",
                isPresented: Binding(get: { blockedRemoval != nil }, set: { if !$0 { blockedRemoval = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("They're part of expenses or payments in this group. Delete or edit those first.")
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Derived

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExpenses: Bool {
        !(group?.expenses ?? []).isEmpty || !(group?.settlements ?? []).isEmpty
    }

    private var knownPeopleNotInGroup: [Person] {
        let inGroup = Set(members.compactMap { $0.existing?.id })
        return allPeople.filter { !$0.isMe && !inGroup.contains($0.id) }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let group {
            name = group.name
            emoji = group.emoji
            currencyCode = group.currencyCode
            members = group.sortedMembers.map { DraftMember(existing: $0) }
            if !members.contains(where: { $0.isMe }) {
                members.insert(DraftMember(existing: me), at: 0)
            }
        } else {
            members = [DraftMember(existing: me)]
        }
    }

    private func removeMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = members[index]
            if let person = member.existing, let group, group.hasActivity(for: person) {
                blockedRemoval = person.name
                return
            }
        }
        members.remove(atOffsets: offsets)
    }

    private func addContacts(_ picked: [PickedContact]) {
        for contact in picked {
            let alreadyAdded = members.contains {
                $0.contactIdentifier == contact.identifier || $0.existing?.contactIdentifier == contact.identifier
            }
            guard !alreadyAdded else { continue }
            if let known = allPeople.first(where: { $0.contactIdentifier == contact.identifier }) {
                members.append(DraftMember(existing: known))
            } else {
                members.append(DraftMember(name: contact.name, detail: contact.detail, contactIdentifier: contact.identifier))
            }
        }
    }

    private func addByName() {
        let trimmed = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        members.append(DraftMember(name: trimmed, detail: nil, contactIdentifier: nil))
        newPersonName = ""
    }

    private func save() {
        let target: ExpenseGroup
        if let group {
            target = group
        } else {
            target = ExpenseGroup(name: trimmedName, emoji: emoji, currencyCode: currencyCode)
            context.insert(target)
        }
        target.name = trimmedName
        target.emoji = emoji
        if !hasExpenses {
            target.currencyCode = currencyCode
        }

        var people: [Person] = []
        for member in members {
            if let existing = member.existing {
                people.append(existing)
            } else {
                let person = Person(name: member.name, contactIdentifier: member.contactIdentifier, detail: member.detail)
                context.insert(person)
                people.append(person)
            }
        }
        target.members = people
        try? context.save()
        dismiss()
    }
}

/// A member as being edited — either an existing Person or someone new that
/// is only created when the user taps Save.
struct DraftMember: Identifiable {
    var id: UUID
    var name: String
    var detail: String?
    var contactIdentifier: String?
    var existing: Person?

    var isMe: Bool { existing?.isMe ?? false }

    init(existing: Person) {
        self.id = existing.id
        self.name = existing.name
        self.detail = existing.detail
        self.contactIdentifier = existing.contactIdentifier
        self.existing = existing
    }

    init(name: String, detail: String?, contactIdentifier: String?) {
        self.id = UUID()
        self.name = name
        self.detail = detail
        self.contactIdentifier = contactIdentifier
        self.existing = nil
    }
}

/// Avatar with initials + name + optional subtitle.
struct PersonRow: View {
    let name: String
    var detail: String?
    var isMe: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: name)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                    if isMe {
                        Text("(you)").foregroundStyle(.secondary)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var color: Color {
        let palette: [Color] = [.blue, .teal, .indigo, .orange, .pink, .purple, .green, .brown, .cyan, .mint]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}
