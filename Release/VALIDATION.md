# Validation record

September 12, 2026. Native build and simulator validation passed for the reading-experience refinement. Signing and physical-device review remain.

## Verified native run

[GitHub Actions run 34704411398](https://github.com/yaportmax/ember-hacker-news/actions/runs/34704411398) validated commit `0d43f594fe682877b809b3f40c1cee6761144ec5` using Xcode 26.6 · Build version 17F113 on standard `macos-26` runners.

| Check | Result |
| --- | --- |
| Static project, privacy manifest, assets | Passed |
| Portable deterministic core tests | 29 passed, zero failures |
| Live API integration test | Passed: all feeds, story, comments, profile, search |
| iPhone simulator unit tests | 29 passed, zero failures; optional live test skipped here |
| iPhone 17 Pro UI tests | All 13 passed |
| iPad Pro 13-inch (M5) UI tests | All 13 passed |
| Release build for physical iOS devices | Passed, unsigned |
| Simulator screenshot export | 39 captures per device |

The iPad job was retried on unchanged source after its first attempt timed out while starting the native Safari service. The successful iPhone and core jobs were retained. The retry passed; physical-device browser startup remains part of the TestFlight review.

Repeated test executions across platforms are not additional distinct tests. The live service test is explicitly enabled in the core CI job; it remains opt-in for local package tests.

UI checks cover navigation, feeds, article/title/menu browser entry and return, bookmarks across relaunch, search and empty results, offline relaunch, comment collapse/replies, profiles, reporting and unblocking, jobs, polls, compact rows, reading preferences, storage confirmation, dark-theme accessibility, large text, and rotation captures.

Contrast checks exclude content obscured by the iPhone bottom floating tab bar; fully visible content and iPad top-tab layouts remain audited. A second, documented exception covers only the two reviewed empty native search prompts in dark mode on iOS 26: their captured foreground/background colors measured 5.93:1 despite the automated warning. Entered search text remains in scope. See the design review for the inspected captures and calculation. Decorative separators, source labels, and author touch areas were corrected after inspecting actual failure captures. UI-test preferences reset normally instead of being locked through launch arguments, and switch changes are asserted explicitly.

[The unchanged CI-generated receipt](Evidence/github-validation.json) was matched against the local source fingerprint before this documentation commit. Documentation and screenshot additions do not change the validated app source. The receipt is evidence of testing, not a signing credential.

[View all actual app screenshots](../docs/SCREENSHOTS.md) and the [design review](../docs/review/AUDIT.md). The gallery is exported directly from this run using deterministic fixtures; normal app launches load live data.

## Remaining publishing work

- Configure the real Apple Developer team and registered bundle ID.
- Host support and privacy pages with the publisher's contact details.
- Produce a signed archive and review the app through TestFlight on physical devices, including VoiceOver, live article behavior, long discussions, and iPad multitasking.
- Complete App Store metadata, age rating, privacy disclosures, screenshot selection, and Apple review.

`scripts/release.py validate` writes a receipt only after its native gate passes. Source or publisher configuration changes invalidate that receipt. `archive` requires current validation and completed publisher configuration; it never uploads automatically.
