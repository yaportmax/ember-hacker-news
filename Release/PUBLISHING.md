# Publishing Ember

Native builds and simulator checks run in GitHub Actions. The repository contains source and validation evidence; producing a signed release still requires the publisher’s Apple Developer configuration and a physical-device review.

## 1. Configure identity

Use `scripts/release.py configure` with your registered bundle ID, Apple team ID, support and privacy URLs, contact email, and publisher name. The script updates `Config.xcconfig` and renders complete static pages in `Release/Web/`. Host those pages at the exact URLs you supplied and confirm they work without authentication. Maintain a support inbox and a process for acting on reports.

Check that “Ember for Hacker News” is available for your app in App Store Connect. Rename the app and update metadata if needed. The app icon is original geometric artwork; the app does not use the Y Combinator logo.

## 2. Build and validate on a Mac

Use Xcode 26 or later with an iOS 26 or later SDK. Apple has required this for submissions since April 28, 2026. The app still supports devices running iOS 17 and later because deployment target and build SDK are separate.

Run `python3 scripts/release.py validate`. Install missing iPhone and iPad simulator runtimes if the command asks. Address every build, unit test, UI test, and accessibility audit failure; do not bypass the checks by manufacturing a validation receipt.

The script stores `.xcresult` bundles in `build/`, builds Release for a physical-device target without signing, and records the source fingerprint only after success. It does not prove physical-device behavior or App Review acceptance.

## 3. Manual device review

Use at least one real iPhone and, because this app supports iPad, an iPad. Also check the oldest supported iOS runtime available to you.

- All six feeds, first and later pages, pull-to-refresh, slow connections, airplane mode, and reconnection.
- Stories with no article URL, jobs, polls, deleted comments, and very large threads.
- Expand/collapse, reply loading, author profile, report actions, block and unblock.
- Search typing/deleting quickly, sort/date filters, empty results, and keyboard dismissal.
- Save/unsave, relaunch, clear history, and change theme with a discussion open.
- Reader and default-browser options; sign-in/vote/reply/submit through HN.
- Share sheet and `emberhn://item/8863`. Universal links for `news.ycombinator.com` are not claimed because you do not control that domain.
- VoiceOver reading order, accessibility text sizes through the largest size, Bold Text, Increase Contrast, Reduce Motion, landscape, and iPad split-screen widths.
- Confirm no Debug fixtures appear in Release. Check memory/scrolling behavior with Instruments in a long discussion.

## 4. Screenshots and store information

Use real simulator/device captures. [The gallery](../docs/SCREENSHOTS.md) contains direct exports from the native UI-test walkthroughs. These show deterministic sample stories; normal launches use live data. Review the captures before selecting illustrative store screenshots, or capture the live app instead.

Export existing results with:

```sh
python3 scripts/release.py screenshots --result build/iPhone-TIMESTAMP.xcresult
```

Choose appropriate iPhone and iPad simulator sizes from Apple's current screenshot requirements; do not stretch smaller screenshots. Complete the App Store record using `APP_STORE.md`, hosted privacy/support URLs, publisher contact, rights to display the aggregated content, and the current age-rating questionnaire. Content comes from HN; review Apple’s user-generated content requirements and the publisher’s moderation responsibilities before submitting. Reporting solely to HN does not remove the publisher’s responsibilities.

Privacy manifest: no tracking domains, no tracking SDKs, no developer-operated data collection; UserDefaults reason `CA92.1` covers on-device preferences. The final App Store privacy answers still require review of Firebase-hosted API traffic, Algolia query handling, and any services added after this package. The app only uses operating-system encryption; confirm the export-compliance answer for your actual release.

## 5. Archive and submit

Run `python3 scripts/release.py archive` after validation. Xcode must be signed into your Apple Developer account with the appropriate certificates and profiles. Add `--allow-provisioning-updates` only if you want Xcode to manage profiles through your account.

The script exports an `.xcarchive` and `.ipa` locally. It never uploads. Upload using Xcode Organizer or Transporter, run a TestFlight pass, complete App Store Connect fields, and submit for review. Increment `CURRENT_PROJECT_VERSION` for each upload and revalidate changed source/configuration.

## Official references

- [Apple submission requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Hacker News API](https://github.com/HackerNews/API)
- [Algolia HN Search](https://hn.algolia.com/api)

Reviewed September 11, 2026. Recheck time-sensitive submission requirements at upload time.
