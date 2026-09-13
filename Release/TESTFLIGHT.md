# Internal TestFlight

Version **1.0.0 (5.1.0)** is available for private testing as of September 13, 2026, 13:17 UTC. Apple's API confirms processing state **VALID**, internal build state **IN_BETA_TESTING**, and membership in **Max — Internal Testing**. Open TestFlight and update **Ember for Hacker News**. [GitHub build/sign/upload run](https://github.com/yaportmax/ember-hacker-news/actions/runs/34759161548).

The uploaded source is `7e0ba1bba4e95181ca516e72efc27cfce1b47901`; Apple's build ID is `c8d94aef-fd4c-4979-be49-6168029d681c`. This update improves large-discussion loading and scroll-time work, sets comment size/row spacing/indentation to centered 14-point defaults, and unifies spacing across comments and live previews. [Native review and screenshots](../docs/review/DISCUSSION-PERFORMANCE.md) · [Upload and availability record](testflight-5.1.0-upload.json).

Ember is registered as `com.maxyaport.ember` in team `4BY949S88S`, with App Store Connect app ID `6811495244`. The private internal group contains only Max's account and automatically receives uploaded builds.

A main-branch code push (or manual **TestFlight upload** run on main) runs the quick core/live API checks, builds and signs Release once, and uploads it to internal TestFlight. Documentation-only pushes do not upload. Pull requests never upload. Each run/attempt has its own build number.

Full iPhone/iPad UI tests and screenshot exports are available through the manual **iOS validation** workflow. They are deliberately not a prerequisite for every private test build. The upload record lists the checks actually run and does not claim a new UI test pass.

`EMBER_APPLE_SIGNING` is an encrypted GitHub Actions repository secret containing the Apple API key, distribution certificate and private key, provisioning profile, and certificate password. It must never be committed or included in artifacts. The runner imports credentials into a temporary keychain and removes its local signing files afterward. The certificate and profile must be renewed before expiry. Only trusted repository collaborators should be able to modify workflows that use this secret.

The workflow records successful upload separately from Apple's processing and tester availability, then polls the read-only Apple API for up to eight minutes to verify the existing internal group's access. Once processing finishes, use TestFlight while signed into the tester's Apple account to install Ember. A build is not reported ready until App Store Connect shows it available to the internal group.

The beta's support link points to repository issues. App Store publication remains a separate process requiring public support/privacy details, final metadata and physical-device review; see [Publishing](PUBLISHING.md). This workflow never submits an App Store review or distributes to external testers.
