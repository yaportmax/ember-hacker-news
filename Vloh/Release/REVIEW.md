# External beta review readiness

This is a working audit, not an approval or a guarantee. External review is held until the updated native suite passes, the new CloudKit schema is deployed to Production, and the device acceptance checks below are completed.

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
| 4.8 Login | Native Sign in with Apple plus iCloud for group storage. No separate password. Native Apple authorization identifier is retained privately; no Apple refresh tokens are retained. |
| 5.1.1 Privacy | In-app/public privacy policy, minimal purpose strings, selected photo picker, account/data deletion. App Store privacy answers must match actual CloudKit and optional report handling. |
| 5.1.1(v) Account deletion | Deletes private profile, owned zones and own contributions to joined groups before leaving; then local draft data. Apple-account data/exported copies are outside Vloh's control. Verify on two real accounts. |
| Export compliance | `ITSAppUsesNonExemptEncryption = false`, using Apple's platform encryption. |
| Beta metadata/contact | Reuse verified review-contact details from Max's existing app where available. No invented phone or address. |

## Required before submission

- Deploy schema additions in `cloudkit-schema.ckdb`: group/member photos and schedule, VlohProfile, vlogDay/draftID/deleted.
- Enable Apple's native sign-in capability and regenerate the Vloh provisioning profile.
- Verify record → stop → record, front/back cameras, audio, interruption, restored draft on an iPhone.
- Verify two-account private invitation, ordered schedule, daily duplicate prevention, chat, playback, photos, owner removal, and account deletion.
- Verify public privacy URL and accurate age/content/privacy declarations in App Store Connect.
- Review notes must explain the sign-in/iCloud requirements and how reviewers can create their own group. Do not expose the user's private group to reviewers.

## Playback constraint

CloudKit returns downloaded CKAsset files. It does not provide the app with progressive/HLS streaming URLs. New exports use a 720p compression preset, recent videos preload, concurrent fetches share one transfer, and cached files open directly. Existing large uploads still need their initial full download. CDN-backed streaming would require a separate media service and authorization design.

## Integrity constraint

Filming times come from Vloh capture timestamps or imported media's original metadata. Missing metadata is rejected. These are eligibility checks for a trusted friend group, not tamper-proof attestation. One stable group/day record ID prevents concurrent duplicate posts through the app. Deletion leaves a media-free tombstone so deleting a vlog does not reopen its daily slot.
