# Field: switching browsers, default browser, and supporter purchases

Researched **2026-10-08**. Every finding below is checked as of that date, rather than a promise about a later release. Sources are Apple, browser vendors, their source repositories, and the format documentation Apple references. Recommendations and inferences are labeled. No app code changed, no purchases configured, no entitlement requested, and no App Store Connect settings inspected.

Local baseline: `aa5d724ddb3b69f78e6c887c7cfb137fcabf72ef`, branch `docs/research-switch-supporter`. Read [README](../../README.md), [PLAN](../PLAN.md), [privacy policy](../privacy.md), [release notes](../release.md), [Saved research](tidy-and-saved.md), and the Saved, History, and Suggest implementations. The user's newer decisions control: open source under the MPL-2.0; free browser; optional tips and a paid element; privacy features free; passwords stay in iOS Passwords.

## Bottom lines

1. **Switching:** Safari on iPhone exports a ZIP from **iOS 18.2**, with bookmark/Reading List HTML and documented history JSON. Its export is available outside the EU too; do not confuse it with the EU browser choice screen. Brave and DuckDuckGo can export bookmark HTML on the phone. For Chrome, Firefox, and Edge, a local iPhone file exporter was not verified; document account/desktop routes honestly. Apple also has **BrowserKit browser-to-browser transfers from iOS 26.4**, so file import is no longer the only public route. [iOS 18 updates](https://support.apple.com/121161), [Safari export](https://support.apple.com/guide/iphone/export-safari-data-to-another-browser-iph1852764a6/ios), [BrowserKit import manager](https://developer.apple.com/documentation/browserkit/bebrowserdataimportmanager).
2. **Default browser:** Field's browsing UI fits the functional criteria. It is **not ready as configured**: no incoming HTTP/HTTPS handler, scheme registration, or entitlement configuration was found. Request `com.apple.developer.web-browser`, implement incoming-link delivery, and verify the signed build. EU choice-screen inclusion is a separate download-based qualification, unavailable to a brand-new 1.0 on its present evidence. [Apple's criteria](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [EU choice screen](https://developer.apple.com/support/browser-choice-screen/).
3. **Money:** Use StoreKit 2: repeatable **consumable tips**, plus a **non-consumable Field Supporter** for named cosmetic extras. A server is unnecessary for Apple's on-device transaction verification. Provide Restore Purchases for Supporter. Recommendation: USD **$9.99 once**, tips **$0.99 / $2.99 / $9.99**, localized through StoreKit. These are tentative proposals, not configured prices. [IAP types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/), [verification](https://developer.apple.com/documentation/storekit/verificationresult), [review 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).
4. **Privacy label:** Local imports and local StoreKit entitlements do not themselves require declaring collection. **The current suggestion configuration remains the unresolved part of “Data Not Collected.”** Apple excludes open-web navigation, but does not explicitly settle native autocomplete in the pages checked. Other browsers' labels are useful comparisons, not approval for Field. Recommendation for an unambiguous 1.0: local suggestions only until Apple clarifies this or the label is changed on a supported, provider-specific basis. Merely making remote suggestions opt-in does not exempt collection. [Apple's definitions and web-view guidance](https://developer.apple.com/app-store/app-privacy-details/).
5. **Privacy manifest:** Importing selected file contents, StoreKit, and alternate icons do **not automatically add a required-reason category**. Reading file metadata through listed APIs does: use `3B52.1` for user-selected files, `C617.1` for files in Field's container, when those uses actually occur. Dates embedded in HTML/JSON are not filesystem timestamp APIs. [API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).
6. **Launch:** Host a public privacy policy and a real support page, link the policy in-app, finish the current age questionnaire, and supply a large-iPhone screenshot set. Unrestricted web access maps to **16+ in the current rating system**, not automatically 18+; older OS storefronts use 17+. Previews are optional. Nominate in App Store Connect at least **three weeks** ahead; Apple's broader featuring page says two weeks minimum and up to three months for wider consideration. [Version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), [age definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/), [nominations](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/).

## 1. Exporting and transferring browser data

### Safari on iPhone and Mac (checked 2026-10-08)

**iPhone, iOS 18.2+:** Settings > Apps > Safari > Export, under History and Website Data. Choose Bookmarks, History, Extensions, Credit cards, and/or Passwords; choose a profile or All Profiles; Save to Downloads. The result is a ZIP in Downloads. History and extensions are per profile; bookmarks, cards, and passwords are shared across profiles. [iPhone instructions](https://support.apple.com/guide/iphone/export-safari-data-to-another-browser-iph1852764a6/ios), [version introduction](https://support.apple.com/121161).

**Regions:** this is not an EU-only export. Apple's US guide and non-EU localized guides document it without an EU condition. That supports offering Safari file import globally; it is not a device-by-device regional test. The EU restriction belongs to the EU choice screen and certain alternative-engine capabilities. [US guide](https://support.apple.com/guide/iphone/export-safari-data-to-another-browser-iph1852764a6/ios), [UAE guide](https://support.apple.com/en-ae/guide/iphone/iph1852764a6/ios), [choice-screen scope](https://developer.apple.com/support/browser-choice-screen/).

**Mac, current Safari:** File > Export Browsing Data to File; choose categories and profiles; Download; choose a filename and location. It exports a ZIP with the same category split. Apple documents no EU-only condition. Apple's **macOS 15.2** notes explicitly introduce expanded history/bookmark/password import and export. Safari 18.2 is also available on Sonoma/Ventura, but availability of the full ZIP UI on those older systems was not conclusively established here. Do not tell users all older Safari versions have it. Older bookmark-only export is File > Export > Bookmarks and produces `Safari Bookmarks.html`. [Current Mac instructions](https://support.apple.com/guide/safari/ibrwebf10132/mac), [macOS 15.2 introduction](https://support.apple.com/120283), [Safari 18.2 availability](https://developer.apple.com/documentation/safari-release-notes/safari-18_2-release-notes), [older HTML instructions](https://support.apple.com/117827).

**Delivery to Field:** users can select the ZIP or extracted HTML/JSON in Field's document picker. Files can also share a selected file, and a Mac export can reach the iPhone using AirDrop or a file provider. Being on the share sheet requires Field to register appropriate document handling; a browser entitlement alone does not register a ZIP importer. Recommendation: make **Import from Files** the reliable first route, then add file-open registration if useful. [Files sharing](https://support.apple.com/guide/iphone/send-files-from-the-files-app-iphf2746307f/ios), [document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller), [document types](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes).

**iOS 26.0+ shortcut:** `SFSafariSettings.openExportBrowsingDataSettings(completionHandler:)` presents Safari's export sheet from Field while Field is in the foreground. It does not hand Field Safari's private database or automatically import the result. [API](https://developer.apple.com/documentation/safariservices/sfsafarisettings/openexportbrowsingdatasettings(completionhandler:)), [June 2025 update](https://developer.apple.com/documentation/updates/safariservices).

**Contents:** Safari exports HTML bookmarks, CSV passwords, and JSON history/cards/extension information. Reading List is included in the bookmark HTML as a folder identified by `com.apple.ReadingList`. Extension export is information for finding the containing app, not portable extension code. English filenames are `Bookmarks.html`, `Passwords.csv`, `History.json`, `PaymentCards.json`, and `Extensions.json`; filenames are localized and profile exports have profile-name suffixes. Do not hard-code English names. [Apple's interchange documentation](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).

Recommendation: read only bookmark and selected history entries. Ignore passwords, cards, and extensions; do not extract them unnecessarily. Safari warns that the archive is **unencrypted**. Tell users to deselect those categories before exporting and delete the export when finished. Field should remove its temporary copy without deleting the user's original. [Safari warning](https://support.apple.com/guide/iphone/export-safari-data-to-another-browser-iph1852764a6/ios).

### Safari history: documented schema (checked 2026-10-08)

These are the exact documented keys and types, rather than a guessed format. All `_usec` timestamps below are **microseconds since 1970-01-01 UTC**. [Apple schema](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).

| Object | Keys |
|---|---|
| Top level | `metadata`: object; `history`: array of objects |
| `metadata` | `browser_name`: string; `browser_version`: string; `data_type`: string (`history` here); `export_time_usec`: integer; `schema_version`: integer |
| Each history object, required | `url`: string; `time_usec`: integer, latest visit; `visits_count`: integer >= 1 |
| Optional title | `title`: string |
| Optional next redirect | `destination_url`: string; `destination_time_usec`: integer, present with destination URL |
| Optional previous redirect | `source_url`: string; `source_time_usec`: integer, present with source URL |
| Optional status | `latest_visit_was_load_failure`: Boolean; `latest_visit_was_http_get`: Boolean |

Redirect records join on URL **and** visit timestamp. Recommendation: retain successful final destinations for Field's compact history, not every redirect shim; warn that this is a summarized import. Keep unknown fields ignorable, but reject unsupported schema versions with a useful message. Do not assume an omitted failure/GET flag is explicitly false. Source for the transfer semantics: [Safari schema](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).

### Other iPhone browsers (checked 2026-10-08)

“Not verified” means the vendor pages checked did not document a local file exporter. It does not prove the latest installed app lacks one, especially after BrowserKit's arrival. Sync is not the same operation as a local export.

| Source | Bookmarks on the phone | History on the phone | Practical route into Field |
|---|---|---|---|
| **Chrome** | No local HTML export verified. Google's HTML export instructions are for a computer. | No local history file export verified. Google documents account-data export through Takeout. | Desktop HTML; or request a Chrome-only Takeout archive through a browser on the phone. Takeout covers Google-account data, not a guaranteed dump of all device-local history. [Chrome bookmarks](https://support.google.com/chrome/answer/96816?hl=en), [Chrome export](https://support.google.com/chrome/answer/10248834?hl=en), [Takeout](https://support.google.com/accounts/answer/3024190?hl=en) |
| **Firefox** | No local HTML export verified in iOS help. | No local history file export verified. | Mozilla Account Sync can move bookmarks/history to desktop Firefox; export bookmark HTML there. Do not require a Field account or promise Firefox history import from its bookmark file. [iOS Sync](https://support.mozilla.org/en-US/kb/sync-bookmarks-logins-and-browsing-history-firefox), [desktop export](https://support.mozilla.org/en-US/kb/export-firefox-bookmarks-to-backup-or-transfer) |
| **Brave** | **Yes.** Menu > Show All… > Bookmarks > share icon at bottom left > Export, at the root folder. Produces `.html`; share sheet can Save to Files. | No local history exporter verified in the checked iOS documentation. | Import the HTML directly. No Sync required. [Brave instructions](https://support.brave.com/hc/en-us/articles/360057082371-How-do-I-Import-or-Export-Bookmarks-on-iOS) |
| **DuckDuckGo** | **Yes**, demonstrated by its own current iOS source: Bookmarks' more menu offers export, writes bookmark HTML, then presents `UIActivityViewController`. | No history export verified; do not confuse bookmark export with browsing-history export. | Bookmarks > more/import-export menu > Export > Save to Files. Menu wording should be device-checked. [Vendor source, pinned revision](https://github.com/duckduckgo/apple-browsers/blob/dd4d25695bbb081989ddf99aad206cd473d1e8d9/iOS/DuckDuckGo/Bookmarks/BookmarksViewController.swift#L759) |
| **Edge** | No local iPhone HTML export verified. | No local iPhone history file export verified. | Sync favorites to desktop Edge and export there. The mobile FAQ and Sync help establish access/sync, not a phone file exporter. [Mobile FAQ](https://support.microsoft.com/en-us/microsoft-edge/microsoft-edge-for-mobile-faqs-29296eab-b76f-4a87-ac9c-9835da53465d), [Sync](https://support.microsoft.com/en-us/edge/sign-in-to-sync-microsoft-edge-across-devices) |

Recommendation: say “Import a bookmarks file” rather than claim a one-tap switch from every iPhone browser. Offer vendor-specific instructions with a desktop fallback. Check actual installed vendor versions before putting those instructions in the app.

### Desktop Chrome, Firefox, and Takeout (checked 2026-10-08)

**Chrome:** More > Bookmarks and lists > Bookmark manager > manager's More > Export bookmarks. The output is HTML. A desktop browser sync can make mobile bookmarks available first. **Firefox:** Bookmarks > Manage Bookmarks > Import and Backup > Export Bookmarks to HTML. Firefox's JSON backup is a separate Firefox restore format; it is not the first interchange target. Neither HTML file contains browsing history. [Google instructions](https://support.google.com/chrome/answer/96816?hl=en), [Mozilla instructions](https://support.mozilla.org/en-US/kb/export-firefox-bookmarks-to-backup-or-transfer).

**Google Takeout:** select Chrome data, request a one-time ZIP, download it, and choose the history JSON in Field. This can be requested on an iPhone through the web, but is an account export, not a local Chrome menu command. Account/sync settings and deleted or encrypted data affect what is available. Use a **Chrome-only** export, not an archive of Gmail, Photos, and everything else. [Chrome exported categories](https://support.google.com/chrome/answer/10248834?hl=en), [Takeout delivery and formats](https://support.google.com/accounts/answer/3024190?hl=en).

Google's own Chrome export schema documents JSON with a **`Browser History`** array. Objects include `title`, `url`, `time_usec` (UNIX microseconds), `client_id`, and `favicon_url`; there are also Typed URL and Session arrays. Encrypted data may put a text message in the array instead of an object. Recommendation: parse just valid history objects, ignore client IDs and favicon URLs, and never fetch their icons during import. Google's schema page is for its Data Portability API; treat Takeout filename and extra-field equivalence as fixture-dependent rather than a guaranteed API contract. [Google schema](https://developers.google.com/data-portability/schema-reference/chrome).

Recommendation: support the `Browser History` structure, not a filename named exactly `BrowserHistory.json`. Do not conflate it with Google **My Activity/Search** exports, which have a different meaning and format. Do not add Google OAuth or a portability API integration to a no-account Field app just to read a user-picked file.

### Netscape bookmark HTML (checked 2026-10-08)

This is a **de-facto interchange format**, not a modern W3C bookmark standard. Apple points to Microsoft's archived Netscape Bookmark File Format description. It uses the `NETSCAPE-Bookmark-file-1` doctype; nested `DL` lists; folder titles in `DT/H3`; links in `DT/A` with `HREF`; optional `ADD_DATE`, `LAST_VISIT`, and `LAST_MODIFIED`. Dates are decimal **UNIX seconds**, unlike Safari/Google history microseconds. [Format description](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa753582(v=vs.85)).

Real producer behavior and parser implications:

- **Not XML:** optional closing tags and `<DL><p>` occur in the documented format. Use a tolerant HTML tokenizer/parser with a folder stack, not XML parsing or one regular expression. Treat the file as data; never render it in a web view. [Format](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa753582(v=vs.85)).
- **Encoding and entities:** current Chrome and Firefox export UTF-8 and a charset meta tag, and escape content. Recommendation: honor a BOM/declared encoding where supported, decode entities, tolerate tag/attribute case, and report unsupported legacy encodings. Do not silently corrupt titles. [Chromium writer](https://github.com/chromium/chromium/blob/main/chrome/browser/bookmarks/bookmark_html_writer.cc), [Mozilla writer](https://github.com/mozilla/gecko-dev/blob/master/toolkit/components/places/BookmarkHTMLUtils.sys.mjs).
- **Special roots:** Chrome exports toolbar, other, and mobile bookmark roots; `PERSONAL_TOOLBAR_FOLDER="true"` marks its bar. “Other bookmarks” is a localized container name, not a portable English identifier. Firefox uses `UNFILED_BOOKMARKS_FOLDER` for its unfiled root. Keep these contents; do not discard them or match only English titles. [Chromium writer](https://github.com/chromium/chromium/blob/main/chrome/browser/bookmarks/bookmark_html_writer.cc), [Mozilla writer](https://github.com/mozilla/gecko-dev/blob/master/toolkit/components/places/BookmarkHTMLUtils.sys.mjs).
- **Reading List:** recognize Safari's `com.apple.ReadingList` identifier, not just the translated folder title. Preserve it as Read later candidates; ordinary favorite/bar items are a different mapping decision. [Safari interchange](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).
- **Extra attributes/content:** icon data, descriptions, separators, and old feed/Web Slice attributes exist. Recommendation: ignore them in the first importer. Validate `http`/`https` and host, remove URL credentials, and reject executable bookmarklets as unsupported. The source formats permit more than Field's Saved model. [Format](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa753582(v=vs.85)), [Saved](../../FieldKit/Sources/FieldKit/Saved/Saved.swift).

### BrowserKit: public app-to-app transfer (checked 2026-10-08)

**Exists; iOS/iPadOS 26.4+, including iOS 27.** BrowserKit itself dates to 18.4, but its import/export managers and transfer data classes date to **26.4**. Do not gate transfers merely on `canImport(BrowserKit)` or 18.4. [Framework](https://developer.apple.com/documentation/browserkit), [import manager](https://developer.apple.com/documentation/browserkit/bebrowserdataimportmanager), [export manager](https://developer.apple.com/documentation/browserkit/bebrowserdataexportmanager).

The system presents a sheet to choose a browser and data categories. `BEBrowserDataImportManager(scene:)` requests import using `BEImportMetadata`; `BEBrowserDataExportManager(window:)` requests export using `BEExportMetadata` and receives selected `BEExportOptions`. Import receives a stream through `importBrowserData(token:)`; export supplies a stream through `exportBrowserData(_:)`. A user choosing Files still requires Field's own file importer/exporter. [Transfer workflow](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser).

Register `BEBrowserDataExchangeImportActivity` and `BEBrowserDataExchangeExportActivity` in `NSUserActivityTypes`; respond with SwiftUI `onContinueUserActivity`. The system launches/relaunches the other browser and carries a UUID token in activity `userInfo`, accessed through the manager's import/export token key. Transfer only in response to the user's request and validate that token. [Workflow and activity handlers](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser).

Data is typed rather than a ZIP contract: `BEBrowserDataBookmark` has folder/identifier/parent identifier information; `BEBrowserDataHistoryVisit` has URL, latest date, count, title, success/GET and redirect fields; `BEBrowserDataReadingListItem` is separate; extensions carry identification/store information. Passwords and payment cards are **not listed transfer categories**. [Bookmarks](https://developer.apple.com/documentation/browserkit/bebrowserdatabookmark), [history](https://developer.apple.com/documentation/browserkit/bebrowserdatahistoryvisit), [Reading List](https://developer.apple.com/documentation/browserkit/bebrowserdatareadinglistitem).

**Entitlement and region:** Apple's workflow says the app must meet default-browser criteria, linking the `com.apple.developer.web-browser` requirements. No separate browser-data entitlement or EU-only condition is specified in the transfer pages checked. Recommendation: obtain the default-browser entitlement and treat direct transfer as available only when the OS and participating browsers support it. **Worldwide runtime behavior and each vendor's participation remain unverified.** BrowserKit's alternative-engine eligibility checks and **BrowserEngineKit** are different capabilities; Field's system WKWebView does not need an alternative-engine entitlement. [Transfer requirements](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser), [browser entitlement](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [alternative-engine requirements](https://developer.apple.com/support/alternative-browser-engines/).

## 2. Default-browser entitlement

### Criteria and restrictions (checked 2026-10-08)

The default-browser option has existed since iOS 14. Apple requires HTTP/HTTPS scheme declarations, prohibits `UIWebView`, and requires a URL field, web-search tools, **or** curated bookmarks at launch. Opening a web URL in the default configuration must reach its expected destination and content. Unexpected redirects or substituted content do not qualify; safety warnings and deliberately restricted parental-control modes are allowed. Entitled browsers cannot claim Universal Links for particular domains, though they may open links in other apps. [Apple requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser).

Apple rejects entitled browsers using full-photo-library, always-on location, HomeKit, background Bluetooth, or Health permission keys specified in that page. Photo saving should use `NSPhotoLibraryAddUsageDescription`; uploading can use WebKit's picker. Use while-in-use location if necessary. Field's inspected `project.yml` uses photo-add, camera, microphone, local network, and Face ID; none is a listed prohibited key. This is a source-level check, not an inspection of an archived Info.plist. [Restrictions](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [Field configuration](../../project.yml).

Recommendation: no hard-coded homepage replacing an incoming link, affiliate detour, injected search ads, or mandatory Field search before navigation. Test clean-link unwrapping, de-AMP, HTTPS upgrades, and blocking against the user's intended destination; show an understandable failure/override instead of silently substituting a site. Apple's documentation does not pre-approve Field's guard rules. [Destination requirement](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [Field guard plan](../PLAN.md).

### Request, configuration, and delivery (checked 2026-10-08)

Use Apple's [Default browser entitlement request form](https://developer.apple.com/contact/request/default-browser-entitlement/) for `com.connork.fieldbrowser` under team `H435XM227M`. It is a **managed** entitlement; adding a Boolean locally does not obtain approval. After approval, configure the App ID, signing profile, and target entitlement, regenerate the project, and inspect the signed archive. The form also offers `com.apple.developer.browser.app-installation`; that is a separate choice for marketplace installation, unnecessary for the switching/Supporter scope. [Default-browser setup](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [managed capabilities](https://developer.apple.com/help/account/capabilities/capability-requests/).

Register inbound `http` and `https` under `CFBundleURLTypes` > `CFBundleURLSchemes`, with an appropriate URL type name/role. Receive URLs at the app/scene root, for example through SwiftUI `.onOpenURL`, and route them to Field's browser. **`LSApplicationQueriesSchemes` is not inbound registration**; it controls schemes queried through `canOpenURL`. Do not add a list of competitors just to become default. [URL types](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes), [schemes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes/cfbundleurlschemes), [onOpenURL](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)), [canOpenURL](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)).

**2025-2026/current SDK details:** `UIApplication.isDefault(.webBrowser)` is available from iOS 18.2 and rate-limited; respect its retry date. The current documentation marks `canOpenURL` deprecated in iOS 27, recommending attempting to open a URL and handling failure. Apps linked on/after iOS 27 are limited to **25** query-scheme entries, versus 50 from iOS 15. Neither requires filling `LSApplicationQueriesSchemes` to receive web links. The iOS 26 Safari export sheet and 26.4 BrowserKit transfer are the material switching additions. [Default status](https://developer.apple.com/documentation/uikit/uiapplication/isdefault(_:)), [query restrictions](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)), [SafariServices updates](https://developer.apple.com/documentation/updates/safariservices).

### Does Field qualify? Code check, 2026-10-08

| Criterion | Inspected evidence | Result |
|---|---|---|
| General-purpose URL entry and search | [Omnibox.submit](../../Field/Omnibox/Omnibox.swift), FieldKit address/destination parsing | Present |
| Bookmarks | [Saved model](../../FieldKit/Sources/FieldKit/Saved/Saved.swift), Saved UI and starred pages | Present; Apple does not require all three launch alternatives |
| Modern web renderer | [Tab](../../Field/Browser/Tab.swift) uses WKWebView; no `UIWebView` reference found | Present |
| Incoming external web link | No `onOpenURL`, scene URL-context handler, or equivalent app entry route found in `Field/`; [FieldApp](../../Field/FieldApp.swift) starts/restores the browser | **Missing.** Internal `Browser.go(to:)` is not external URL delivery |
| Scheme registration and managed entitlement | [Info.plist](../../Field/Info.plist), [project.yml](../../project.yml) have no HTTP/HTTPS URL type or browser entitlement setup | **Missing** in the source inspected |
| Prohibited permission keys | Source plist/build settings checked against Apple's list | None found; verify merged archive |

Recommendation: incoming web links open a **new regular tab**, including when Private is open or locked. Queue a cold-launch link until initialization/welcome completes; do not overwrite a user's current tab or expose a locked private session. Verify cold, warm, background, and locked-Private launches using HTTP and HTTPS from Mail/Notes. In-app web views in another app are not all forced through the default browser. The normal HTTP/HTTPS handoff is what the entitlement governs. [Apple's handoff description](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser).

### EU choice screen and other regional changes (checked 2026-10-08)

**EU-only:** the choice-screen list needs the default entitlement, browsing as the primary purpose, EU/country App Store availability, and at least **5,000 iPhone downloads across EU storefronts in the previous calendar year**. Only the developer's most-downloaded browser is eligible. Up to 11 qualifying browsers plus Safari are selected per country; Apple refreshes eligibility annually, with a supplementation rule where fewer qualify. iPad has its own 4,000-download threshold. Field's TestFlight status does not establish qualifying App Store downloads. [EU eligibility](https://developer.apple.com/support/browser-choice-screen/).

Default-browser entitlement eligibility is **not** subject to that download floor. Recommendation: get the entitlement for 1.0; plan no choice-screen exposure in launch forecasts. Japan also has browser-choice changes from **iOS 26.2**, but that does not turn Safari file export or the standard default-browser entitlement into EU-only features. [Japan changes](https://developer.apple.com/support/app-distribution-in-japan/), [default-app user settings](https://support.apple.com/121430).

## 3. Tips and Field Supporter

### Review policy and product kinds (checked 2026-10-08)

Guideline **3.1.1** requires IAP for digital feature unlocks and permits tipping the developer through IAP. It also requires a restore mechanism for restorable purchases. Recommendation: use Apple IAP for the global tip jar and Supporter; regional external-payment exceptions are not needed for this design. Do not call a developer tip a charitable donation. Guideline **5.1.1** requires privacy policies and consent for collection; **5.1.2** prohibits requiring tracking or unnecessary system permissions to access functionality or receive compensation. [Review guidelines](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), [privacy rules](https://developer.apple.com/app-store/review/guidelines/#privacy).

I found **no categorical Apple rule banning paid privacy tools**. Charging for blocking or Private is ruled out by the user's decision, not an invented App Review prohibition. Cosmetic icons/bar looks and actual convenience functionality are plausible paid digital features; Supporter must clearly state the delivered extras, not imply the free browser collects data or that paying changes data handling. Recommendation: keep existing Glass/solid looks free and sell additional looks, not take away an existing choice. Do not advertise future Tidy extras as delivered today. [IAP unlock rule](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), [Field's existing looks](../PLAN.md).

**Consumable:** bought again; appropriate for a tip with no permanent entitlement. **Non-consumable:** bought once, does not expire; appropriate for Supporter. Neither requires a Field account. Finished consumables do not appear in `Transaction.currentEntitlements`; Supporter does, unless refunded/revoked. [Product kinds](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/), [current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements).

### On-device StoreKit 2 (checked 2026-10-08)

Apple verifies transactions and returns `VerificationResult`. Grant the unlock only for verified transactions for Field's expected products; do not trust a standalone UserDefaults `supporter = true`. This can run entirely on-device without a developer receipt-validation server. StoreKit is still a networked Apple purchase service, not an offline payment system. [VerificationResult](https://developer.apple.com/documentation/storekit/verificationresult), [Meet StoreKit 2, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10114/).

Recommendation: load localized `Product` data; process purchase success, pending, cancellation, and verification failure; deliver the product before finishing its transaction. Listen to `Transaction.updates` from launch for deferred purchases and changes on another device; rebuild Supporter from verified current entitlements and respond to revocation/refund. Keep any bookkeeping local and exclude transaction IDs from logs exported to the developer. [Product purchase](https://developer.apple.com/documentation/storekit/product/purchase(options:)), [transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates), [finish](https://developer.apple.com/documentation/storekit/transaction/finish()).

Add **Restore Purchases** to the Supporter screen. The user action calls `AppStore.sync()` and refreshes verified entitlements. Apple says sync can prompt for authentication, so do not invoke it automatically at launch; ordinary launch/reinstall entitlement recovery is automatic. It does not refund or “restore” spent tips into money or new perks. [Restore API](https://developer.apple.com/documentation/storekit/appstore/sync()).

### Small Business Program and prices (checked 2026-10-08)

Apple's standard Small Business Program commission is **15%** for paid apps and IAP. New developers and developers with up to **USD $1 million proceeds** in the previous calendar year can qualify, subject to associated-account and current-year rules. Enrollment is not automatic: Account Holder accepts the latest Paid Apps agreement, identifies associated accounts, and submits enrollment. The reduced rate starts on Apple's specified fiscal schedule after approval, not instantly when the form is submitted. [Program and enrollment](https://developer.apple.com/app-store/small-business-program/).

App Store Connect currently offers **800 price points by default**, plus 100 higher points by request. Choose a base country/region; Apple generates prices for other storefronts with tax/currency adjustments, or manage them manually. Use `Product.displayPrice`, not hard-coded dollars. Avoid old numbered “tier” assumptions. Proposed USD prices below need confirmation in the actual account before submission. [IAP pricing](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/), [displayPrice](https://developer.apple.com/documentation/storekit/product/displayprice).

### Alternate icons and indie copy (checked 2026-10-08)

Use bundled alternate icon assets and Xcode's `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; Xcode generates the corresponding `CFBundleIcons` entries. The user selects an icon and Field calls `setAlternateIconName`; passing `nil` restores the primary icon. **iOS displays a system alert announcing the change.** Do not promise a toast-only experience or use private methods to suppress it. Handle unsupported/error states and show a preview before the user chooses. [Apple alternate-icon guide](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons), [UIKit API](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:)).

Review rules still require accurate, recognizable app metadata/icons and IAP for paid digital unlocks. No separate mandatory review exemption for paid alternate icons was found. Recommendation: keep icons recognizably Field; let people choose them explicitly; describe the actual unlock in purchase and review notes. [Metadata and icons, 2.3.8](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).

Two primary indie examples: **Dice by PCalc** describes a tip jar that unlocks only its thanks; **PCalc** describes optional tips with extra icons while its calculator functionality remains available. These demonstrate published product wording, **not access to Apple's private review decision or a guarantee for Field**. [Dice release history](https://pcalc.com/dice/history.html), [PCalc developer announcement](https://pcalc.com/ios/whatsnew.html).

Suggested Field copy, original recommendation:

> **Field Supporter**
> Extra app icons and bar looks. One purchase. No subscription.
> Browsing and privacy protections stay free.

> **Leave a tip**
> An optional thank-you for making Field. Tips do not unlock features.

Keep these separate. A tip must not silently purchase Supporter, and a Supporter payment should not be presented as a donation with unspecified benefits.

## 4. App Store privacy label

### Definitions: short exact excerpts, then their meaning (checked 2026-10-08)

Apple's wording includes:

- **Collect:** “transmitting data off the device”. The full definition additionally requires developer/partner access beyond servicing the request in real time.
- **Third-party partners:** “other external vendors whose code you’ve added to your app”, alongside analytics, advertising networks, and third-party SDKs.
- **Linked:** identity linkage “via their account, device, or other details”. Removing a name alone is insufficient; de-identification must prevent re-linkage.

These are excerpts, not the full definitions. On-device processing is excluded; Apple alone collecting through its services is not the developer's disclosure responsibility; open-web navigation has a specific exclusion. Optional/opt-in ongoing collection still generally requires disclosure. [Full Apple definitions and examples](https://developer.apple.com/app-store/app-privacy-details/).

### Purchases and imports (checked 2026-10-08)

**Inference for Field:** verifying StoreKit purchases locally and keeping the entitlement locally does not mean Field collects Purchase History. Apple processes the purchase; Field does not transmit purchase information to its developer or another SDK/vendor. Local bookmark/history imports likewise do not become collection merely by being read. This changes if transaction details, imports, or derived information are uploaded. [Apple on-device/Apple-service guidance](https://developer.apple.com/app-store/app-privacy-details/), [StoreKit verification](https://developer.apple.com/documentation/storekit/verificationresult).

No server also means no server-side fraud analysis, entitlement dashboard, or purchase-event analytics. Those are not needed for this proposed unlock. Update the policy to distinguish **Apple purchase processing** from Field's local state instead of claiming no network communication apart from pages/suggestions once StoreKit ships.

### Search suggestions: what the code does and what is unresolved (checked 2026-10-08)

Field's `Suggest.enabledByDefault` is `true`. Prefixes of at least two characters are sent after a pause to the chosen supported engine, unless Private or filters stop the request. The session disables cookies, credentials, cache and redirects, and uses fixed headers. The recipient still sees the prefix and IP address. This is an app-owned `URLSession` feature, not just content fetched by a website the person opened. [Gate](../../FieldKit/Sources/FieldKit/Suggest/Suggest.swift), [endpoints](../../FieldKit/Sources/FieldKit/Suggest/SuggestEndpoint.swift), [networking](../../FieldKit/Sources/FieldKit/Suggest/EphemeralFetch.swift).

Apple defines Search History as information about searches performed in an app. It does **not explicitly say** whether an unsubmitted prefix qualifies, whether native browser autocomplete is covered by the open-web exclusion, or whether an HTTP endpoint with no vendor SDK makes that search provider a label partner. Narrowly reading the code-integration definition supports excluding the provider; broadly reading this as an integrated app feature supports disclosure if the provider retains the data. **Neither interpretation is a verified Apple ruling for Field.** [Definition and web-view exclusion](https://developer.apple.com/app-store/app-privacy-details/).

A cookie-free session is not proof of real-time-only processing at the recipient. Google documents typed text/IP going to an engine for Chrome suggestions and describes activity collection in its privacy policy. DuckDuckGo says it saves anonymous queries disconnected from identifiers; that is a different practice, not proof that Field's particular autocomplete endpoint retains nothing. No endpoint-specific retention assurance for all seven providers was established. [Chrome explanation](https://support.google.com/chrome/answer/13730681?hl=en), [Google policy](https://policies.google.com/privacy?hl=en), [DuckDuckGo policy](https://duckduckgo.com/privacy).

### What comparison browsers declare (US listings checked 2026-10-08)

| Browser | Declared label | Search-suggestion inference |
|---|---|---|
| DuckDuckGo | Data Not Linked to You: contact information, usage, diagnostics; no Search History declaration visible | Its own search policy is materially different from Google's. [Listing](https://apps.apple.com/us/app/duckduckgo-optional-duck-ai/id663592361) |
| Firefox | Linked contact information; unlinked identifiers, usage and diagnostics; no Search History declaration visible | iOS help says suggestions are enabled by default. [Listing](https://apps.apple.com/us/app/firefox-fast-private-browser/id989804926), [suggestion settings](https://support.mozilla.org/en-US/kb/turn-search-suggestions-or-firefox-ios) |
| Brave | Unlinked identifiers and usage; no Search History declaration visible | Its general privacy-settings help explains sending text to the search engine, but is not proof of the latest iOS default. [Listing](https://apps.apple.com/us/app/brave-browser-search-engine/id1052879175), [help](https://support.brave.com/hc/en-us/articles/360017989132-How-do-I-change-my-Privacy-Settings) |
| Orion | **Data Not Collected** | Its docs ask users to choose an engine on first use because typing can expose IP/fingerprint; this is not a zero-network browser. [Listing](https://apps.apple.com/us/app/orion-browser-by-kagi/id1484498200), [engine choice](https://help.kagi.com/orion/getting-started/search-engine.html) |

The labels do not attribute each declaration to a feature or show why search suggestions were omitted. Apple says these disclosures are supplied by developers, not independently verified labels. Thus “these browsers omit Search History” is verified; “Apple explicitly exempts their suggestions” is **not**.

### Recommendation and concrete answers (2026-10-08)

**Recommendation:** preserve the intended **Data Not Collected** claim by shipping **only local suggestions** for 1.0 unless Apple confirms that Field's native engine suggestions fall within its browser exclusion. Submitted searches still navigate to the selected engine as normal open-web browsing. This is a conservative product recommendation, not a newly discovered rule that all browsers must disable autocomplete.

For that configuration, with imports and StoreKit entirely local:

| App Privacy question | Recommended answer |
|---|---|
| Do Field or its partners collect data from this app? | **No** |
| Purchase History | Do not select: Apple processes payment; Field keeps verified entitlements on-device |
| Browsing History / Search History | Do not select for local history/imports and ordinary open-web navigation |
| Data linked to you | No collected types to classify |
| Tracking | **No**; no tracking implementation or advertising SDK identified |
| Privacy policy URL | Public hosted policy required; explain local data, website/search recipients, and Apple purchase processing |

Basis: [Apple label guidance](https://developer.apple.com/app-store/app-privacy-details/), source inspection above. These answers are conditional on that configuration, **not certification of today's default-on suggestion build**.

**If keeping today's native remote suggestions:** do not silently certify “Data Not Collected” based on no server or on cookie filtering. Seek a specific Apple answer with the endpoint list and request behavior. If Apple treats them as collected Search History, disclose it for **App Functionality**, plus any confirmed recipient uses. Mark **not linked** only with supported pre-collection de-identification/recipient behavior; absent that evidence, a linked classification is the conservative choice. Assess tracking from actual cross-app advertising reuse; a linked label alone does not mean tracking, and no-cookie traffic alone does not disprove it. Provider-specific declarations cannot be finalized from the evidence here. [Apple purposes/linkage/tracking definitions](https://developer.apple.com/app-store/app-privacy-details/).

Risk: default-on suggestions can send unintended personal text before Return; the existing filters are best effort. An opt-in improves informed choice but **does not by itself remove disclosure duties**. If the user prefers retaining suggestions to retaining the current label, that is a real product decision, with corresponding policy/manifest work rather than a cosmetic wording fix.

## 5. Privacy manifest and export compliance

### Required-reason APIs (checked 2026-10-08)

Apple's required-reason list is about API use, not whether a feature sounds privacy-sensitive. Reading bytes with `Data(contentsOf:)`, decoding dates stored inside an export, presenting a picker, using StoreKit, and setting an alternate icon are not themselves listed required-reason categories. Audit actual implementation and any ZIP/parser dependency; an SDK calling listed APIs needs accurate reasons in the applicable manifest. [Requirement](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [listed API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

| Actual added use | Manifest action |
|---|---|
| Decode `ADD_DATE`, `time_usec`, or StoreKit transaction dates | None for File Timestamp: these are payload values |
| Read selected source's creation/modification metadata using listed APIs | Add `NSPrivacyAccessedAPICategoryFileTimestamp`, reason **`3B52.1`** |
| Read timestamps/metadata of the copied archive or temporary files in Field's own container | Same category, **`C617.1`** where applicable |
| Display file timestamps to the user | **`DDA9.1`** may apply to that actual use; do not add it speculatively |
| Check available disk capacity before extraction/write, with visible low-space behavior | `NSPrivacyAccessedAPICategoryDiskSpace`, **`E174.1`** if implemented |
| Store local preferences or a convenience cache of purchase state in UserDefaults | Existing **`CA92.1`** covers own-container defaults; verified StoreKit remains the entitlement authority |

Sources: [listed APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

`stat`/`fstat` and related listed file APIs can fall under File Timestamp even if a wrapper is used to inspect size. Read bounded contents or audit the wrapper instead of assuming a size check is exempt. If both source and internal copies use those APIs, declare both applicable reasons. Do not read filesystem modification dates to invent a missing bookmark-save date. [API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Current [PrivacyInfo.xcprivacy](../../Field/PrivacyInfo.xcprivacy) has no collected types/tracking, plus UserDefaults `CA92.1` and boot time `35F9.1`. **Recommendation: no automatic additions for these features.** Add timestamp/disk reasons only when the final implementation calls the corresponding APIs. If the suggestion decision changes the collection classification, align `NSPrivacyCollectedDataTypes`, purposes/linkage/tracking, the policy, and App Store Connect. The manifest and store label are separate declarations; one does not update the other. [Manifest collection fields](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).

**Export compliance:** imports, icons, and using Apple's StoreKit do not propose a custom encryption implementation. Keep the existing Apple-only encryption exemption assessment for this scope; verify the actual archive and any new dependency. Tor remains a separate later reassessment, as the release plan already says. [Apple encryption determination](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/), [local release assessment](../release.md).

## 6. App Store 1.0 logistics

### Featuring (checked 2026-10-08)

App Store Connect > **Featuring Nominations** > create nomination > **App Launch**. Supply Field, planned date, platforms/regions, story and relevant details. Apple's Connect guide recommends **at least three weeks**. Its general featuring page instead says a minimum of **two weeks**, and up to **three months** ahead for wider consideration. Recommendation: use three weeks as the minimum planning buffer; do not delay forever awaiting a guaranteed feature. A nomination is optional and does not ensure selection. [Form workflow](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/), [editorial guidance](https://developer.apple.com/app-store/getting-featured/).

### Screenshots and preview video (checked 2026-10-08)

Field currently targets **iPhone only**. Apple's current specs group devices by display type, rather than relying only on the old 6.9-/6.5-inch names. Provide **1-10** JPEG/PNG screenshots without alpha; one accepted large-iPhone set can scale for the smaller iPhones. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [Field target](../../project.yml).

| Set | Accepted portrait sizes; landscape is the transpose |
|---|---|
| Large Dynamic Island iPhone | **1260 × 2736**, **1290 × 2796**, or **1320 × 2868** |
| Large Face ID iPhone fallback | **1284 × 2778** or **1242 × 2688**; required if no large Dynamic Island set |
| Recommendation for Field | Capture **1320 × 2868** on a supported large iPhone simulator/device; use a consistent set |

Apple also lists iPhone Duo outer **1398 × 2034** and inner **2007 × 2853** screenshots, with a requirement beginning **April 2027 for apps using iOS 27.1 SDK or later**. This is future-gated, not an additional 1.0 requirement on 2026-10-08. No iPad screenshot set is required for the current iPhone-only target. [Current screenshot table](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

**App previews are optional:** up to three per device size/language; **15-30 seconds**, **500 MB maximum**, **30 fps maximum**. For a modern Face ID/Dynamic Island iPhone, use accepted **886 × 1920 portrait** or **1920 × 886 landscape**, not the native screenshot resolution. H.264 in `.mov`, `.m4v`, or `.mp4`, progressive, target **10-12 Mbps**; ProRes 422 HQ `.mov` is another accepted format. If audio is included, H.264 uses stereo AAC **256 kbps**, **44.1 or 48 kHz**. Choose a poster frame; processing may take up to 24 hours. [Preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/).

Recommendation: screenshots first. A later preview can show actual address entry, Saved, blocking and Private without promising unavailable Tor or Tidy functionality.

### Age rating, public URLs, and remaining release work (checked 2026-10-08)

Answer **Yes** to Unrestricted Web Access. Under Apple's updated system it is a **16+** capability; older operating systems display the earlier **17+** rating. Other questionnaire answers and regional systems can change the outcome. Answer for Field's own features accurately; do not describe it as a children's browser because blocking exists. [Current and older rating tables](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).

**Known repo gaps:** `project.yml` still says **0.1**; About has no public privacy-policy link and its statement that only opened pages leave the phone already omits enabled suggestions. The private repo's policy is not a public policy URL. These are findings, not fixes made here. [Configuration](../../project.yml), [About](../../Field/Settings/About.swift), [current policy](../privacy.md).

Before submitting 1.0:

- Host the policy at a stable HTTPS URL, publicly accessible without sign-in. Include an easily accessible in-app link. Explain imports, local purchase entitlement, Apple's purchase processing, and the final suggestion behavior. A private GitHub file is insufficient. [Policy requirement, 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy).
- Host a **Support URL** with actual contact information. Marketing URL is optional; support is required. Keep review contact details current and mark login unnecessary. Set version 1.0 and complete name/subtitle/description, keywords, category, screenshots, copyright, availability and review information. [Version metadata requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).
- Accept the Paid Apps agreement and complete banking/tax setup for IAP; configure product localizations, prices, review screenshots/notes. The first product of each IAP kind must be submitted with a new app version; include both tips and Supporter in the 1.0 submission if ready. [Submit IAP](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/), [Paid Apps agreement/pricing](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/).
- **EU distribution:** declare trader status accurately and complete required contact verification if a trader. A monetized indie app is not automatically exempt because its author is an individual. [DSA requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).
- Verify the final signed entitlement, merged Info.plist, privacy report and export-compliance answer; use review notes to explain free privacy, paid cosmetics, import categories and no sign-in. The existing TestFlight release setup is a starting point, not proof of App Store metadata readiness. [Local release procedure](../release.md).

## What Field should build

The following is a proposed build order, not implementation completed in this research round.

### Import sources, in priority order

1. **Safari iPhone ZIP + standalone Netscape HTML**, available across Field's iOS 26.0+ range. Parse bookmark/Reading List HTML; separately opt in to Safari `history` JSON. Provide the iOS 26 Safari export-sheet shortcut and Files picker. This also handles current Mac Safari ZIPs and legacy Mac HTML. Ignore credential/card/extension files. [Safari file flow](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari), [export shortcut](https://developer.apple.com/documentation/safariservices/sfsafarisettings/openexportbrowsingdatasettings(completionhandler:)).
2. **Brave/DuckDuckGo iPhone and desktop Chrome/Firefox/Edge bookmark HTML** through the same parser. Give truthful export instructions; no Field account and no vendor sign-in inside Field. [Brave](https://support.brave.com/hc/en-us/articles/360057082371-How-do-I-Import-or-Export-Bookmarks-on-iOS), [DuckDuckGo source](https://github.com/duckduckgo/apple-browsers/blob/dd4d25695bbb081989ddf99aad206cd473d1e8d9/iOS/DuckDuckGo/Bookmarks/BookmarksViewController.swift#L759), [Chrome](https://support.google.com/chrome/answer/96816?hl=en), [Firefox](https://support.mozilla.org/en-US/kb/export-firefox-bookmarks-to-backup-or-transfer).
3. **BrowserKit direct switching on iOS 26.4+**, sharing the same normalized import model. Validate real Safari/vendor participation and regional behavior before advertising source-browser names. Keep Files fallback for 26.0-26.3 and nonparticipants; support export too so Field is not a one-way trap. [BrowserKit](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser).
4. **Google Takeout history JSON**, preferably as a selected extracted Chrome history file before adding general Takeout ZIP support. Parse `Browser History`, not My Activity; no OAuth, no SQLite rummaging in other app containers, no Firefox internal history database parser in the first version. [Google export schema](https://developers.google.com/data-portability/schema-reference/chrome).

Recommendation for mapping into existing FieldKit:

- Normalize in `FieldKit/`; keep picker/security-scoped access, temporary storage and BrowserKit adapters in the app. Preview counts, duplicates, skipped schemes, profiles and mapping losses; commit once after confirmation, with Undo. Bound file size, expanded ZIP size, record count and nesting; reject unsafe archive paths. No page loads, favicon fetching, live suggestions or cloud inference during import.
- **Saved:** one URL record, optional one-level folder, stars and `lastOpened`. Flatten nested folder paths to names such as `Work / Research`, with collision handling; preserve empty folders. Keep existing records on conflicts; repeated imports must be idempotent. Use sane `ADD_DATE` as `added`, otherwise import time. [Current Saved semantics](../../FieldKit/Sources/FieldKit/Saved/Saved.swift).
- **Stars/Read later:** preview a small set of source Favorites/toolbar links for optional stars; do not star hundreds automatically. Import Safari Reading List with `lastOpened = nil`. Existing `save` marks **every** new page unread, so explicitly decide how ordinary imported bookmarks should populate that filter; recommended: mark them already read while leaving Reading List unread. This needs a focused import API, not forged visits or a second Reading List model. [Saved model](../../FieldKit/Sources/FieldKit/Saved/Saved.swift).
- **History:** include it, **unchecked by default**. Explain that imported entries affect autocomplete and remain on-device. Add a bulk merge that preserves newest valid date and source count, filters credentials/non-web URLs/known load failures, and handles redirect destinations. Do not replay `record` once per source visit: it manufactures front-door credits, assumes a visit is happening, and can skew counts/dates. The persisted history caps at **2,000 ranked records**, including its synthetic domain credits; preview/truncate transparently instead of claiming a complete archive. Do not turn imported search URLs into the separate Past Searches store. [Current History](../../FieldKit/Sources/FieldKit/History.swift).
- Verification before shipping: actual localized Safari ZIPs with profiles; nested/favorite/Reading List HTML from each claimed source; UTF-8/entities/legacy encoding errors; malformed/oversized inputs; repeated-import idempotence; no disk/network activity in Private; cancellation/Undo; history count/date/ranking preservation; persisted cap reporting. These are acceptance criteria for a later implementation, not tests run here.

### Entitlement checklist

- Implement cold/warm HTTP/HTTPS intake and regular-tab routing; declare inbound schemes.
- Apply for **`com.apple.developer.web-browser`** for `com.connork.fieldbrowser`; configure approved signing and verify the archived entitlement/Info.plist.
- Confirm no prohibited permission keys or domain-specific Universal Link claims; validate guard behavior against requested destinations.
- Add a quiet Settings action explaining how to set Field as default, using public settings routes; check `isDefault(.webBrowser)` sparingly.
- Separately register BrowserKit activities and availability-gate transfer at **26.4**, if that phase ships. No EU alternative-engine entitlement for system WKWebView.

Authority for this checklist: [default-browser requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [request form](https://developer.apple.com/contact/request/default-browser-entitlement/), [transfer workflow](https://developer.apple.com/documentation/browserkit/transferring-browsing-data-to-another-browser).

### Products and proposed prices

All prices here are tentative proposals; nothing is configured or decided.

| Product ID | Display name | Kind | Suggested US price | Delivers |
|---|---|---|---|---|
| `com.connork.fieldbrowser.supporter` | **Field Supporter** | Non-consumable | **$9.99 once** | Bundled alternate icons and extra bar looks; list the actual set at launch |
| `com.connork.fieldbrowser.tip.small` | Small Tip | Consumable | **$0.99** | Thanks; no unlock |
| `com.connork.fieldbrowser.tip.medium` | A Little More | Consumable | **$2.99** | Thanks; no unlock |
| `com.connork.fieldbrowser.tip.large` | Generous Tip | Consumable | **$9.99** | Thanks; no unlock |

These IDs/names/prices are recommendations. Use actual localized StoreKit names/prices; expose Restore Purchases for Supporter. Enroll in Small Business before forecasting the 15% rate. Avoid subscriptions for a static local cosmetic set. All browsing, Saved/import, blocking, Private and later Tor stay free by product decision. [IAP kinds](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/), [price configuration](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/), [restore](https://developer.apple.com/documentation/storekit/appstore/sync()), [Small Business](https://developer.apple.com/app-store/small-business-program/).

### Privacy answers and manifest changes

- **Preferred 1.0 configuration:** local suggestions only pending clarification; no collection, no Purchase History declaration, no tracking; local imports/history do not change that. Publish a policy that describes Apple payment processing and open-web recipients. This is a recommendation to substantiate the label, not a declaration that the current remote-suggestion build is verified.
- **If remote suggestions remain:** resolve Apple browser-exclusion scope and recipient retention/linkage first; otherwise disclose the supported Search History collection and actual uses. Do not claim opt-in or no cookies makes it exempt. Align label, policy and manifest.
- **Required reasons:** keep existing `CA92.1`/`35F9.1`; no StoreKit/icon category. Add File Timestamp `3B52.1` and/or `C617.1` only for actual picked/internal file API use; add Disk Space `E174.1` only for an implemented capacity check. Fix stale “only pages” privacy copy in a later app round.

Sources: [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/), [required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), [current manifest](../../Field/PrivacyInfo.xcprivacy).

## Decisions for the user

These are the remaining product choices to grill against the sources above. The already-made choices (open source under the MPL-2.0, free browser, privacy free, password handoff) are not reopened.

1. **Import history at all, and how much?** Recommendation: **yes, optional and unchecked**, starting with Safari, with honest 2,000-record ranking/cap disclosure. Takeout later. Value: familiar autocomplete; cost: sensitive old history and a bulk-merge path. Evidence: [History](../../FieldKit/Sources/FieldKit/History.swift), [Safari history schema](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).
2. **Files first or BrowserKit first?** Recommendation: **Files first**, Safari ZIP and one shared HTML parser; BrowserKit next for 26.4+. It keeps the iOS 26.0 minimum and does not depend on every competitor participating. [Import manager availability](https://developer.apple.com/documentation/browserkit/bebrowserdataimportmanager).
3. **What happens to nested folders, Favorites, and unread bookmarks?** Recommendation: flatten paths; retain all links; preview optional stars; only Reading List starts unread. Field's one-level Saved model is intentional, so make the conversion visible instead of adding nested folders incidentally. [Saved](../../FieldKit/Sources/FieldKit/Saved/Saved.swift).
4. **Supporter plus tips, or one paid mechanism?** Recommendation: **both**, clearly separate: one-time Field Supporter for cosmetics; repeatable optional tips with no unlock. No subscription now. [IAP kinds](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/).
5. **Name, price, and paid scope?** Recommendation: **Field Supporter, $9.99 US once** (tentative), alternate icons and extra bar looks. Keep today's two looks and core Tidy free; decide any genuinely new Tidy conveniences only when concrete. Tip names/prices as above. [Review unlock rule](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), [pricing](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/).
6. **Remote suggestions or certainty about “Data Not Collected” at 1.0?** Recommendation: prioritize **the claim's certainty**, with local suggestions until Apple settles native autocomplete. If remote suggestions are essential, accept the evidence/label work rather than assuming all engines are anonymous. Turning them off by default alone is insufficient. [Apple disclosure guidance](https://developer.apple.com/app-store/app-privacy-details/), [Orion comparison](https://help.kagi.com/orion/getting-started/search-engine.html).
7. **Where do external links land?** Recommendation: new regular tab, including while Private is locked; queue cold-launch URLs through welcome/startup. Apply for the default entitlement for 1.0; no choice-screen launch assumption. [Apple criteria](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [EU criteria](https://developer.apple.com/support/browser-choice-screen/).
8. **Public policy/support host and release date?** Recommendation: a small stable HTTPS site with `/privacy` and `/support`, contact email, no analytics; choose the hostname before submission. Submit a featuring nomination at least three weeks ahead; ship screenshots first, preview optional. [Required support URL](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), [featuring lead time](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/).

## Couldn't verify

All uncertainties recorded **2026-10-08**:

- **Native autocomplete classification:** no explicit Apple statement settling Field's `URLSession` prefixes under the open-web exclusion, or the vendor-code definition for HTTP-only engine integration. No endpoint-specific retention, re-identification, or advertising-use guarantee for every supported engine. This is the largest unresolved privacy-label issue; comparative labels do not settle it.
- **BrowserKit on real devices:** did not compile a transfer prototype, test EU/non-EU runtime behavior, or verify Safari/Chrome/Firefox/Brave/DuckDuckGo/Edge adoption in installed current versions. The docs specify 26.4 availability and default-browser criteria, but no separate transfer entitlement or explicit region gate. Report that scope accurately rather than infer universal vendor support.
- **Local iPhone exporters:** no primary confirmation of local bookmark/history file export in current Chrome, Firefox, or Edge. No Brave history exporter verified. DuckDuckGo's HTML export is source-verified, not tested through its live UI. Negative findings are documentation limits, not exhaustive binary audits.
- **Safari fixtures and older Mac systems:** no actual export produced here. Apple's release notes establish expanded export in iOS 18.2 and macOS 15.2; Safari 18.2 being available on older macOS does not by itself prove the full ZIP UI is available there. Regional guidance supports non-EU availability, but no exhaustive region/device test was done.
- **Takeout exact packaging:** Google's vendor schema documents the history shape, but does not establish one immutable Takeout filename, all optional fields, retention coverage, or equivalence for every account. Obtain a real current Chrome-only export before promising complete history import.
- **App Store account state:** no live entitlement approval, signing profile, privacy questionnaire, IAP price availability, Small Business approval, trader status, support/policy URL, or 1.0 metadata was checked. The code readiness findings are source checks, not archive/device checks or App Review acceptance.
- **Review outcomes:** published PCalc copy and browser labels are primary vendor evidence, not private App Review reports. No phrase, icon set, entitlement request, or nomination is guaranteed approval/featuring.
- **Manifest dependency audit:** no new importer/ZIP library chosen, no privacy report generated for a new implementation. Required-reason recommendations are conditional on the APIs actually used.
