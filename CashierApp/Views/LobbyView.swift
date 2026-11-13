import SwiftUI

private struct SampleEvent: Identifiable {
    let id = UUID()
    let league: String
    let matchup: String
    let odds: [String]
}

private let sampleEvents: [SampleEvent] = [
    .init(league: "NFL", matchup: "Eagles @ Cowboys", odds: ["-135", "+3.5", "O 47.5"]),
    .init(league: "NBA", matchup: "76ers @ Celtics", odds: ["+210", "+6.5", "O 221.5"]),
    .init(league: "NHL", matchup: "Flyers @ Penguins", odds: ["+115", "+1.5", "O 6.0"]),
    .init(league: "MLB", matchup: "Phillies @ Mets", odds: ["-120", "-1.5", "O 8.5"]),
]

/// Sportsbook-style lobby. Only here to give the cashier a believable host app.
struct LobbyView: View {
    @Environment(WalletStore.self) private var wallet
    @State private var showCashier = false

    var body: some View {
        NavigationStack {
            List(sampleEvents) { event in
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.league).font(.caption).foregroundStyle(.secondary)
                    Text(event.matchup).font(.headline)
                    HStack {
                        ForEach(event.odds, id: \.self) { price in
                            Text(price)
                                .font(.subheadline.monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Sportsbook")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCashier = true
                    } label: {
                        // HStack rather than Label: toolbar items render Labels icon-only.
                        HStack(spacing: 6) {
                            Text(wallet.balance.formatted(.currency(code: "USD")))
                            Image(systemName: "plus.circle.fill")
                        }
                        .font(.subheadline.bold())
                    }
                }
            }
            .sheet(isPresented: $showCashier) {
                CashierView()
            }
        }
    }
}
