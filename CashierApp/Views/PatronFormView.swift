import SwiftUI

/// Choose an existing patron (SSN only) or enter a new one. Values stay in memory for this app run only.
struct PatronFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Patron
    @State private var showProblems = false
    let onSave: (Patron) -> Void

    init(patron: Patron?, onSave: @escaping (Patron) -> Void) {
        _draft = State(initialValue: patron ?? Patron())
        self.onSave = onSave
    }

    private func focusNone() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Patron", selection: $draft.kind) {
                        ForEach(Patron.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(draft.kind == .existing
                         ? "Looks up a patron already enrolled in VIP Preferred. Only the SSN is sent; contact details come from the server's test defaults."
                         : "Onboards a patron who isn't enrolled yet. These details are what Paysafe and Pavilion receive.")
                }

                if draft.kind == .new {
                    Section("Name") {
                        TextField("First name", text: $draft.firstName).accessibilityIdentifier("patron.firstName").textContentType(.givenName)
                        TextField("Last name", text: $draft.lastName).accessibilityIdentifier("patron.lastName").textContentType(.familyName)
                    }
                }

                Section {
                    SecureField("SSN (9 digits)", text: $draft.ssn).accessibilityIdentifier("patron.ssn").keyboardType(.numberPad)
                    if draft.kind == .new {
                        DatePicker("Date of birth", selection: $draft.dateOfBirth, in: ...Date.now, displayedComponents: .date)
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Sent to Paysafe as the VIP Preferred consumer ID; Pavilion looks the patron up by it. Use a synthetic TEST SSN only.")
                }

                if draft.kind == .new {
                    Section("Contact") {
                        TextField("Phone (10 digits)", text: $draft.phone).accessibilityIdentifier("patron.phone").keyboardType(.phonePad)
                        TextField("Email", text: $draft.email).accessibilityIdentifier("patron.email")
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("Billing address (US)") {
                        TextField("Street", text: $draft.street).accessibilityIdentifier("patron.street")
                        TextField("City", text: $draft.city).accessibilityIdentifier("patron.city")
                        HStack {
                            TextField("State", text: $draft.state).accessibilityIdentifier("patron.state").textInputAutocapitalization(.characters).frame(maxWidth: 80)
                            TextField("ZIP", text: $draft.zip).accessibilityIdentifier("patron.zip").keyboardType(.numberPad)
                        }
                    }
                }

                if showProblems, !draft.problems.isEmpty {
                    Section {
                        ForEach(draft.problems, id: \.self) { Text($0).foregroundStyle(.red) }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Patron")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusNone() }.accessibilityIdentifier("patron.keyboardDone")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use patron") {
                        if draft.problems.isEmpty {
                            onSave(draft)
                            dismiss()
                        } else {
                            showProblems = true
                        }
                    }
                }
            }
        }
        // Entered details would be lost by an accidental swipe-down.
        .interactiveDismissDisabled()
    }
}
