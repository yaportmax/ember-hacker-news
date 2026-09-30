# Vloh privacy

Last updated: September 30, 2026.

Vloh is a private video and chat app for small groups of friends. It uses Apple iCloud and CloudKit. It does not create a separate password account, read your contacts, show advertising, or include third-party analytics.

## What the app stores

Your chosen display name, group membership, published videos and thumbnails, captions, messages, replies, reactions, and publishing dates are stored in the group's private CloudKit space. CloudKit supplies an account identifier to associate your contributions with your iCloud account. Vloh does not receive your Apple Account password.

Drafts and their original clips are stored on your device. Publishing sends an exported video, thumbnail, and caption to your group. The app caches downloaded videos and thumbnails on your device for playback.

The Photos picker gives Vloh the videos you select. Camera and microphone access is requested when you choose to record. Vloh does not browse your full photo library or contacts.

## Who can access published content

The group owner and invited participants can view and contribute to the group's shared CloudKit space. Vloh does not publish your videos to a public feed. Invited participants can download or export copies. Groups are intended for people you trust.

Apple provides the hosting, account authentication, and sharing infrastructure. Apple's privacy policies and iCloud terms apply to those services. TestFlight can collect testing and crash information under Apple's TestFlight terms; Vloh does not add its own analytics service.

## Removal and retention

You can delete your drafts from Drafts and delete your own published vlogs from a video's actions menu. Deleting a published vlog removes its video record from the group. Previously exported copies held by other participants cannot be removed by Vloh. Related messages and replies are separate records and may remain in the group's CloudKit space.

The group owner can manage or revoke invitations using Apple's sharing sheet. Revoking an invitation removes that person's ongoing access; it does not delete content they contributed or copies they already exported. Removing the app removes its local drafts and cache, but does not automatically remove published CloudKit content.

## Contact

Report a Vloh issue through [the project support page](https://github.com/yaportmax/ember-hacker-news/issues). Please do not include passwords or private group videos in a public issue.
