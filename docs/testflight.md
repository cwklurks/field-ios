# TestFlight notes

Text to paste into App Store Connect for the Release 1 beta. Each field is filled in by the account holder, by hand; the build side is in [docs/release.md](release.md).

## Beta App Description

At most 4,000 characters. Replace nothing below; paste it as it is.

> Field is a small, fast, quiet browser for the iPhone. One bar at the bottom — back, the address, the tab count — and the page. There is no start page, no feed, no account to sign into.
>
> Ads and trackers are blocked at the network level before a page draws, using EasyList, EasyPrivacy and HaGeZi's domain lists. Links arrive clean: redirect wrappers are unwrapped, tracking parameters are stripped, AMP pages go back to the original. Every site has an off switch.
>
> Tabs live in a two-across grid; swipe a card away to close it. A tab you are not using sleeps and costs nothing until you return to it. Your tabs come back after a quit.
>
> Saved keeps a page in one list, with folders and a Read later filter, and starred pages sit on the new-tab page.
>
> Private is a separate, always-dark space you deliberately enter. It keeps nothing on disk, locks when you leave, and is wiped when you close it. It is honest about what it cannot do.
>
> Field has no account, no sync, no analytics and no crash reporting. The only things that leave the phone are the pages you open and what they load, and, while Search suggestions is on, what you type in the bar, sent to your search engine as you type so it can suggest searches. That is never done in Private, and you can turn it off in Settings.
>
> This is version 0.1, an early beta. Expect rough edges. Send feedback from the TestFlight app, or to the email below.

## What to Test

For friends. Paste the list as it is.

> How to get in: open Field, choose a bar look on the first screen, then type an address or a few words in the bottom bar.
>
> Things worth trying:
>
> - Load a news site or a forum, and watch the ads, banners and video slots stay away. Then turn the shield off for that site from the bar's long press and see what changes.
> - Open a Google result, a Facebook or Reddit outbound link, and an AMP link. Each should open at the real address, with the wrapper and the tracking parameters gone.
> - Open a page that tries to push you into the App Store, and one that opens a popup. The first should be stopped; the second should show a "Popup blocked" chip with an Open button.
> - Open eight or more tabs, swipe up for the grid, swipe a card away to close it, then force-quit and reopen. Your tabs should come back.
> - Star a page to Saved, make a folder, and try Read later.
> - Long-press the address and use Capture Page to save a long page as a PDF, and again as one image. Then press side + volume up and use Full Page in the screenshot editor.
> - Type a few words in the bar slowly. Your past searches and pages sit nearest the field; your search engine's suggestions appear above them without moving them. Tap the arrow on a suggestion to put it in the field without going. Then turn Search suggestions off in Settings, or enter Private, and check no engine suggestions appear (local history and past searches can still appear).
> - Enter Private, sign in to something if you like, then leave and come back. It should lock, and closing it should wipe it. Read the "What Private can't do" screen.
>
> What feedback helps most:
>
> - anything that crashes, hangs or drops frames, with the site and what you were doing;
> - pages that break with blocking on, so the lists can be tuned;
> - links that still arrive with tracking parameters or wrappers;
> - anything that reads as wrong or confusing, including the wording.
>
> Screenshots and the iPhone model help a lot. Thank you.

## Feedback email

fieldbrowser.app@gmail.com

## Beta App Review notes

Paste into App Store Connect's App Review Information.

> Sign-in is not required. Field has no account, no sign-up and no sign-in screen; it opens straight into a browser.
>
> To reach the main features: type an address or a few words in the bottom bar and press Return. Swipe up on the bar for the tab grid; swipe sideways on the bar to change tabs. Long-press the back button for forward and back history; long-press the address for Save, Copy, Share, Capture Page and the per-site blocking switch. Settings is on the grid's row, and About › Built on Search shows the app's notices in full.
>
> Ad and tracker blocking is on by default, and can be turned off for one site from the bar's long press.
>
> Search suggestions are on by default: what is typed in the bar is sent to the chosen search engine's public suggestion endpoint as it is typed, without cookies, and never in Private. They can be turned off in Settings, under Search engine. Address and secret filters are best effort: unfamiliar address prefixes and unrecognized secrets can still be sent. Requests use a neutral User-Agent and fixed English language header. Past searches are saved locally even with suggestions off; there is no in-app clearing control yet.
>
> Tor is not part of this build. It is planned for a later release, so any mention of it elsewhere does not apply to this version.
