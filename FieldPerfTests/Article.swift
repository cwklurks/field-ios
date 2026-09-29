import Foundation

/// A long-form article laid out like a real news site: a sticky header, a
/// drop cap, figures with captions, pull quotes, a table and footnotes.
/// About 60 screens tall on an iPhone, so a run of fast flings starting in
/// the middle never reaches either end (pull to reload would spoil it).
enum Article {
    static let headline = "The Hedgerow Ledger"

    static let html: String = {
        var body = ""
        for section in 0..<sections.count * 4 {
            body += "<h2>\(sections[section % sections.count])</h2>\n"
            for paragraph in 0..<5 {
                body += "<p>\(prose[(section * 5 + paragraph) % prose.count])</p>\n"
            }
            switch section % 4 {
            case 0: body += figure(section)
            case 1: body += "<blockquote>\(quotes[section % quotes.count])</blockquote>\n"
            case 2: body += list
            default: body += section % 8 == 3 ? table : figure(section)
            }
        }
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(headline) · The Weald Review</title>
        <style>\(style)</style></head>
        <body>
        <header><span class="mark">The Weald Review</span><nav>Land · Water · Towns · Letters</nav></header>
        <article>
        <p class="kicker">Countryside</p>
        <h1>\(headline)</h1>
        <p class="dek">What a mile of old hedge is worth, who pays to keep it, and why the answer changes with every season.</p>
        <p class="byline">By Ada Marlow · 14 minute read</p>
        \(figure(0))
        <div class="body">\(body)</div>
        <ol class="notes"><li>Figures are from parish surveys and are rounded.</li><li>Names of farms have been changed.</li></ol>
        </article>
        <footer>The Weald Review · A fixture page for Field's perf tests</footer>
        </body></html>
        """
    }()

    private static func figure(_ index: Int) -> String {
        """
        <figure><img src="/figure/\(index).svg" width="800" height="450" alt="">
        <figcaption>Plate \(index + 1). A laid hedge in its third winter, seen from the lane.</figcaption></figure>

        """
    }

    /// A small landscape, different for every index, so each figure rasterises on its own.
    static func svg(_ index: Int) -> String {
        let hue = (index * 47) % 360
        let sun = 120 + (index * 83) % 560
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450">
        <defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="hsl(\(hue),60%,78%)"/><stop offset="1" stop-color="hsl(\((hue + 40) % 360),70%,92%)"/>
        </linearGradient></defs>
        <rect width="800" height="450" fill="url(#s)"/>
        <circle cx="\(sun)" cy="110" r="46" fill="hsl(\((hue + 180) % 360),80%,70%)" opacity=".85"/>
        <path d="M0 300 C160 240 300 330 460 270 S720 250 800 290 V450 H0Z" fill="hsl(\((hue + 90) % 360),35%,45%)"/>
        <path d="M0 350 C140 320 330 390 520 340 S740 330 800 360 V450 H0Z" fill="hsl(\((hue + 110) % 360),40%,32%)"/>
        <path d="M0 400 C200 380 380 430 600 395 S760 390 800 405 V450 H0Z" fill="hsl(\((hue + 130) % 360),45%,22%)"/>
        </svg>
        """
    }

    private static let style = """
    :root{color-scheme:light dark;--ink:#1d1d1f;--muted:#6e6e73;--rule:#d2d2d7;--ground:#fbfbf8}
    @media (prefers-color-scheme:dark){:root{--ink:#f2f2f0;--muted:#a1a1a6;--rule:#3a3a3c;--ground:#161617}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--ground);color:var(--ink);font:18px/1.62 -apple-system,Georgia,serif;-webkit-text-size-adjust:100%}
    header{position:sticky;top:0;z-index:2;display:flex;justify-content:space-between;align-items:baseline;gap:12px;padding:10px 18px;background:color-mix(in srgb,var(--ground) 88%,transparent);-webkit-backdrop-filter:saturate(1.6) blur(14px);backdrop-filter:saturate(1.6) blur(14px);border-bottom:1px solid var(--rule)}
    .mark{font:700 17px/1 Georgia,serif;letter-spacing:.02em}
    nav{font:13px/1 -apple-system,sans-serif;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    article{max-width:40rem;margin:0 auto;padding:18px}
    .kicker{font:600 13px/1 -apple-system,sans-serif;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
    h1{font:700 2.1rem/1.1 Georgia,serif;margin:.3em 0}
    .dek{font-size:1.15rem;color:var(--muted)}
    .byline{font:14px -apple-system,sans-serif;color:var(--muted);border-top:1px solid var(--rule);padding-top:10px}
    .body>p:first-of-type::first-letter{float:left;font:700 3.6em/.8 Georgia,serif;margin:.08em .08em 0 0}
    h2{font:700 1.35rem/1.25 Georgia,serif;margin:1.8em 0 .5em}
    figure{margin:1.6em -18px}
    img{display:block;width:100%;height:auto;aspect-ratio:16/9;background:var(--rule)}
    figcaption{font:14px/1.4 -apple-system,sans-serif;color:var(--muted);padding:8px 18px 0}
    blockquote{margin:1.4em 0;padding:.2em 0 .2em 1em;border-left:3px solid var(--ink);font:italic 1.3rem/1.4 Georgia,serif}
    table{width:100%;border-collapse:collapse;font:15px/1.4 -apple-system,sans-serif;margin:1.4em 0}
    th,td{text-align:left;padding:8px 6px;border-bottom:1px solid var(--rule)}
    td:last-child,th:last-child{text-align:right;font-variant-numeric:tabular-nums}
    .notes{font:14px/1.5 -apple-system,sans-serif;color:var(--muted);border-top:1px solid var(--rule);padding-top:1em}
    footer{font:13px -apple-system,sans-serif;color:var(--muted);text-align:center;padding:40px 18px 80px}
    """

