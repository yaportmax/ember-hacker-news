# Internal TestFlight

Ember is registered as `com.maxyaport.ember` in team `4BY949S88S`, with App Store Connect app ID `6811495244`. The private internal group contains only Max's account and automatically receives uploaded builds.

After a successful main-branch push runs all native validation jobs, `TestFlight upload` downloads that exact run's receipt, checks its source fingerprint, creates a signed Release archive, and uploads an internal-only build. Pull requests never upload. A manual run on main can select an existing successful main-push validation run while its receipt artifact remains available. Each upload run/attempt has its own build number.

`EMBER_APPLE_SIGNING` is an encrypted GitHub Actions repository secret containing the Apple API key, distribution certificate and private key, provisioning profile, and certificate password. It must never be committed or included in artifacts. The runner imports credentials into a temporary keychain and removes its local signing files afterward. The certificate and profile must be renewed before expiry. Only trusted repository collaborators should be able to modify workflows that use this secret.

The workflow records successful upload separately from Apple's processing and tester availability. Once processing finishes, use TestFlight while signed into the tester's Apple account to install Ember. A build is not reported ready until App Store Connect shows it available to the internal group.

The beta's support link points to repository issues. App Store publication remains a separate process requiring public support/privacy details, final metadata and physical-device review; see [Publishing](PUBLISHING.md). This workflow never submits an App Store review or distributes to external testers.
