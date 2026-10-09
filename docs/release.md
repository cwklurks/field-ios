# Releasing to TestFlight

Release 1 in [PLAN.md](PLAN.md) puts Field on friends' phones through TestFlight. The build side is one script, `scripts/release/archive.sh`. Everything in App Store Connect is done by hand, once, by the account holder. Nothing in this repo creates records there or uploads without `--upload`.

## What's already in place

| App Store Connect wants | Where it is |
|---|---|
| A 1024 px icon with no alpha | `Field/Assets.xcassets/AppIcon.appiconset`, with a dark variant |
| The export compliance answer | `ITSAppUsesNonExemptEncryption = NO` in project.yml. Field uses only Apple's own encryption (HTTPS through WebKit), so it's exempt. Tor (release 2) changes the answer |
| Purpose strings | Camera, microphone and local network in project.yml, each saying it's only when a page asks |
| A privacy manifest | `Field/PrivacyInfo.xcprivacy`: no tracking, no data collected, and two required-reason APIs: UserDefaults (`CA92.1`, the app's own settings) and system boot time (`35F9.1`, `CACurrentMediaTime` timing taps on the phone). Grep again when a milestone adds file timestamps, disk space or keyboard APIs |
| The MIT notice for Search | Settings › About › Built on Search by Office Commun, which shows NOTICE.md in full |
| Version and build | Version **0.1** (`MARKETING_VERSION`); the build number is the commit count, set by the script |

Version 0.1 says "early" to testers and leaves 1.0 for the App Store. TestFlight builds are grouped under their version, so every Release 1 build sits under 0.1 until the version is raised.

## Once, before the first upload

1. **Sign Xcode in.** Xcode › Settings › Accounts › `+` › Apple Account, with the Apple ID of team Connor Klann (H435XM227M). The script's export needs it: the first time, Xcode makes the Apple Distribution certificate and the App Store profile itself. Without it the export fails with "No Accounts".

2. **Create the app record.** At [appstoreconnect.apple.com](https://appstoreconnect.apple.com), go to Apps › `+` › New App:
   - Platforms: iOS
   - Name: **Field Browser**. Names are unique across the whole App Store, so if it's taken, try "Field: Quiet Browser" or "Field Web". This is the store name; the home screen still says Field.
   - Primary language: English (U.S.), or your own English
   - Bundle ID: **com.connork.fieldbrowser**. It's in the list because Xcode's automatic signing registered it. If it isn't, add it under Certificates, Identifiers & Profiles › Identifiers first.
   - SKU: **field-ios**. It's private and never shown; any unique string will do.
   - User Access: Full Access

3. **Fill the privacy label.** Under the app, go to App Privacy › Get Started. Answer **"No, we do not collect data from this app"**, then Publish. The label then reads "Data Not Collected". It's true as long as nothing but the pages you open leaves the phone, so answer again before anything else does (Tor bridges, list updates). Search suggestions already do: what is typed goes from the phone to the search engine the person chose, never to us. Unsubmitted prefixes are not saved; submitted searches are kept locally outside Private. Check App Privacy's definitions against that before answering, and say so in the policy (docs/privacy.md does). App Privacy also asks for a privacy policy URL. The App Store needs one; for TestFlight, fill it in if asked. A short page saying Field collects nothing will do.

4. **Add yourself as an internal tester.** Open TestFlight › Internal Testing › `+`, make a group (for example "Me") and add yourself. Internal testers must be users on the team, and you already are as Account Holder. Internal builds need no review and arrive as soon as they've processed.

5. **Install TestFlight** from the App Store on the iPhone. Sign in with the same Apple ID, and accept the invitation from the email or from TestFlight itself.

## Each upload

Commit first, since the build number is the commit count, then:

```sh
scripts/release/archive.sh --upload
```

The script:
- runs `xcodegen generate`;
- archives a Release build into `build/release/Field.xcarchive`;
- checks the signature (the stale-profile trap from device installs);
- exports with `scripts/release/ExportOptions.plist`, switched to upload.

App Store Connect processes the build in about 5 to 30 minutes, then it shows in TestFlight and emails you. It asks no export compliance question, because of the Info.plist key.

Without `--upload`, the script stops at `build/release/export/Field.ipa`. It checks that the .ipa is signed with Apple Distribution and carries an App Store profile (no debugger entitlement, no device list), and prints the version, build and profile. Use that to check a build without sending it.

A build number can be used only once per version. To upload the same commit again, give it a higher number: `scripts/release/archive.sh --upload --build 7.1`, or anything above the last one.

## Friends: external testers

Friends who aren't on the team are external testers. The first build of each version goes through Beta App Review.

1. TestFlight › External Testing › `+`, make a group, for example "Friends".
2. Add them by email, or turn on a public link and send that. Up to 10,000 testers.
3. Fill Test Information (TestFlight › Test Information):
   - a beta app description ("A small, fast iPhone browser. Ads and trackers are blocked before the page draws.");
   - a feedback email;
   - contact details;
   - "Sign-in required" off.
4. Add the build to the group, write What to Test, and Submit for Review. The review usually takes about a day. Later builds of the same version often go out without a full review.

Testers install from TestFlight's invitation, and each build expires after 90 days. Feedback, with screenshots, arrives under TestFlight › Feedback.

## Default browser

Field takes web links from other apps already: `http` and `https` are declared under `CFBundleURLTypes` in `Field/Info.plist`, and `onOpenURL` hands them to `Arrivals`. Until Apple grants the managed entitlement `com.apple.developer.web-browser`, iOS never offers Field as the default, so taps in Mail still go to Safari. The entitlement can't be added early: a profile without it can't sign the app, and the archive fails. It's prepared and off:

- `Field/DefaultBrowser.entitlements` holds the key.
- `project.default-browser.yml` points `CODE_SIGN_ENTITLEMENTS` at it and sets `FIELD_DEFAULT_BROWSER`, which shows Settings › Default browser (the system's Default Apps, and whether Field is the default). `project.yml` includes it only when the environment says `FIELD_DEFAULT_BROWSER=YES`, so a plain `xcodegen generate` and the archive script leave all of it out.

### Asking Apple, once

1. Fill in Apple's [Default browser entitlement request form](https://developer.apple.com/contact/request/default-browser-entitlement/) as the Account Holder, for bundle ID **com.connork.fieldbrowser**, team **H435XM227M**. Leave the app-installation entitlement unticked: that's for installing apps from marketplaces, not for being the default. The criteria are in [Preparing your app to be the default web browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser); the evidence for each is in [the research](research/switching-and-supporter.md#does-field-qualify-code-check-2026-10-08).
2. Wait for Apple's email. Managed capabilities are listed on the App ID once granted: Certificates, Identifiers & Profiles › Identifiers › com.connork.fieldbrowser › Additional Capabilities ([Apple's help](https://developer.apple.com/help/account/capabilities/capability-requests/)). Turn it on there if it isn't already.

### Switching it on

For one archive, before Apple's approval is permanent in the project:

```sh
FIELD_DEFAULT_BROWSER=YES scripts/release/archive.sh
```

To keep it on, delete the `enable:` line under `include:` in `project.yml`, and run `xcodegen generate`. Automatic signing fetches a profile with the entitlement (`-allowProvisioningUpdates` in the script). A development build on a phone needs it in the development profile too; the simulator ignores it.

### Checking the archive

Archive without `--upload`, then:

```sh
app=build/release/Field.xcarchive/Products/Applications/Field.app
# The entitlement is signed in: prints "true".
codesign -d --entitlements :- "$app" | plutil -extract com\.apple\.developer\.web-browser raw -o - -
# And the exported profile carries it: prints "true".
unzip -oq build/release/export/Field.ipa -d /tmp/field-ipa
security cms -D -i /tmp/field-ipa/Payload/Field.app/embedded.mobileprovision > /tmp/field-profile.plist
/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.web-browser" /tmp/field-profile.plist
# http and https are declared, and nothing else: field-test is Debug's alone.
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$app/Info.plist"
# None of the keys Apple rejects in a browser: prints nothing.
for key in NSPhotoLibraryUsageDescription NSLocationAlwaysUsageDescription NSLocationAlwaysAndWhenInUseUsageDescription \
    NSLocationUsageDescription NSHomeKitUsageDescription NSBluetoothAlwaysUsageDescription \
    NSHealthShareUsageDescription NSHealthUpdateUsageDescription; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$app/Info.plist" >/dev/null 2>&1 && echo "rejected key: $key"
done
```

An archive without the switch fails the first check with "No value at that key path", and its Settings has no Default browser section.

Then on the phone, from TestFlight: Settings › Apps › Default Apps › Browser App lists Field. Choose it, tap a link in Notes and in Mail, with Field closed, in the background, and with Private locked. Each opens in a new tab of your own, and Private stays locked.

## When something goes wrong

- **"No Accounts" or "No profiles for 'com.connork.fieldbrowser'".** Xcode isn't signed in (step 1).
- **"The bundle version must be higher".** That build number was already uploaded; use `--build`.
- **The signature check fails.** An incremental build swapped in a new profile without re-signing. The script stops before exporting. Point `-derivedDataPath` at a fresh folder, or delete `build/release/Build`, then run it again.
- **An email about a missing purpose string (ITMS-90683).** Add the key it names to project.yml as `INFOPLIST_KEY_<key>`, in the same voice as the others.
