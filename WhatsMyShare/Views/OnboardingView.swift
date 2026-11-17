import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("What's My Share")
                    .font(.largeTitle.bold())
                Text("Split bills with friends and family.\nNo bank accounts. No sign-up. Your data stays on your phone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?")
                    .font(.headline)
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(start)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 16)
            Spacer()
            Button(action: start) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedName.isEmpty)
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start() {
        guard !trimmedName.isEmpty else { return }
        context.insert(Person(name: trimmedName, isMe: true))
        try? context.save()
    }
}
