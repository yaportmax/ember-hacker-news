# Large discussion loading — September 13, 2026

The reported thread, [A misalignment of AI in mathematics](https://news.ycombinator.com/item?id=49662371), had 1,183 comments in the supplied screenshot. The previous implementation waited for every request before displaying any comments. It also traversed the complete tree and parsed all comment HTML whenever scrolling updated the next-comment overlay. A lazy view did not make that repeated data preparation lazy.

## Changes

- Show the first readable comment as soon as it arrives. Continue loading the whole discussion ahead of scrolling, with eight requests at most.
- Prioritize discovered replies. Publish only a continuous prefix of HN's reading order, so later-arriving replies cannot insert themselves above comments already shown. Background updates are coalesced to at most twice a second after the first comment.
- Parse HTML away from the main actor and retain the prepared formatting. Rebuild the visible rows only for data, collapse, or block changes. The jump control examines layout anchors without parsing or flattening the tree.
- Reuse prepared discussions within the session for two minutes, bounded to four discussions and 8,000 comments. Explicit refresh still fetches fresh content. This cache is not an offline download feature.
- Keep readable comments after a failed or cancelled request. A retry continues to respect collapsed threads. One quiet footer can appear if reading reaches the end of the loaded content; there are no per-reply spinners.

## Verification

Source: `d6e8e26639d996f6ebeef18e22b14a6602db1092`.

[Native review run](https://github.com/yaportmax/ember-hacker-news/actions/runs/34757047743).

The targeted checks cover early display while a reply is deliberately held, stable comment order, collapse during background loading, partial failures, cancellation, cache reuse, explicit refresh, and 1,200-comment row-access cost. Native iPhone/iPad checks exercise a 1,200-comment fixture, scrolling metrics, the next-comment arrow, reopening, and collapse position, plus the existing link and reading-control checks.

Both native jobs passed, including the 1,200-comment scrolling test and the existing reading/link interactions. All 40 core/live API tests passed. Reading the prepared 1,200-row array 10,000 times took 0.00166 seconds in the core check. This measures removal of scroll-time tree work, not network speed or frame rate.

The native scroll-deceleration measurements averaged 2.435 seconds on iPhone and 2.415 seconds on iPad, with low variation across three swipes. These are gesture durations, not a frames-per-second measurement. Actual captures were inspected for readable content, working navigation, and the absence of inline reply loaders.

## Settings and 14-point defaults

After the performance run, the user requested a broader spacing review and 14-point defaults. The subsequent source is `63da3ee0d65f79ec5b2bd989f0ab1f899340104c` ([native settings run](https://github.com/yaportmax/ember-hacker-news/actions/runs/34758147319)).

- Comment text size, row spacing, and reply indentation default to 14 points. Reset restores those values. All three sliders place 14 at their center; the text-size slider retains the existing larger sizes up to 28.
- Existing values matching the old defaults migrate once. Other explicit custom values remain intact.
- The live samples always contain multiple lines so the effect of line spacing is visible, including at smaller fonts and on iPad.
- Comment row padding now uses the same component in discussions, extra comment feeds, and previews. Reply indentation measures the text column; zero removes the indentation and its guide.
- Tests compare minimum and maximum line/row spacing, font size, indentation, and actual reading-screen dimensions. They also exercise all fonts, resets, persistence, themes, reading preferences, storage confirmations, and blocking.

The iPad settings run passed all three native tests. Min/max line spacing changed both the preview and actual reading-screen frames; size, row padding, indentation, resets, saved preferences, large text, and landscape checks passed. On iPhone, both typography tests, large-text/landscape, reading preferences, reporting/blocking, article/comment interactions, and the 1,200-comment responsiveness check passed. The storage test missed its initial navigation tap and never reached Settings; the unchanged isolated [iPhone storage review](https://github.com/yaportmax/ember-hacker-news/actions/runs/34759088111) passed, including confirmation, retained bookmark, and empty history. The iPad storage run reached confirmation but its tab helper then selected a hidden duplicate Saved tab (reported hit point `{-1, -1}`). That test helper now selects a hittable tab; this helper-only adjustment has not had another native run. The completed iPad typography and reading checks remain valid. Two of the iPad captures contained incomplete display frames, so a short follow-up uses application screenshots after the compositor settles: source `0cd71d30d12f994d16922c4bab0b203e79d6a76d`, [capture run](https://github.com/yaportmax/ember-hacker-news/actions/runs/34758839751). The follow-up passed on both devices and the inspected discussion frames rendered fully. It changes only test/capture code. Fixture timings are not measurements of the user's connection or physical iPhone.

## TestFlight

Version **1.0.0 (5.1.0)** is available in Max's private internal group. The [upload record](../../Release/testflight-5.1.0-upload.json) records source `7e0ba1bba4e95181ca516e72efc27cfce1b47901` and Apple's `VALID` / `IN_BETA_TESTING` response at 13:17 UTC. Application code is identical to the native settings review; later commits add only capture and isolated-test workflow support. The final documentation/test-helper commit skips redundant CI and upload because it does not change the shipped application. The signing/upload run also passed all 40 core/live API tests.

## Native captures

These are unedited native simulator captures, not design mockups. The iPad defaults image is from the main settings run; the other images are from the settled-frame follow-up with identical application code.

| Centered 14-point defaults | iPhone | iPad |
| --- | --- | --- |
| Text size, row spacing, and reply indentation | [Capture](spacing-iphone-defaults.png) | [Capture](spacing-ipad-defaults.png) |

| Discussion line spacing | iPhone |
| --- | --- |
| Minimum | [Capture](spacing-iphone-lines-min.png) |
| Increased | [Capture](spacing-iphone-lines-max.png) |

[Settled iPad discussion](spacing-ipad-lines-min.png). The frame comparisons verify a real layout change.

## References

[The official HN API](https://github.com/HackerNews/API) exposes individual items and ranked child IDs. [Apple's SwiftUI performance guidance](https://developer.apple.com/videos/play/wwdc2023/10160/) explains why expensive body computations affect responsiveness.