    private static let list = """
    <ul><li>Lay the hedge in late winter, before the sap rises.</li><li>Leave one standard tree every thirty paces.</li><li>Trim on a three-year rotation, never all at once.</li><li>Let the base thicken; it is where the wrens live.</li></ul>

    """

    private static let table = """
    <table><thead><tr><th>Parish</th><th>Miles of hedge</th><th>Cost per mile</th></tr></thead>
    <tbody><tr><td>Ashdown</td><td>41</td><td>£1,180</td></tr><tr><td>Bexley Green</td><td>27</td><td>£1,340</td></tr>
    <tr><td>Coldharbour</td><td>63</td><td>£990</td></tr><tr><td>Dunsfold</td><td>18</td><td>£1,520</td></tr></tbody></table>

    """

    private static let sections = [
        "A mile of thorn", "Who pays", "The layer's winter", "Birds keep the books",
        "The flail and the billhook", "Grants and their seasons", "What the maps forget",
        "Water in the ditch", "A parish argument", "The next forty years",
    ]

    private static let quotes = [
        "“A hedge is a slow machine. You set it going and your grandchildren read the output.”",
        "“Nobody ever thanked me for a hedge. They only notice when it's gone.”",
        "“The grant pays for the cutting. Nothing pays for the waiting.”",
    ]

    private static let prose = [
        "The hedge along Tanner's Lane is older than the church tower it frames. Its hawthorn stems are as thick as a wrist where the layer cut them, bent them and pinned them down in the winter of the great frost, and they have been growing sideways ever since. Walk it slowly and you pass through three centuries in about eleven minutes.",
        "Nobody owns a hedge in the way they own a field. The land under it belongs to a farm, the birds in it belong to nobody, and the view of it belongs, in a loose and sentimental way, to everyone who drives past. That is exactly why it is so hard to decide who should pay to keep it standing.",
        "A laid hedge costs about a thousand pounds a mile to make and very little to keep, provided somebody comes back every few years. A flailed hedge costs almost nothing to cut and slowly turns into a line of bruised stumps. The difference only shows on a time scale longer than most farm tenancies.",
        "In the survey of 1947 the parish counted forty-one miles of hedge. By 1990 it was twenty-six, and the missing fifteen had become wider fields, a bypass and a car park behind the school. The recount this spring found thirty-two. Most of the new miles were planted by volunteers on Saturday mornings.",
        "The layer works with a billhook, a pair of leather gloves and a thermos. He cuts each stem three quarters of the way through, close to the ground, and lays it over at an angle so that the sap still runs through the hinge of bark. By spring the whole line has sprouted from the base, dense enough to stop a sheep.",
        "The accounts of a hedge are kept by the birds. Yellowhammers need a thick base and a view of open ground; dormice need hazel and an unbroken line to travel along; bullfinches need the buds that a hard trim removes. Count what lives in a mile and you have a fair audit of how it has been treated.",
        "Grants arrive in the autumn and must be spent by the spring, which suits the work, since hedges are cut in the winter when the birds have finished nesting. The trouble is the years between. A hedge laid with a grant needs a light trim three years later, and there is rarely money for that.",
        "The old maps show the hedges as thin black lines, all the same weight. They do not say which were laid and which were left, which carried a stream along their foot and which ran dry. The best record is still the memory of the people who walked them, and that record is getting shorter.",
        "Where a hedge runs along a slope it slows the water. After the storms two winters ago the lane below the laid section stayed passable, while the one below the flailed stretch filled with silt to the height of a boot. The parish council noticed, and so, for the first time, did the insurance assessor.",
        "The argument at the parish meeting went on for two hours. One side wanted the verges cut short for visibility; the other wanted them left for the orchids. In the end they agreed to cut every other year and to leave the corner by the stile alone, which is how most parish arguments end.",
        "Forty years is a long time to plan for, but it is the natural unit for a hedge. Plant it now and it will be laid for the first time in about eight years, again in twenty, and by the time it is forty it will be the kind of hedge people photograph for calendars, provided nobody forgets it in between.",
        "On the last stretch before the ford the hedge thins, and you can see where the old gate stood. The posts are gone but the gap remains, and a pair of wrens have claimed the thicket on either side of it. The layer says he will close it next winter. The wrens, presumably, have other plans.",
    ]
}
