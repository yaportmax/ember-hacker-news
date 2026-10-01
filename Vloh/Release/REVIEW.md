# External beta review readiness

This is a working audit, not an approval or a guarantee. The updated native suite and unsigned device Release build passed on October 1; see `VALIDATION.json`. External review remains held until the new CloudKit schema is deployed to Production, new-account Apple token handling is resolved, and the device acceptance checks below are completed.

## Review coverage

| Apple requirement | Implementation / remaining check |
| --- | --- |
| 1.2 User-generated content | Private invitations, text screening, vlog/message reporting through a reviewed email, hide/block controls, owner deletion and member removal, public contact and community rules. There is no automated video-content classifier. Human moderation and timely handling of reports remain the operator's responsibility. |
| 1.5 Developer contact | In-app mail contact and public policy/support documents. |
| 1.6 Security | CloudKit private/shared zones, private invites, no public `_world` access on Vloh types. Shared-zone contributors have read/write rights; client posting/order rules do not provide adversarial server enforcement. |
| 2.1 Completeness | Native unit/UI tests cover core paths and media fixtures. Real camera, sound, sign-in, CloudKit sharing, and account deletion require device acceptance. |
| 2.2 TestFlight | External distribution is submitted for beta review; no tester compensation and no App Store release is requested. |
| 2.3 Accurate metadata | Description and test notes must disclose daily rotation, filming/posting windows, iCloud, selected imports and download-first playback. |
| 2.4 Compatibility | iPhone and iPad native layout/test runs. |
| 2.5 APIs/background | Public APIs only. Capture session runs on serial queue. No unrelated background modes. Upload resumes from saved state. |
| 4.1 Intellectual property | Original Vloh name/UI/assets. No Vlogit branding or copied assets. |
| 4.8 Login | Native Sign in with Apple plus iCloud for group storage. No separate password. Native Apple authorization identifier is retained privately; credential state is checked and revocation signs out. No Apple refresh tokens are retained. |
| 5.1.1 Privacy | In-app/public privacy policy, minimal purpose strings, selected photo picker, account/data deletion. App Store privacy answers must match actual CloudKit and optional report handling. |
| 5.1.1(v) Account deletion | Deletes private profile, owned zones and own contributions to joined groups before leaving; then local draft data and playback cache. Signs out and shows Apple's instructions for removing authorization manually. Verify on two real accounts. |
| Export compliance | `ITSAppUsesNonExemptEncryption = false`, using Apple's platform encryption. |
| Beta metadata/contact | Reuse verified review-contact details from Max's existing app where available. No invented phone or address. |

## Privacy declarations prepared

The bundled privacy manifest declares Name, Email Address, User ID, Photos/Videos, Audio, Emails/Text Messages, Customer Support, and Other User Content for app functionality, linked to the user, with no tracking. Email Address is support correspondence, not a requested Sign in with Apple email scope. This conservatively includes private CloudKit content and optional report evidence rather than asserting that the app has no user data. Match the App Store Connect questionnaire to these declarations and the public policy before submission.

## Other applicable guideline checks

- 1.1 / 1.2: community rules prohibit objectionable content; operator moderation still requires real responses to reports.
- 1.3: the app is not submitted to the Kids Category. Complete the age-rating questionnaire honestly for user content, messaging, and video sharing.
- 2.3: app icon and public support/privacy documents exist; screenshots and test notes must show the submitted build. No hidden paid features, subscriptions, location, contacts, ads, tracking, or AI generation are included.
- 3.1 / 3.2: the beta has no paid access, purchases, financial services, donations, or rewards.
- 4: original app UI, native permissions and share controls, accessible labels/trim adjustment, iPhone/iPad support. Device checks must cover larger text and VoiceOver.
- 5.2: users must have rights and consent for uploaded clips. No third-party Vlogit branding, assets, music, or code is used.
- 5.3 / 5.4 / 5.5: no gambling, lottery, VPN, or device-management features.

## Required before submission

- Deploy schema additions in `cloudkit-schema.ckdb`: group/member photos and schedule, VlohProfile, vlogDay/draftID/deleted.
- Enable Apple's native sign-in capability and regenerate the Vloh provisioning profile.
- Verify record → stop → record, front/back cameras, audio, interruption, restored draft on an iPhone.
- Verify two-account private invitation, ordered schedule, daily duplicate prevention, chat, playback, photos, owner removal, and account deletion.
- Verify public privacy URL and accurate age/content/privacy declarations in App Store Connect.
- Resolve Sign in with Apple token handling for new accounts before external review. The current native-only implementation retains no refresh tokens and offers the manual revocation fallback described in TN3194; Apple also documents server validation/storage for new account creation. Do not describe automatic Apple authorization revocation as implemented.
- Review notes must explain the sign-in/iCloud requirements and how reviewers can create their own group. Do not expose the user's private group to reviewers.

## Playback constraint

CloudKit returns downloaded CKAsset files. It does not provide the app with progressive/HLS streaming URLs. New exports use a 720p compression preset, recent videos preload, concurrent fetches share one transfer, and cached files open directly. Existing large uploads still need their initial full download. CDN-backed streaming would require a separate media service and authorization design.

## Integrity constraint

Filming times come from Vloh capture timestamps or imported media's original metadata. Missing metadata is rejected. These are eligibility checks for a trusted friend group, not tamper-proof attestation. One stable group/day record ID prevents concurrent duplicate posts through the app. Deletion leaves a media-free tombstone so deleting a vlog does not reopen its daily slot.
