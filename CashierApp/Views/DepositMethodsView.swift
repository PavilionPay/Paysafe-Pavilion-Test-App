import SwiftUI

/// The operator's own cashier: every deposit method the operator offers, laid out like a typical
/// sportsbook cashier. Only eCheck/ACH (VIP Preferred) is wired up in this sample; it opens Paysafe
/// Checkout. In a real app the other tiles would open their own flows.
enum DepositMethod: String, CaseIterable, Identifiable {
    case paypal, debitCard, playPlus, cage, vipACH, applePay, checkByMail, bankWire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paypal: "PayPal"
        case .debitCard: "Debit Card"
        case .playPlus: "Play+ Prepaid"
        case .cage: "Cage"
        case .vipACH: "eCheck/ACH - Bank Account"
        case .applePay: "Apple Pay"
        case .checkByMail: "Check By Mail"
        case .bankWire: "Bank Wire"
        }
    }

    /// The only method this sample implements.
    var isActive: Bool { self == .vipACH }

    @ViewBuilder var icon: some View {
        switch self {
        case .vipACH:
            VIPACHLogo()
        default:
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var symbol: String {
        switch self {
        case .paypal: "p.circle.fill"
        case .debitCard: "creditcard.fill"
        case .playPlus: "plus.rectangle.fill"
        case .cage: "circle.hexagongrid.circle.fill"
        case .applePay: "wallet.pass.fill"
        case .checkByMail: "envelope.fill"
        case .bankWire: "building.columns.fill"
        case .vipACH: ""
        }
    }

    private var tint: Color {
        switch self {
        case .paypal: Color(red: 0.0, green: 0.19, blue: 0.53)
        case .debitCard, .checkByMail: .orange
        case .playPlus, .applePay: .black
        case .cage: Color(red: 0.85, green: 0.2, blue: 0.4)
        case .bankWire: Color(red: 0.9, green: 0.3, blue: 0.2)
        case .vipACH: .clear
        }
    }
}

/// Palette taken from the reference cashier: light page, pale tiles, slate section bar, navy buttons.
enum CashierStyle {
    static let page = Color.white
    static let tile = Color(white: 0.965)
    static let sectionBar = Color(red: 0.29, green: 0.31, blue: 0.39)
    static let text = Color(white: 0.2)
    static let navy = Color(red: 0.09, green: 0.1, blue: 0.24)
    static let vipNavy = Color(red: 0.07, green: 0.2, blue: 0.42)
}

struct DepositMethodsView: View {
    var onSelectVIP: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionBar(title: "Deposit")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DepositMethod.allCases) { method in
                        if method.isActive {
                            Button(action: onSelectVIP) { MethodTile(method: method) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("method.\(method.rawValue)")
                        } else {
                            // Same look as the real cashier, but not part of this sample.
                            MethodTile(method: method)
                                .accessibilityHint("Not implemented in this sample")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(CashierStyle.page)
    }
}

struct SectionBar: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CashierStyle.sectionBar)
    }
}

private struct MethodTile: View {
    let method: DepositMethod

    var body: some View {
        VStack(spacing: 12) {
            method.icon.frame(height: 40)
            Text(method.title)
                .font(.system(size: 16))
                .foregroundStyle(CashierStyle.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(CashierStyle.tile)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

/// Simple drawing of the VIP ACH mark: "vip" in a navy circle, then "ACH" over "bank transfer".
struct VIPACHLogo: View {
    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Circle().fill(CashierStyle.vipNavy).frame(width: 34, height: 34)
                    .overlay(Text("vip").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: -2, y: 1)
            }
            VStack(alignment: .leading, spacing: -2) {
                Text("ACH").font(.system(size: 22, weight: .heavy)).foregroundStyle(CashierStyle.vipNavy)
                Text("bank transfer").font(.system(size: 6, weight: .semibold)).foregroundStyle(CashierStyle.vipNavy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VIP ACH")
    }
}
