import SwiftUI
import Contacts
import ContactsUI

/// A person chosen from the iOS Contacts picker.
struct PickedContact: Hashable {
    var identifier: String
    var name: String
    var detail: String?
}

/// Presents Apple's system contact picker. The picker runs outside the app,
/// so no Contacts permission prompt is needed and the app only ever sees the
/// people the user actually taps.
///
/// Usage: `.background(ContactPicker(isPresented: $show) { contacts in … })`
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: ([PickedContact]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil, !context.coordinator.isShowing else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        context.coordinator.isShowing = true
        // Present on the next run loop so we're never mid-update.
        DispatchQueue.main.async {
            host.present(picker, animated: true)
        }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        var isShowing = false

        init(parent: ContactPicker) { self.parent = parent }

        // Implementing the plural variant enables multi-select in the picker.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let picked = contacts.compactMap(Self.makePicked)
            finish()
            parent.onPick(picked)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finish()
        }

        private func finish() {
            isShowing = false
            DispatchQueue.main.async { [parent] in
                parent.isPresented = false
            }
        }

        private static func makePicked(_ contact: CNContact) -> PickedContact? {
            var name = ""
            let nameKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            if contact.areKeysAvailable([nameKeys]) {
                name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            }
            if name.isEmpty, contact.isKeyAvailable(CNContactOrganizationNameKey) {
                name = contact.organizationName
            }

            var detail: String?
            if contact.isKeyAvailable(CNContactPhoneNumbersKey),
               let phone = contact.phoneNumbers.first?.value.stringValue {
                detail = phone
            } else if contact.isKeyAvailable(CNContactEmailAddressesKey),
                      let email = contact.emailAddresses.first?.value {
                detail = email as String
            }

            if name.isEmpty { name = detail ?? "" }
            guard !name.isEmpty else { return nil }
            return PickedContact(identifier: contact.identifier, name: name, detail: detail)
        }
    }
}
