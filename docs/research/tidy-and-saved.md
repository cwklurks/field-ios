# Field: on-device tab sorting and saved pages

Researched 2026-09-25

Sources are Apple docs and other primary pages fetched on that date unless noted. Field is on-device only; section 3 records the cloud option that was considered and declined. The last section lists what could not be verified.

## 1. Apple Foundation Models framework (on-device)

**API.** `SystemLanguageModel.default` is the on-device model. Other pieces:

- `LanguageModelSession(model:tools:instructions:)`, then `respond(to:generating:options:)` or `streamResponse`.
- `@Generable` / `@Guide` give guided generation through constrained decoding. Guides include `.count`, `.maximumCount`, `.range`, `.anyOf`, `.pattern`. `DynamicGenerationSchema` builds a schema at runtime, for example `anyOf` a user's folder names.
- `Tool` protocol for tool calling; Apple advises 3-5 tools at most.
- `GenerationOptions(sampling: .greedy)` for deterministic output.
- `prewarm(promptPrefix:)` preloads the model.

Sources: https://developer.apple.com/documentation/foundationmodels, https://developer.apple.com/documentation/foundationmodels/generable, https://developer.apple.com/documentation/foundationmodels/tool

**Context window.**

- TN3193 and "Managing the context window" say **4096 tokens per session**. That covers instructions, prompt, schema and output together.
- iOS 26.4 added `contextSize` and `tokenCount(for:)`, back-deployed to 26.0.
- The WWDC26 session sample prints `contextSize // 8192` and says to "adapt your app to the hardware it's running on". So read `contextSize` at runtime rather than hard-coding a number.
- Going over the limit throws `contextSizeExceeded` (called `exceededContextWindowSize` in the 26.0 API).

Sources: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window, https://developer.apple.com/documentation/foundationmodels/managing-the-context-window, https://developer.apple.com/videos/play/wwdc2026/241/

**Speed.**

