import Foundation

/// A test patron entered in the app, sent to the cashier server for one session.
/// The SSN becomes VIP Preferred `consumerId`, which Paysafe passes to Pavilion as the patron's SSN.
/// TEST only: use synthetic identities, never a real person's SSN.
struct Patron: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        /// Already enrolled in VIP Preferred (test environment): only the SSN is needed; the server fills placeholder contact details.
        case existing
        /// Not enrolled yet: the details entered here are who gets onboarded.
        case new
        var id: String { rawValue }
        var title: String { self == .existing ? "Existing" : "New" }
    }

    var kind: Kind = .existing
    var firstName = ""
    var lastName = ""
    var ssn = ""            // 9 digits, no dashes
    var dateOfBirth = Calendar.current.date(from: DateComponents(year: 1985, month: 1, day: 15)) ?? .now
    var phone = ""          // 10 digits
    var email = ""
    var street = ""
    var city = ""
    var state = ""          // 2-letter code
    var zip = ""            // 5 digits

    static func digits(_ value: String) -> String { value.filter(\.isNumber) }
    private static func blank(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Human-readable problems, empty when the patron can be sent.
    var problems: [String] {
        var issues: [String] = []
        if Self.digits(ssn).count != 9 { issues.append("SSN must be 9 digits.") }
        guard kind == .new else { return issues }
        if Self.blank(firstName) { issues.append("First name is required.") }
        if Self.blank(lastName) { issues.append("Last name is required.") }
        if Self.digits(phone).count != 10 { issues.append("Phone must be 10 digits.") }
        if !email.contains("@") { issues.append("Email looks incomplete.") }
        if Self.blank(street) { issues.append("Street is required.") }
        if Self.blank(city) { issues.append("City is required.") }
        if state.trimmingCharacters(in: .whitespaces).count != 2 { issues.append("State must be a 2-letter code.") }
        if Self.digits(zip).count != 5 { issues.append("ZIP must be 5 digits.") }
        return issues
    }

    var maskedSSN: String { "•••-••-" + String(Self.digits(ssn).suffix(4)) }
    var displayName: String {
        kind == .existing ? "Existing patron" : "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    /// Shape the cashier server expects in POST /api/cashier/session.
    var payload: [String: Any] {
        guard kind == .new else { return ["kind": kind.rawValue, "ssn": Self.digits(ssn)] }
        let dob = Calendar.current.dateComponents([.year, .month, .day], from: dateOfBirth)
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespaces) }
        return [
            "kind": kind.rawValue,
            "ssn": Self.digits(ssn),
            "firstName": trim(firstName),
            "lastName": trim(lastName),
            "email": trim(email),
            "phone": Self.digits(phone),
            "dateOfBirth": ["year": dob.year ?? 0, "month": dob.month ?? 0, "day": dob.day ?? 0],
            "street": trim(street),
            "city": trim(city),
            "state": trim(state).uppercased(),
            "zip": Self.digits(zip),
        ]
    }
}
