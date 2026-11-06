# Hailbell for Flutter

In-app support chat and push notifications from [Hailbell](https://hailbell.com) for Flutter apps on iOS and Android.

The plugin wraps Hailbell's native SDKs. Your customers get the same native chat as Swift and Kotlin apps: ticks, typing, photos, review and offer cards, an offline cache, and the chat's words in 14 languages. You answer from the Hailbell dashboard, Discord or Telegram.

```dart
import 'package:hailbell/hailbell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hailbell.configure(appId: 'app_...');   // the App ID of the platform the app runs on
  runApp(const YourApp());
}

// A "Chat with us" button
onPressed: () => Hailbell.open(),
```

The step-by-step setup, including push with `firebase_messaging`, is in [GUIDE.md](GUIDE.md). The example app is in [example/](example).

## Requirements

- Flutter 3.27 or later.
- iOS 16 or later. Swift Package Manager and CocoaPods both work.
- Android 8 (API 26) or later, Kotlin 2.0 or later.

## Hailbell

| API | Use |
| --- | --- |
| `Hailbell.configure(appId:, baseUrl:)` | Call once at launch, after `WidgetsFlutterBinding.ensureInitialized()`. iOS and Android have different App IDs. |
| `Hailbell.open()` | Opens the chat as a full-height sheet. Throws a `StateError` before `configure`. |
| `Hailbell.unreadCount` | A `ValueListenable<int>` of replies not yet read, for a badge. `unreadCountStream` is the same as a `Stream<int>`. |
| `Hailbell.identify(userId:, name:, email:, identityToken:)` | Who the user is. Only `identityToken`, an HS256 JWT signed with the app's identity secret, links the chat across devices. |
| `Hailbell.identify(name:, email:, firebaseIdToken:)` | For apps on Firebase Auth: a function returning the current ID token. Hailbell verifies it and uses the Firebase uid as the user id. |
| `Hailbell.setMetadata(map)` | Context shown beside the chat, merged with what you sent before. `appVersion`, `os` and `locale` are sent automatically. |
| `Hailbell.track(event, properties:)` | A signal shown beside the chat, such as `paywall_decline` or `chat_opened`. |
| `Hailbell.setPaywallPlacements(list)` | The placements an offer can open. |
| `Hailbell.onPaywall` | `(placement, purchased) {}`: open the paywall, and call `purchased()` if they buy. |
| `Hailbell.setPushToken(token)` | Android: the FCM token. iOS: the plugin takes the APNs token by itself; pass `getAPNSToken()` only as a fallback, never the FCM token. |
| `Hailbell.handleNotification(data)` | Opens the chat for a tapped reply's payload. The plugin already does this for its own notifications. |
| `Hailbell.darkMode` | `null` (default) follows the phone. Set `true` for an always-dark app. |
| `Hailbell.asksForNotifications` | Default `true`: after the first message, the chat offers to turn on notifications if they're off. |
| `Hailbell.setTeamPhoto(bytes)` | Deprecated: set the photo in the dashboard. A bundled photo shows only until the chat hears from Hailbell, and never once the dashboard signs replies as the team, turns photos off or sets a photo for this app. |
| `Hailbell.reset()` | On sign-out: clears the identity and the cached chat. |
| `Hailbell.deleteData()` | Deletes the user's chat, images and details from Hailbell. Throws a `HailbellException` if the server can't be reached. |

## HailbellPush

| API | Use |
| --- | --- |
| `handleMessage(data, title:, body:)` | Pass every `firebase_messaging` message, from `onMessage` and `onBackgroundMessage`. Returns false for messages that aren't Hailbell's. |
| `isHailbell(data)` | True when an FCM data map came from Hailbell. |
| `requestPermission(provisional:)` | Asks for notification permission and registers for pushes. |
| `canNotify()` | Whether the user allows notifications. |
| `setTags(map)` | Key/value data for segments; a `null` value removes a tag. |
| `setMarketing(enabled)` / `optOut()` | Promotional opt-in, or stop all Hailbell pushes to this device. |
| `onOpen` | iOS: route a tapped campaign push yourself; return true when handled. On Android the link opens as an intent for your app. |
| `clearBadge(appGroup:)` | iOS: resets the badge kept by the Notification Service Extension. |
| `setAndroidOffersChannel(id)` | Android: use the app's own channel for campaign pushes. Call before `configure`. |

## Install

```sh
flutter pub add hailbell
```

or in `pubspec.yaml`:

```yaml
dependencies:
  hailbell: ^1.0.0
```

## How it's built

`lib/` is the Dart API. It talks to `android/` and `ios/` over one method channel, `hailbell`, and an event channel, `hailbell/unread_count`, for the unread count.

The plugin carries Hailbell's [iOS](https://github.com/vidursaini/hailbell-ios) and [Android](https://github.com/vidursaini/hailbell-android) SDKs inside it, in `ios/hailbell/Sources/hailbell/Vendor/` and `android/vendor/hailbell/`, so each release pins one version of both. Those folders are replaced on every release; don't edit them. The plugin's own native code is `ios/hailbell/Sources/hailbell/HailbellPlugin.swift` and `android/src/main/kotlin/com/hailbell/flutter/`.

`flutter test` runs the Dart tests against a mocked channel.

## Support and license

Questions: hello@hailbell.com, or the chat on [hailbell.com](https://hailbell.com).

MIT. See [LICENSE](LICENSE).
