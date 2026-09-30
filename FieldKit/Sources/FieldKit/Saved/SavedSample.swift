import Foundation

extension Saved {
    /// A made-up library of exactly `count` pages: a handful of folders, a
    /// dozen stars, most never opened again. The same every time, for the
    /// app's `-FieldSeedSaved` in the perf tests and the harness.
    public static func sample(_ count: Int, now: Date) -> Saved {
        var saved = Saved()
        var dice = Dice(seed: 404)
        let folders = ["Recipes", "Work", "Trips", "Reading", "Design"]
        let sites = [
            "www.seriouseats.com", "github.com", "developer.apple.com", "en.wikipedia.org",
            "www.nytimes.com", "www.lonelyplanet.com", "news.ycombinator.com", "www.figma.com",
            "forums.swift.org", "www.theatlantic.com", "www.bbcgoodfood.com", "arstechnica.com",
        ]
        let subjects = ["Pasta", "Concurrency", "Lisbon", "Typography", "Sourdough", "Layout",
                        "Kyoto", "Actors", "Colour", "Soup", "Porto", "Grids", "Coffee", "Memory"]
        let kinds = ["A guide to", "Notes on", "The trouble with", "Ten things about", "Why", "How to think about"]

        var i = 0
        while saved.pages.count < count {
            let subject = subjects[dice.roll(subjects.count)]
            let site = sites[dice.roll(sites.count)]
            let url = URL(string: "https://\(site)/\(subject.lowercased())/\(i)")!
            let when = now.addingTimeInterval(-Double(count - i) * 3_600 * 7)
            let folder = dice.roll(3) == 0 ? nil : folders[dice.roll(folders.count)]
            let starred = saved.starred.count < 12 && dice.roll(20) == 0
            saved.save(url, title: "\(kinds[dice.roll(kinds.count)]) \(subject.lowercased())", folder: folder,
                       starred: starred, now: when)
            if dice.roll(3) == 0 { saved.opened(url, now: when.addingTimeInterval(3_600)) }
            i += 1
        }
        return saved
    }
}
