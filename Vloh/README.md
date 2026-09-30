# Vloh

Native private vlogs for your friend group. Swift 6, SwiftUI, iOS 18+. Built with the same dependency-free structure and checked-in Xcode project as Ember.

## Run
Open `Vloh.xcodeproj` in Xcode 26+. Run the Vloh scheme. Camera recording needs a physical device. Sharing needs iCloud and the registered `iCloud.com.maxyaport.vloh` container.

## Included
- Private groups with Apple's native invite sheet and iCloud access.
- Record with the native camera or import chosen videos using PhotosPicker.
- Durable local drafts, clip reordering, deletion, trimming, captions, and previews.
- Portrait 720p exports with letterboxed landscape clips and original audio.
- Persistent upload queue, stable record IDs to avoid duplicate retries, and explicit paused/retry state.
- Feed metadata separated from video downloads; no automatic playback while scrolling.
- On-demand video cache capped at 500 MiB. Draft files are outside that cache.
- Group chat, vlog replies, reactions, search, unwatched filter, and video export.
- Optional turn rotation by the group's timezone. Anyone can still post anytime.
- Native Dynamic Type, light/dark appearance, accessibility labels, iPhone/iPad layouts.

## Boundaries
CloudKit transfers run while the app is active or within iOS's limited background execution window. An interrupted transfer retains its exported file and draft, and can be retried. This does not promise unlimited background upload. First playback downloads the compressed video file before playback; HLS streaming is not implemented.

Shared-zone members have CloudKit read/write permissions. This is intended for a trusted private group, not adversarial public social networking. Contributors can export videos. The UI limits deletion to your own vlog, but that UI is not a server-enforced ownership ACL.

Chat refreshes on entry, manual refresh, and every 15 seconds while open. Push notification delivery and scheduled turn reminders are not implemented in this build. Rotation currently uses registered member rows, so a removed share participant's row should be cleaned up before relying on rotation.

## Tests
`swift test -j 2` runs portable archive/rotation tests. `python3 scripts/validate.py` runs native unit/UI tests, exports screenshot evidence, and builds the Release device target without signing on a Mac. CI uses the same script. Fixtures exist only in Debug under `--ui-testing`.

A new app must be registered in App Store Connect before its first upload. See `Release/SETUP.md`. No TestFlight availability is claimed until Apple confirms the processed build and Max's internal tester group.
