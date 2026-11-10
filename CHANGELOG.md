## 1.0.2

- Android: a review card's button opens the app's Play Store listing instead of Play's in-app review sheet, which Play can skip without telling the app, so a tap did nothing. Google's in-app review library is no longer a dependency.
- Native SDKs: iOS 1.1.4, Android 1.1.3.

## 1.0.1

- The dashboard decides who customers see on replies. Each reply shows the photo of the teammate who wrote it in this app, and the header follows the app's chat design and each teammate's per-app photo.
- `setTeamPhoto` is deprecated. A bundled photo shows only until the chat first hears from Hailbell, and never once the app signs replies as the team, turns photos off, or sets a photo (or no photo) for this app in the dashboard.
- Native SDKs: iOS 1.1.4, Android 1.1.2.

## 1.0.0

- Stable. Tested on the iOS simulator (Swift Package Manager and CocoaPods builds; chat, dark mode, and reply and campaign pushes with the app open, in the background and closed) and on the Android emulator.

## 0.1.1

- iOS: builds with Xcode 27.2 (Swift 6.4). The Swift SDK read the device model off the main actor, which the new compiler rejects.

## 0.1.0

- First release. Wraps the Hailbell iOS (Swift) and Android (Kotlin and Compose) SDKs.
- Chat: `Hailbell.configure`, `open`, `identify` (identity token or Firebase ID token), `setMetadata`, `track`, `setPaywallPlacements`, `onPaywall`, `unreadCount`, `reset`, `deleteData`, `darkMode`, `asksForNotifications`, `setTeamPhoto`.
- Push: `Hailbell.setPushToken`, `HailbellPush.handleMessage` for `firebase_messaging`, `requestPermission`, `canNotify`, `setTags`, `setMarketing`, `optOut`, `onOpen` and `clearBadge` on iOS, `setAndroidOffersChannel`.
