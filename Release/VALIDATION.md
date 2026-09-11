# Validation record

September 11, 2026. Native build and simulator validation passed. This is not App Store approval or a claim of complete real-device testing.

## Verified native run

[GitHub Actions run 6](https://github.com/yaportmax/ember-hacker-news/actions/runs/34642526701) validated commit `a5f5550b05938264df6cee2b526bccaa0800aafa` using Xcode 26.6 (17F113) on a standard `macos-26` runner.

| Check | Result |
| --- | --- |
| Static project, privacy manifest, assets | Passed |
| Portable deterministic unit tests | 29 passed, zero failures |
| iPhone simulator unit tests | 29 passed, zero failures |
| iPhone 17 Pro UI tests | All 6 passed |
| iPad Pro 13-inch (M5) UI tests | All 6 passed |
| Release build for physical iOS devices | Passed, unsigned |
| Real simulator screenshot export | Passed |

The optional live API test is skipped in default CI. It passed separately during initial authoring against HN and Algolia; that earlier result is not part of this native run. Repeated executions across platforms are not additional distinct tests.

UI tests cover bookmark restoration, search and empty results, offline relaunch, comment collapse/replies, dark-theme accessibility, and screenshots. Contrast checks exclude content obscured by the iPhone bottom floating tab bar; fully visible content and iPad top-tab layouts remain audited. Screenshots use deterministic fixtures, while normal app launches load live data.

[The unchanged CI-generated validation receipt](Evidence/github-validation.json) records the source fingerprint, toolchain, and devices. It was matched against the local source before this documentation commit. Documentation and screenshot additions do not change the validated app source. The receipt is historical evidence, not a signing credential.

## Fixes found through simulator testing

- Increased rank size and contrast, and strengthened secondary story text in both themes.
- Removed a toolbar wordmark that iOS clipped.
- Updated UI tests for iPad floating tab controls and search focus after clearing text.

[View the actual app screenshots](../docs/SCREENSHOTS.md). The gallery comes from run 5; the only subsequent source change was to the search test's focus handling.

## Remaining publishing work

- Set the real Apple Developer team and a registered bundle ID; configure signing.
- Host support and privacy pages with the publisher's contact details.
- Produce a signed archive and verify it through TestFlight on physical devices.
- Review VoiceOver, larger Dynamic Type sizes, rotation, iPad multitasking, live articles, and long discussions on devices.
- Complete App Store metadata, age rating, privacy disclosures, screenshot selection, and Apple review.

`scripts/release.py validate` writes a release receipt only after the full native gate passes. Changing source or publisher configuration invalidates that receipt. `archive` requires current validation and completed publisher configuration; it never uploads automatically.
