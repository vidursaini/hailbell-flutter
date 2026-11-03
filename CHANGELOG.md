## 0.1.0

- First release. Wraps the Hailbell iOS (Swift) and Android (Kotlin and Compose) SDKs.
- Chat: `Hailbell.configure`, `open`, `identify` (identity token or Firebase ID token), `setMetadata`, `track`, `setPaywallPlacements`, `onPaywall`, `unreadCount`, `reset`, `deleteData`, `darkMode`, `asksForNotifications`, `setTeamPhoto`.
- Push: `Hailbell.setPushToken`, `HailbellPush.handleMessage` for `firebase_messaging`, `requestPermission`, `canNotify`, `setTags`, `setMarketing`, `optOut`, `onOpen` and `clearBadge` on iOS, `setAndroidOffersChannel`.
