import UIKit

extension ContentBlocking {
    /// The per-site switch, as an item for the address's long-press menu:
    /// "Turn Off Blocking on example.com", or back on. It flips the shield
    /// for the whole site, then `reload`s so the page shows the change. Nil
    /// for a page with no site: a blank tab, `about:` or `data:`.
    func shieldAction(for page: URL?, reload: @escaping () -> Void) -> UIAction? {
        guard let host = page?.host(), !host.isEmpty else { return nil }
        let on = isShieldOn(for: host)
        let title = "Turn \(on ? "Off" : "On") Blocking on \(site(host))"
        return UIAction(title: title, image: UIImage(systemName: on ? "shield.slash" : "shield")) { [weak self] _ in
            self?.setShield(!on, for: host)
            reload()
        }
    }
}
