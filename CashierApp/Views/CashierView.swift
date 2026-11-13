import SwiftUI

struct CashierView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss

    /// Demo mode needs no keys or backend; the default path uses server/server.py and your TEST keys.
    @AppStorage("usePaysafeDemo") private var usePaysafeDemo = false
    @State private var amount: Decimal = 25
    @State private var isLaunching = false
    @State private var launcher = CheckoutLauncher()
    @State private var editingPatron = false

    private let presets: [Decimal] = [15, 25, 50, 100]

    var body: some View {
        NavigationStack {
            Form {
                Section("Balance") {
                    Text(wallet.balance.formatted(.currency(code: "USD"))).font(.title2.bold())
                }

                Section("Deposit amount") {
                    HStack {
                        ForEach(presets, id: \.self) { preset in
                            Button(preset.formatted(.currency(code: "USD").precision(.fractionLength(0)))) {
                                amount = preset
                            }
                            .buttonStyle(.bordered)
                            .tint(amount == preset ? .accentColor : .gray)
                        }
                    }
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                }

                if !usePaysafeDemo {
                    Section {
                        if let patron = wallet.patron {
                            LabeledContent(patron.displayName, value: patron.maskedSSN)
                            Button("Change patron") { editingPatron = true }
                            Button("Use default test patron", role: .destructive) { wallet.patron = nil }
                        } else {
                            LabeledContent("Default test patron", value: "from server .env")
                            Button("Existing or new patron…") { editingPatron = true }
                        }
                    } header: {
                        Text("Patron")
                    } footer: {
                        Text("Pavilion finds the VIP account by SSN. Use Existing for an enrolled SSN, New to onboard one that isn't.")
                    }
                }

                Section {
                    Label("VIP Preferred (ACH)", systemImage: "building.columns")
                    Toggle("Use Paysafe demo store", isOn: $usePaysafeDemo)
                } header: {
                    Text("Payment method")
                } footer: {
                    if usePaysafeDemo {
                        Text("Opens Paysafe's public demo. Pick Deposit → VIP Preferred → Add Bank Account → Online Banking, then tap Cancel to return. The amount above isn't used.")
                    }
                }

                if let outcome = wallet.lastOutcome {
                    Section { OutcomeBanner(outcome: outcome) }
                }

                Section {
                    Button {
                        Task { await startCheckout() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLaunching { ProgressView() } else { Text("Continue to Paysafe").bold() }
                            Spacer()
                        }
                    }
                    .disabled(isLaunching || amount <= 0)
                }
            }
            .navigationTitle("Cashier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $editingPatron) {
                PatronFormView(patron: wallet.patron) { wallet.patron = $0 }
            }
        }
    }

    private func startCheckout() async {
        isLaunching = true
        defer { isLaunching = false }
        do {
            let outcome: CheckoutOutcome
            if usePaysafeDemo {
                outcome = try await launcher.launchDemo()
            } else {
                let sessionId = try await wallet.createCashierSession(amount: amount)
                outcome = try await launcher.launch(sessionId: sessionId)
            }
            await wallet.apply(outcome: outcome)
        } catch {
            await wallet.apply(outcome: .failed(error.localizedDescription))
        }
    }
}

private struct OutcomeBanner: View {
    let outcome: CheckoutOutcome

    var body: some View {
        switch outcome {
        case .success(let reference):
            Label("Deposit received" + (reference.map { " (\($0))" } ?? ""), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .cancelled:
            Label("Deposit cancelled", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .demoClosed:
            Label("Paysafe demo closed. The demo doesn't report results to the app.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
