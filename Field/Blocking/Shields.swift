import Foundation

/// The sites the blocker is off for: the ones it broke. Kept in UserDefaults
/// "shield.off" by site (registrable domain), so switching it off on one page
/// of a shop covers its checkout on another subdomain too.
struct Shields {
    static let key = "shield.off"

    private let defaults: UserDefaults
    /// Gives a host's site. The default is a small stand-in; the guard's
    /// public-suffix lookup takes its place once loaded (see INTEGRATION.md).
    var domain: (String) -> String
    private(set) var off: Set<String>
    init(defaults: UserDefaults = .standard, domain: @escaping (String) -> String = Shields.registrableDomain) {
        self.defaults = defaults
        self.domain = domain
        off = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func isOn(for host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        return !off.contains(site(host))
    }

    mutating func set(_ on: Bool, for host: String) {
        let site = site(host)
        if on { off.remove(site) } else { off.insert(site) }
        defaults.set(off.sorted(), forKey: Self.key)
    }

    private func site(_ host: String) -> String {
        domain(Self.normalized(host))
    }

    private nonisolated static func normalized(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    /// The last two labels, or three under a country's own second level
    /// (bbc.co.uk, abc.net.au). Addresses and single names stay whole.
    /// Close enough for a switch, not for cookies.
    nonisolated static func registrableDomain(_ host: String) -> String {
        let host = normalized(host)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 2, !host.contains(":"), !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            return host
        }
        let country = labels[labels.count - 1].count == 2
        let keep = country && secondLevels.contains(String(labels[labels.count - 2])) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    private nonisolated static let secondLevels: Set<String> = [
        "ac", "co", "com", "edu", "go", "gob", "gov", "gv", "ltd", "mil", "ne", "net", "nic", "or", "org", "plc", "sch",
    ]
}
