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

Downloaded and visually reviewed all eight native store captures from run 34772094770. iPad captures are 2064 × 2752, an accepted 13-inch size. iPhone captures are 1206 × 2622 (6.3-inch), which does not satisfy the required 6.5-inch/6.9-inch slot. The screenshot-only branch `release/store-screenshots` selects an available iPhone Pro Max simulator for new native captures. It does not trigger the signing/upload workflow. See Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). No screenshots have been uploaded to Apple by this session. Corrected capture run [34774575947](https://github.com/yaportmax/ember-hacker-news/actions/runs/34774575947) is in progress; its artifacts still need download, dimension/visual checks, and Apple upload. Screenshot workflow changes are on `release/store-screenshots` at `d8b3dad0515dce13d971083d70c8e1048da4237f`.

No review submission has been made, no new agreements accepted, and no account-specific declarations have been invented. The app is not published.

Before submission, confirm Apple processing and build eligibility, inspect the new captures, finish the privacy and age-rating questionnaires, select the build, and verify the existing contact, rights, pricing, and availability fields. Record the final review submission status here.

The `release/app-store` branch explicitly exports an App Store-eligible build. Ordinary main-branch uploads remain internal-only. Uploading does not itself submit App Review or publish the app.

Subsequent research: Apple’s current [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions) explicitly include public posting in Messaging and Chat, UGC discovery feeds in Social Media, and embedded browsers in Unrestricted Web Access. Source inspection confirms the native HN feed and the Vote or reply on HN action opening an in-app SFSafariViewController. This supports those proposed disclosures; it does not mean the questionnaire was saved or the remaining content-frequency questions were answered.

## Approved continuation — September 13, 2026

The publisher supplied App Review contact details in chat and explicitly approved all remaining publication work. The contact was encrypted with the existing distribution certificate’s public key before transfer through GitHub; no plaintext contact or Apple credential was committed. Apple API readback verified all four contact fields exactly. Do not request the same approval or contact details again.

Completed through the existing Apple API connection:
- Build 6.1.0 remains VALID and APP_STORE_ELIGIBLE, selected on version 1.0; release is AFTER_APPROVAL.
- App Review contact and no-demo-account setting saved and verified.
- Privacy policy URL, subtitle, News / Productivity categories, and USES_THIRD_PARTY_CONTENT declaration saved.
- Publisher-approved age-rating questionnaire saved and read back. Apple canonicalizes INFREQUENT to INFREQUENT_OR_MILD; the initial literal-value assertion failed, but a subsequent read verified the answers. This was corrected in the submission script.
- Four 1320 × 2868 iPhone screenshots and four 2064 × 2752 iPad screenshots uploaded, all Apple assetDeliveryState COMPLETE. Native source run 34774575947; artifacts 10323425521 and 10323023612.
- Free price saved, with USA base territory and a fresh price-point verification.
- Availability saved for 175 territories, including future territories. No new trader-status declaration was made.

Submission attempt [34784554817](https://github.com/yaportmax/ember-hacker-news/actions/runs/34784554817) passed the preparatory checks but Apple rejected adding the version to App Review with one associated error: `STATE_ERROR.APP_DATA_USAGES_REQUIRED` — published answers to the app’s data usages are required. A draft review submission may exist; no review submission succeeded. The application is NOT published or waiting for review.

The only blocker reported by Apple is the unpublished App Privacy data-collection label. Apple’s public OpenAPI specification exposes the privacy policy URL but not a privacy-label publishing operation. The cloud browser remained unusable: repeated refresh timeouts, a reported confirm dialog, browser-recovery supersession errors, and a failed manual-handoff request. A new tab could be created but not inspected/navigated reliably. Do not repeat permission questions; recover the browser or have the publisher publish App Privacy answers in App Store Connect.

After the privacy label is published, rerun the final preparation workflow job (103797540779, run 34784554817) or update the `release/store-prepare` branch to trigger verification/submission. The final source is `bbbfb04ab090a38a35009a0bebc42b6964374830`; `EMBER_VERIFY_AND_SUBMIT=1` avoids repeating completed metadata, screenshot, price, and availability writes. It performs fresh preflight checks, reuses the draft submission, and submits to review. Confirm the returned submission state before reporting success.
