# Apple setup

Team: `4BY949S88S` (existing Ember team).
Bundle: `com.maxyaport.vloh`.
CloudKit container: `iCloud.com.maxyaport.vloh`.

1. Register the bundle ID and enable iCloud/CloudKit and Push Notifications.
2. Create the CloudKit container and associate it with the bundle ID. Initialize the record schema in Development, then deploy it to Production before TestFlight group sharing.
3. In App Store Connect, create an iOS app named **Vloh**, primary language English (U.S.), bundle ID above, SKU `vloh-ios-1`. Apple requires the website for new app creation.
4. Use automatic provisioning with the existing App Store Connect API key and Apple Distribution certificate. The Ember provisioning profile cannot sign Vloh.
5. Create **Max — Internal Testing** for Vloh with automatic build distribution and add Max's existing internal account. External buddies require their own TestFlight group and Apple's beta review.

Record types: `VlohGroup`, `VlohMember`, `VlohVlog`, `VlohReply`, `VlohReaction`. Sync uses zone-change fetches, so no query indexes are required. Video/poster fields on VlohVlog are CKAsset fields. Others are represented by the production schema in `cloudkit-schema.ckdb`.

Private TestFlight does not publish the app to the App Store. Signed builds must be verified for processing and tester access. A CloudKit Production deployment is required for real TestFlight sharing, not merely a simulator compile pass.
