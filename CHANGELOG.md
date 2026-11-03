## 1.0.0

- Stable. Tested on the iOS simulator (Swift Package Manager and CocoaPods builds; chat, dark mode, and reply and campaign pushes with the app open, in the background and closed) and on the Android emulator.

## 0.1.1

- iOS: builds with Xcode 27.2 (Swift 6.4). The Swift SDK read the device model off the main actor, which the new compiler rejects.

## 0.1.0

- First release. Wraps the Hailbell iOS (Swift) and Android (Kotlin and Compose) SDKs.
- Chat: `Hailbell.configure`, `open`, `identify` (identity token or Firebase ID token), `setMetadata`, `track`, `setPaywallPlacements`, `onPaywall`, `unreadCount`, `reset`, `deleteData`, `darkMode`, `asksForNotifications`, `setTeamPhoto`.
- Push: `Hailbell.setPushToken`, `HailbellPush.handleMessage` for `firebase_messaging`, `requestPermission`, `canNotify`, `setTags`, `setMarketing`, `optOut`, `onOpen` and `clearBadge` on iOS, `setAndroidOffersChannel`.
