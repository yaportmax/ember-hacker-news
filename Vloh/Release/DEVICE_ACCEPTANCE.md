# Vloh device acceptance

Automated validation covers draft persistence, trimming, mixed orientation silent video export, iPhone/iPad navigation, and Release compilation. It does not establish these live iCloud and hardware results. Complete them on the signed TestFlight build before inviting the whole group:

1. On an iCloud-signed-in iPhone, enter your name and create a private group. Record a clip with audible speech, import a landscape clip, trim and reorder them, then publish. Check picture orientation, clip boundaries and audio sync.
2. Force quit while a draft is saved, reopen, and confirm its clips and trim survive. Turn off network before sharing; confirm the queued draft survives another relaunch and publishes once after reconnecting.
3. Invite a second iCloud account using the group’s native private invitation. Accept on its iPhone, watch the vlog, send a chat message, reply and react. Confirm both accounts receive changes.
4. Revoke that participant in the native sharing controls. Confirm refreshed group access is removed on the other device. Downloaded or exported copies cannot be recalled.
5. Delete your posted vlog, refresh on both phones, and confirm it leaves the feed. Replies/reactions are separate CloudKit records; deletion does not remove their records.
6. Try camera/microphone denial, airplane mode and insufficient iCloud storage. Confirm useful errors preserve the draft. Check dark mode, larger text and VoiceOver on the main screens.

Known beta constraints: foreground polling rather than push delivery; no scheduled turn notification; compressed videos download fully before first playback; uploads retry while the app is active; owner iCloud storage is used by the private group. Do not report these as verified background or streaming features.
