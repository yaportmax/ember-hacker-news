# First App Store release

The publisher approved the application and requested public release on September 13, 2026.

Status: **preparing submission; not published or submitted for review**.

- App: Ember for Hacker News, Apple ID `6811495244`, bundle `com.maxyaport.ember`.
- Version: `1.0.0`. The approved TestFlight build `5.1.0` was internal-only and cannot be submitted to customers.
- Public-release candidate: `6.1.0`, source `3192dac22d06b92e0b722f559ec39892dcae1f43`. Application source and configuration are unchanged from the approved build. Only distribution, screenshots, and documentation change.
- [Signed build/upload](https://github.com/yaportmax/ember-hacker-news/actions/runs/34772094798).
- [Current native iPhone/iPad captures](https://github.com/yaportmax/ember-hacker-news/actions/runs/34772094770).
- [Prepared store metadata](APP_STORE.md), [public support](../docs/SUPPORT.md), [public privacy policy](../docs/PRIVACY.md).
- Intended price: free. Intended release: automatic after Apple approval.

## September 13 continuation

The existing browser was authenticated as the publisher. App Store Connect showed Ember version 1.0 in Prepare for Submission. Build 6.1.0 was enabled in the build picker; older internal-only builds were disabled. Selected 6.1.0 and saved the promotional text, description, keywords, support URL, copyright, and review notes from APP_STORE.md. Cleared Sign-in required. Automatic release after approval was already selected.

App Information initially had no category, subtitle, content-rights declaration, or age rating. Entered News / Productivity and shortened the subtitle to `Stories. Discussions. No noise` after Apple rejected the original trailing-period text as too long. Clicked Save, but the subsequent browser connection failed, so those App Information fields need a fresh persistence check.

Automatic approval review rejected the attempted age-rating answers, citing insufficient verification/authorization of consequential capability disclosures, especially messaging and social-media classification. The questionnaire was canceled. Do not retry that rejected action through another interface; verify the definitions against the app and obtain the needed publisher approval before continuing. No age rating was saved by this session.

The browser subsequently returned repeated CDP refresh timeouts, including through the documented alternative DOM API. App Privacy, pricing/availability, contact details, and final submission could not be completed. The review-contact name, phone, and email fields were blank on the version page. Content-rights setup and account-level EU trader status also remain outstanding. Do not invent these details.

Downloaded and visually reviewed all eight native store captures from run 34772094770. iPad captures are 2064 × 2752, an accepted 13-inch size. iPhone captures are 1206 × 2622 (6.3-inch), which does not satisfy the required 6.5-inch/6.9-inch slot. The screenshot-only branch `release/store-screenshots` selects an available iPhone Pro Max simulator for new native captures. It does not trigger the signing/upload workflow. See Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). No screenshots have been uploaded to Apple by this session.

No review submission has been made, no new agreements accepted, and no account-specific declarations have been invented. The app is not published.

Before submission, confirm Apple processing and build eligibility, inspect the new captures, finish the privacy and age-rating questionnaires, select the build, and verify the existing contact, rights, pricing, and availability fields. Record the final review submission status here.

The `release/app-store` branch explicitly exports an App Store-eligible build. Ordinary main-branch uploads remain internal-only. Uploading does not itself submit App Review or publish the app.
