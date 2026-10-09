# Security

Field's promise is that nothing leaves your phone that you didn't ask to send. A way around that is a vulnerability, and it should be reported privately, not in a public issue.

## How to report

- Use GitHub's private vulnerability reporting: the **Security** tab of this repository, then **Report a vulnerability**.
- Or email fieldbrowser.app@gmail.com.

Say what you found, which version of Field (Settings › About) and iOS, and the steps to see it. A page or link that shows it is the most useful thing you can send. Please give a fix time to ship before you publish.

## What's in scope

- **Privacy leaks.** Anything Field sends, or lets a page learn, that the README and [docs/privacy.md](docs/privacy.md) say it doesn't: what you type reaching your search engine when it shouldn't, history or saved pages leaving the phone, a fingerprint Field adds of its own.
- **Blocking bypasses.** A way for a page to load what the block lists or the navigation guard should stop: tracking parameters that survive, a redirect that isn't unwrapped, or an App Store or app-link hijack that gets through.
- **Private leaks.** Anything from Private that outlives it or reaches your ordinary tabs: something left on disk after Private closes, shared cookies or storage, a page shown while it's locked or under its cover, a link that opens in Private or unlocks it.
- Links from other apps that open something they shouldn't.

## What isn't

- What Private says plainly it can't do (docs/privacy.md, "Private"): screenshots, the keyboard learning words, hiding your IP address.
- Bugs in WebKit or iOS. Report those to Apple; tell us too if Field could work around one.
- A tracker the lists don't know about yet. That's an ordinary issue, or a report to EasyList or HaGeZi.
