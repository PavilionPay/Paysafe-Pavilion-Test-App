import SwiftUI

/// The operator's cashier. The patron picks a deposit method from the operator's own grid; only
/// eCheck/ACH (VIP Preferred) is implemented here, and it opens Paysafe Checkout for that one method.
struct CashierView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showVIPDeposit = false

    var body: some View {
        NavigationStack {
            DepositMethodsView { showVIPDeposit = true }
                .navigationTitle("Deposit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                }
                .navigationDestination(isPresented: $showVIPDeposit) { VIPDepositView() }
        }
        // The cashier pages are light, like a typical operator cashier, inside the dark app.
        .environment(\.colorScheme, .light)
    }
}

/// eCheck/ACH amount page. "Deposit" opens Paysafe Checkout with VIP Preferred as the only method.
struct VIPDepositView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss

    /// Demo mode needs no keys or backend; the default path uses server/server.py and your TEST keys.
    @AppStorage("usePaysafeDemo") private var usePaysafeDemo = false
    @State private var amount: Decimal = 15
    @State private var isLaunching = false
    @State private var launcher = CheckoutLauncher()
    @State private var editingPatron = false

    private let presets: [Decimal] = [15, 20, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionBar(title: "Deposit")

                Button { dismiss() } label: {
                    Label(DepositMethod.vipACH.title, systemImage: "chevron.left")
                        .font(.system(size: 15))
                        .foregroundStyle(CashierStyle.text)
                }
                .padding(16)

                VStack(alignment: .leading, spacing: 16) {
                    amountField
                    presetButtons
                    depositButton
                    if let outcome = wallet.lastOutcome { OutcomeBanner(outcome: outcome) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                SectionBar(title: "Sample settings")
                sampleSettings.padding(16)
            }
        }
        .background(CashierStyle.page)
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $editingPatron) {
            PatronFormView(patron: wallet.patron) { wallet.patron = $0 }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("Amount") + Text("*").foregroundColor(.red))
                .font(.system(size: 13))
                .foregroundStyle(CashierStyle.text)
            TextField("", value: $amount, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .foregroundStyle(CashierStyle.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(Capsule().stroke(Color(white: 0.75)))
                .accessibilityIdentifier("deposit.amount")
        }
    }

    private var presetButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            ForEach(presets, id: \.self) { preset in
                let selected = amount == preset
                Button(preset.formatted(.currency(code: "USD").precision(.fractionLength(0)))) { amount = preset }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .foregroundStyle(selected ? .white : CashierStyle.text)
                    .background(selected ? CashierStyle.navy : .clear, in: Capsule())
                    .overlay(Capsule().stroke(CashierStyle.navy))
            }
            Spacer()
        }
    }

    private var depositButton: some View {
        Button {
            Task { await startCheckout() }
        } label: {
            Group {
                if isLaunching { ProgressView().tint(.white) } else { Text("DEPOSIT").font(.system(size: 14, weight: .bold)) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(CashierStyle.navy.opacity(isLaunching || amount <= 0 ? 0.5 : 1), in: Capsule())
        }
        .disabled(isLaunching || amount <= 0)
        .accessibilityIdentifier("deposit.submit")
    }

    /// Test-only controls that a real cashier wouldn't have.
    private var sampleSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !usePaysafeDemo {
                Text("Patron").font(.system(size: 13, weight: .semibold)).foregroundStyle(CashierStyle.text)
                if let patron = wallet.patron {
                    LabeledContent(patron.displayName, value: patron.maskedSSN).foregroundStyle(CashierStyle.text)
                    HStack {
                        Button("Change patron") { editingPatron = true }
                        Spacer()
                        Button("Use default test patron", role: .destructive) { wallet.patron = nil }
                    }
                } else {
                    LabeledContent("Default test patron", value: "from server .env").foregroundStyle(CashierStyle.text)
                    Button("Existing or new patron…") { editingPatron = true }
                }
                Text("Pavilion finds the VIP account by SSN. Use Existing for an enrolled SSN, New to onboard one that isn't.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Use Paysafe demo store", isOn: $usePaysafeDemo).foregroundStyle(CashierStyle.text)
            if usePaysafeDemo {
                Text("Opens Paysafe's public demo. Pick Deposit → VIP Preferred → Add Bank Account → Online Banking, then tap Cancel to return. The amount above isn't used.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
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
