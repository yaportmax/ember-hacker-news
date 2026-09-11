# Validation record

Authoring date: September 11, 2026.

**This is not an App Store-ready certification.** No iOS binary has been compiled or executed in the authoring workspace. The environment is Ubuntu 24.04, not macOS, and has no Xcode, Apple SDK, simulator, or signing credentials.

## Completed here

| Check | Result |
| --- | --- |
| Portable Swift core compilation | Passed with Swift 6.2.3, Swift 6 language mode and strict concurrency |
| Deterministic XCTest suite | 29 tests passed, zero failures |
| Live API integration | 1 test passed separately against HN and Algolia |
| Live endpoints covered | Top, New, Best, Ask, Show, Jobs, item, comment, user, search |
| App/UI test Swift syntax | Parsed successfully with the Swift compiler; Apple-framework type checking remains unperformed |
| Xcode project structure | Parsed by an independent OpenStep parser; all references resolve |
| Target source membership | All 19 app, 2 unit-test, and 1 UI-test Swift files included in their targets |
| Scheme, Info.plist, privacy manifest | XML/plist structure checked |
| Icon assets | Three 1024 × 1024 opaque RGB icons; primary icon visually inspected |
| Release tools | Python syntax, asset/manifest checks, configuration rendering, and Linux refusal of Mac-only steps checked |

The default test run reports 30 tests with one skipped. That skipped test is the live integration test, which was explicitly enabled and passed separately. There are **30 distinct passing tests total**, not 31. Logs are included in `Release/Evidence/`.

## Still required

- Xcode compilation and Apple SDK type/availability checks for the SwiftUI app and UI tests.
- iPhone and iPad simulator execution of the six UI tests, including the accessibility audit and screenshot capture.
- Manual real-device review, Dynamic Type, VoiceOver, rotation, iPad multitasking, and long-thread scrolling/memory checks.
- Apple Developer team, registered bundle ID, certificates/profiles, signed archive, and TestFlight.
- Name availability, public support/privacy pages with the real publisher’s contact information, screenshot selection, age rating, final privacy disclosures, and App Store review.

`scripts/release.py validate` writes `Release/validation.json` only after iPhone/iPad tests and a Release device build succeed on a Mac. No such receipt is included or fabricated here. `archive` refuses to continue without a current passing receipt and completed publisher configuration.
