"""Field's domain lists: HaGeZi's tracker and ad domains, less what EasyList
and EasyPrivacy already block, split into lists small enough for WebKit to
parse in one short hold of the main thread. Writes Adblock Plus syntax for
SafariConverterLib. Run by build.sh:

    uv run --quiet --script scripts/lists/domains.py <work> <out-prefix> <per-list>

Reads from <work>: easylist.txt, easyprivacy.txt and domains-*.src.txt (the
domain lists), and from scripts/lists: protected.txt, allowlist.txt, extra.txt.

- A domain blocks with every subdomain (`||d^`).
- A site's own domain (a registrable domain) blocks as a third party only,
  so the tracker's own site still works when visited; a subdomain blocks
  everywhere, which is what catches first-party trackers like
  smetrics.example.com.
- A protected domain (protected.txt, e.g. google.com) and a public suffix
  are never blocked whole, only named subdomains of them.
- EasyList and EasyPrivacy exceptions for a domain blocked here come along,
  since a WebKit list's exceptions only reach its own rules.
"""
import json
import re
import sys
from pathlib import Path

here = Path(__file__).parent
root = here.parent.parent
work, prefix, per_list = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])

domain_rule = re.compile(r"\|\|([a-z0-9._-]+)\^")
exception_host = re.compile(r"@@\|\|([a-z0-9.-]+)")


def lines(path):
    return [line.strip() for line in path.read_text().splitlines()]


def rules(path):
    """The plain `||domain^` rules of a list, ignoring comments and anything else."""
    return {m.group(1) for line in lines(path) if (m := domain_rule.fullmatch(line))}


def ancestors(domain):
    """The domain and each domain it's under: a.b.c, b.c, c."""
    labels = domain.split(".")
    return [".".join(labels[i:]) for i in range(len(labels))]


psl = json.loads((root / "FieldKit/Sources/FieldKit/Guard/Rules/public-suffix-list.json").read_text())
suffixes = set(psl["rules"])
wildcards = set(psl["wildcards"])
psl_exceptions = set(psl["exceptions"])


def is_suffix(domain):
    if domain in psl_exceptions:
        return False
    if domain in suffixes or "." not in domain:
        return True
    parent = domain.split(".", 1)[1]
    return parent in wildcards


def registrable(domain):
    """The public suffix plus one label, or None for a suffix itself."""
    parts = ancestors(domain)
    for i, candidate in enumerate(parts):
        if is_suffix(candidate):
            return parts[i - 1] if i > 0 else None
    return None


def entries(path):
    """Domains and exceptions from a Field rules file, one per line, `!` comments."""
    return [line for line in lines(path) if line and not line.startswith("!")]


protected = set(entries(here / "protected.txt"))
allowed_rules = entries(here / "allowlist.txt")
allowed = {m.group(1) for rule in allowed_rules if (m := exception_host.match(rule))}
extra = entries(here / "extra.txt")

wanted = set()
for source in sorted(work.glob("domains-*.src.txt")):
    wanted |= rules(source)

dropped = sorted(d for d in wanted if d in protected or is_suffix(d))
wanted -= set(dropped)
wanted -= allowed
# A subdomain of a domain that's already blocked adds nothing.
wanted = {d for d in wanted if not any(a in wanted for a in ancestors(d)[1:])}

# What EasyList and EasyPrivacy already block everywhere, or as a third party.
everywhere, third_party = set(), set()
for name in ("easylist.txt", "easyprivacy.txt"):
    for line in lines(work / name):
        if m := re.fullmatch(r"\|\|([a-z0-9.-]+)\^(\$third-party)?", line):
            (third_party if m.group(2) else everywhere).add(m.group(1))


def covered(domain):
    if any(a in everywhere for a in ancestors(domain)):
        return True
    # Third-party only here too, so the same thing.
    return registrable(domain) == domain and any(a in third_party for a in ancestors(domain))


before = len(wanted)
wanted = sorted(d for d in wanted if not covered(d))
covered_count = before - len(wanted)

blocked = set(wanted)
# Every domain a blocked one is under, to find exceptions for a parent domain.
under = {a for d in blocked for a in ancestors(d)}
cosmetic = re.compile(r"\$.*\b(elemhide|generichide|specifichide|genericblock)\b")
exceptions = set()
for name in ("easylist.txt", "easyprivacy.txt"):
    for line in lines(work / name):
        m = exception_host.match(line)
        if not m or cosmetic.search(line):
            continue
        host = m.group(1)
        if host in under or any(a in blocked for a in ancestors(host)):
            exceptions.add(line)
exceptions = sorted(exceptions)


def rule(domain):
    return f"||{domain}^$third-party" if registrable(domain) == domain else f"||{domain}^"


blocks = extra + [rule(d) for d in wanted]
tail = exceptions + allowed_rules
size = per_list - len(tail)
chunks = [blocks[i:i + size] for i in range(0, len(blocks), size)]
for i, chunk in enumerate(chunks, 1):
    Path(f"{prefix}-{i}.txt").write_text("\n".join(chunk + tail) + "\n")

print(f"  {before + len(dropped)} domains after merging; dropped {len(dropped)} protected or public suffixes"
      f" ({', '.join(dropped[:12])}{'…' if len(dropped) > 12 else ''}); {covered_count} already in EasyList or"
      f" EasyPrivacy; {len(wanted)} left in {len(chunks)} lists, with {len(exceptions)} EasyList exceptions")