- The only numbers Apple has published are for the 2024 model on iPhone 15 Pro: about 0.6 ms per prompt token before the first token, then about 30 tokens/s (https://machinelearning.apple.com/research/introducing-apple-foundation-models).
- For 30 tabs that means roughly 1 s to read the prompt plus a few seconds to generate about 200 output tokens. Stream the result and call `prewarm` when the tab switcher opens.
- Background apps can be rate-limited (`rateLimited`).

**Models and availability.**

- iOS 27 ships "AFM 3". `SystemLanguageModel.variant` is `.core3` (3B dense) or `.coreAdvanced3` (20B sparse, 1-4B active) (https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models).
- Supported iPhones: iPhone 15 Pro/Pro Max, all iPhone 16 models and later (16e, 17, Air, 17e, 18 Pro).
- Apple Intelligence languages: English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (Simplified and Traditional), Japanese, Korean.
- Not available in mainland China. Needs up to 8-14 GB of storage (https://support.apple.com/en-us/121115).
- iOS 27 still runs on iPhone 11 through 15 Plus, which have no model. A large share of Field's users need the fallback.

**When unavailable.** `availability` returns `.available` or `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`. `modelNotReady` means the model is still downloading. Also check `supportsLocale()`, because unsupported languages throw `unsupportedLanguageOrLocale` (https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel, https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models).

**Guardrail false positives.** These matter for classifying arbitrary web page titles.

- Both input and output are checked, and a failure throws `guardrailViolation`.
- The model can also throw `refusal` during guided generation.
- `.permissiveContentTransformations` does **not** help here. For non-String output it "behaves the same way as default".
- Apple says it reduced false positives in 26.4 and is making "even more improvements in iOS 27". A developer-forum thread reports a benign query about snooker player Judd Trump being blocked (https://developer.apple.com/forums/thread/792908).
- Expect adult, violent, drug and news titles to trip the checks sometimes. Catch the error per batch, split the batch in half to find the offending tab, and route that tab to the fallback. Never send private-mode tabs to the model.

Sources: https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output, https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations

**New in iOS 27** (WWDC26 session 241, https://developer.apple.com/videos/play/wwdc2026/241/):

- Rebuilt on-device model with better tool calling.
- Image input.
- `PrivateCloudComputeLanguageModel`: 32K context and reasoning levels. It needs a managed entitlement, each user gets a daily quota, and requests leave the device, so it is out of scope for Field (https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute).
- The `LanguageModel` protocol, so other models can back a `LanguageModelSession`.
- `DynamicProfile`, an Evaluations framework, and an open-sourced framework core.

**Sketch.** Not compiled. The `tokenCount` overload that takes a `Prompt` is described in TN3193, but only the `Instructions` signature appears on the reference page. `merge` and `EmbeddingFallback` are placeholders.

```swift
@Generable struct TabPlan {
  @Guide(description: "Topic groups", .maximumCount(8)) var groups: [Group]
  @Generable struct Group {
    @Guide(description: "1-3 word topic, no emoji") var name: String
    var ids: [Int]
  }
}
struct TabInfo { let id: Int; let title: String; let host: String }

func render(_ t: [TabInfo]) -> String {
  t.map { "\($0.id) | \($0.host) | \($0.title.prefix(70))" }.joined(separator: "\n")
}

func batches(_ tabs: [TabInfo], _ m: SystemLanguageModel) async throws -> [[TabInfo]] {
  let budget = m.contextSize / 2          // rest for instructions, schema, output
  var out: [[TabInfo]] = [], queue = [tabs]
  while let c = queue.popLast() {
    if c.count == 1 || (try await m.tokenCount(for: Prompt(render(c)))) <= budget { out.append(c) }
    else { let mid = c.count / 2; queue += [Array(c[mid...]), Array(c[..<mid])] }
  }
  return out
}

func suggest(_ tabs: [TabInfo]) async throws -> [TabPlan.Group] {
  let m = SystemLanguageModel.default
  guard m.isAvailable, m.supportsLocale() else { return EmbeddingFallback.cluster(tabs) }
  var groups: [TabPlan.Group] = []
  for batch in try await batches(tabs, m) {
    let s = LanguageModelSession(model: m, instructions:   // fresh context per batch
      "Group browser tabs by topic or task. Every id goes in exactly one group; leftovers go in \"Other\".")
    let prompt = "Reuse these names when they fit: \(groups.map(\.name))\nid | host | title\n\(render(batch))"
    do {
      let plan = try await s.respond(to: prompt, generating: TabPlan.self,
                                     options: .init(sampling: .greedy)).content
      groups = merge(groups, plan.groups, validIDs: Set(batch.map(\.id)))  // drop invented or duplicate ids
    } catch { groups = merge(groups, EmbeddingFallback.cluster(batch), validIDs: Set(batch.map(\.id))) }
  }
  return groups
}
```

At about 30 tokens per tab, 30 tabs come to roughly 1.5K tokens in total, which fits in one call. Chunking only starts at around 60-80 tabs with a 4K window (an estimate). Guided generation guarantees valid structure, not valid IDs, so always check the IDs against the real tabs.

## 2. Fallback without Apple Intelligence

- **`NLEmbedding.sentenceEmbedding(for:)`** returns 512-dimensional vectors. It covers only English, Spanish, French, German, Italian, Portuguese and Simplified Chinese, and returns `nil` for other languages. In the WWDC20 session Apple itself suggests running clustering algorithms on these vectors (https://developer.apple.com/videos/play/wwdc2020/10657/). It is available on iOS 14+ and works on every device (https://developer.apple.com/documentation/naturallanguage/nlembedding, https://developer.apple.com/documentation/naturallanguage/finding-similarities-between-pieces-of-text).
- **`NLContextualEmbedding`** (iOS 17+) is a BERT-style model that gives one vector per token and needs an asset download. Apple's docs say to use `NLEmbedding` for semantic similarity, so it is a poor fit here (https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding).
- **Recipe:**
  1. Run heuristics first: same registrable domain (needs a bundled public-suffix list), exact duplicate URLs, and a small table of known hosts (github.com → Code, etc.).
  2. Embed "title — host".
  3. Cluster with average-linkage agglomerative clustering on cosine distance, using a threshold cut rather than a fixed k.
  4. Name each cluster from its top TF-IDF title terms, or the dominant host.
- **Cost:** negligible. For 30-200 tabs the O(n²) clustering is trivial, and there is nothing to download.
- **How good it is:** decent at grouping by site or domain, weak on intent. It will not see that a flights page and a hotels page belong to the same "Lisbon trip". Titles are short and noisy.
- **Evidence from Firefox:** Mozilla found DBSCAN clustering "insufficient" and switched to logistic regression anchored on a group the user had already started, an 18% improvement (https://blog.mozilla.org/en/firefox/ai-tab-groups/). So "add similar tabs to this group" works better than grouping everything from scratch.
- No published benchmark of `NLEmbedding` quality was found.

## 3. Cloud option

A cloud model (Claude via the Anthropic API) was considered and declined, because nothing may leave the phone.

## 4. UX patterns in shipping browsers

- **Safari iOS 27** has built-in Apple Intelligence tab "topics" (https://support.apple.com/guide/iphone/organize-your-tabs-with-tab-groups-iph3028ebf68/ios).
  - Topics are a **non-destructive view** in the tab screen. From a topic you can Move Tabs to a Tab Group, Close Tabs, or Copy Links.
  - Each topic has "Looks Good / Something Isn't Right" feedback, and a "Never" switch turns the feature off.
  - Bookmarks and Reading List items are auto-grouped into topics once three or more are related (https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/ios).
  - This is now the baseline Field's users will compare against.
- **Firefox desktop (141+):** opt-in, downloads two local models on first use (https://blog.mozilla.org/en/firefox/ai-tab-groups/).
  - Group names come from TF-IDF keywords plus 3 sample titles, fed to a distilled T5 model (57 MB, int8).
  - "Suggest more tabs" uses MiniLM embeddings with a logistic-regression similarity score.
  - Firefox 141 users blamed smart tab groups for CPU and battery spikes; Mozilla said a different on-device feature caused them (https://www.tomshardware.com/tech-industry/artificial-intelligence/new-local-ai-integration-into-firefox-spurs-complaints-of-cpu-going-nuts-chip-and-power-spikes-plague-new-version-141-x). Lesson: run only when the user asks.
- **Chrome Tab Organizer** (desktop, cloud): "Organize similar tabs" suggests groups with names and emoji. Page titles, URLs and tab group data are sent to Google (https://blog.google/products-and-platforms/products/chrome/google-chrome-generative-ai-features-january-2024/, https://support.google.com/chrome/answer/14519765).
- **Edge "Organize tabs":** shows a preview where you can rename, recolor and move tabs, then confirm with "Group tabs". Microsoft doesn't say whether it runs locally or in the cloud (https://blogs.windows.com/msedgedev/2024/02/29/ai-powered-tools-in-edge/, https://www.windowslatest.com/2026/02/26/i-tested-microsoft-edges-ai-tab-organizer-and-its-shockingly-good/).
- **Opera Tab Commands:** only the typed command goes to the server; tab data stays local. It reports what it did and offers **keep or undo** (https://blogs.opera.com/desktop/2025/03/ai-tab-commands-in-opera-one/).
- **Arc Tidy Tabs:** broom button once there are more than 6 Today tabs; uses OpenAI; applies immediately, and you fix it by dragging (https://tidbits.com/2024/02/15/arc-gains-instant-links-tab-grouping-and-arc-search-iphone-app/, https://resources.arc.net/hc/en-us/articles/19335160678679-Arc-Max-Boost-Your-Browsing-with-AI).
- **Firefox iOS:** tabs unviewed for 14 days move to a collapsed "Inactive Tabs" section. Users filed "terrible idea, how to disable" issues on GitHub (https://support.mozilla.org/en-US/kb/use-tabs-firefox-ios, https://github.com/mozilla-mobile/firefox-ios/issues/10686).

**What feels good:** you trigger it yourself; you see a preview before anything moves; names are short and specific ("ThinkPad shopping" rather than "Shopping"); undo is one tap; and it's non-destructive (a view, not a move).

**What annoys:** grouping or archiving that happens automatically and can't be turned off, background CPU use, generic names, and closing tabs with no way back.

## 5. Bookmarks on mobile

- **Safari:** four concepts (Bookmarks with folders, Favorites, Reading List, Tab Groups with per-group Favorites). Powerful, but confusing (https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/ios, https://support.apple.com/guide/iphone/save-pages-to-a-reading-list-iph1a4721132/ios).
- **DuckDuckGo:** Favorites are simply bookmarks with a flag, shown on the New Tab page. The clearest model of the group (https://duckduckgo.com/duckduckgo-help-pages/sync-and-backup/syncing-favorites).
- **Firefox iOS:** Bookmarks plus Reading List, with homepage Shortcuts (frequent and recent sites) and recent saves (https://support.mozilla.org/en-US/kb/customize-firefox-home-ios, https://support.mozilla.org/en-US/kb/add-web-pages-your-reading-list-firefox-ios).
- **Arc Search:** favorites/pins with a star instead of bookmarks, plus an archive list sorted by date (https://tidbits.com/2024/02/15/arc-gains-instant-links-tab-grouping-and-arc-search-iphone-app/).
- **Orion:** bookmarks, favorites and reading list, with tab groups ("Named Windows") synced separately (https://help.kagi.com/orion/features/tab-groups.html).

**Clearest minimal model:** one concept, "Saved".

- A saved page has URL, title, date saved, an optional folder, and an optional star.
- Starred pages are the favorites grid on the new tab page.
- Instead of a separate Reading List, use a "Read later" smart filter (saved, never reopened).

## 6. Recommendation for Field

1. **Data model:**
   - Store Saved pages as above.
   - Tab groups are live sets of open tabs; add "Save group as folder" and "Open folder as tabs" to bridge them.
   - Record `lastViewed` for every tab.
2. **Tidy button:**
   - Shown in the tab switcher once there are 8 or more tabs. Nothing runs automatically.
   - Engines: Foundation Models if `isAvailable && supportsLocale()`; otherwise `NLEmbedding` + agglomerative clustering + host heuristics.
   - Results appear as a preview sheet: editable names, a checkbox per tab, drag between groups. Then Apply, followed by an Undo toast. Offer "Add similar tabs" for an existing group (the Firefox pattern).
3. **Stale tabs:**
   - Use deterministic rules, no AI: unviewed for 14 days (configurable) or duplicate URLs.
   - Show a banner: "12 tabs untouched for 2 weeks — Review / Close all".
   - Closed tabs go to Recently Closed, so the action is always reversible. Never archive silently.
4. **Folder suggestion when saving:**
   - Pick the folder whose saved pages are most similar (cosine distance to the folder's average `NLEmbedding` vector). This is instant, works on every device, and needs no LLM.
   - Use Foundation Models with a `DynamicGenerationSchema` `anyOf` over existing folder names only to suggest a *new* folder name.
5. **Hygiene:**
   - Never process private tabs.
   - Label the button as on-device.
   - Version prompts per model (https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) and test on iOS 26.x and 27.

## Could not verify

- **Context size and speed:** the on-device context is documented as 4096, but the WWDC26 sample shows 8192. There are no official speed numbers for AFM 3.
- **Tab-title benchmarks:** none published for either `NLEmbedding` or Apple's model.
- **Blocked pages:** Arc's and Firefox's help pages returned 403 or bot walls, so Arc Search's default archive interval and the Firefox iOS inactive-tab details come from search snippets and TidBITS.
- **Chrome's help page:** the Tab Organizer article has moved; the data-collection sentence comes from a search snippet.
- **Guardrail forum example:** the Judd Trump false positive comes from a search snippet of the forum thread, not a direct read.
- **Code sketch:** not compiled. The `tokenCount(for: Prompt)` overload and `merge` / `EmbeddingFallback` are placeholders.
