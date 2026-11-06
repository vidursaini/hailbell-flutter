# Adding Hailbell to a Flutter app

This guide takes a Flutter app to a live support chat with push replies, offers and the usual entry points, on iOS and Android. The plugin wraps Hailbell's native SDKs: the chat your customers see is the same native screen as in Swift and Kotlin apps, with ticks, typing, photos, review and offer cards. You write Dart; nothing in the chat is rebuilt in Flutter.

The API reference is in [README.md](README.md). The dashboard, Discord, Telegram, AI replies and purchases work the same as for native apps; [hailbell.com/docs](https://hailbell.com/docs) explains how replies and offers flow.

## 1. Create the app in the dashboard

Using a coding agent? With the [Hailbell skill](https://hailbell.com/docs#agents) and its MCP server connected, the agent makes the app and both platforms itself (step 2). You still sign up and upload the push keys (step 3).

1. **Sign up** at [app.hailbell.com](https://app.hailbell.com/?signup=1) with **Continue with Google** or an emailed sign-in link. The first sign-in makes an account with a 14 day free trial, no card needed, and the first-run setup creates your first app from an App Store search.
2. Give the app an **iOS** and an **Android** platform: on the app's page in **Settings**, use **Add iOS** or **Add Android** under **Platforms**. Each platform has its own **App ID** (`app_…`), and your app passes the one for the platform it runs on. App IDs are public, so they live in code. Set the iOS platform's **Bundle ID (for push)** under **Edit**.
3. Upload your push keys in **Settings › Push keys**:
   - **iOS:** in Apple Developer, **Certificates, Identifiers & Profiles › Keys**, make a key with **Apple Push Notifications service (APNs)** on, download the `.p8` file, and upload it with its **Key ID** and your **Team ID**. One key covers every app in that Apple team.
   - **Android:** in the Firebase console, **Project settings › Service accounts › Generate new private key**, and upload the JSON file. One file per Firebase project.

   Hailbell checks each key with Apple or Google, stores it encrypted and never shows it again.
4. In **Push › Setup**, enter the Android app's **Firebase project ID** (from `google-services.json`) and press **Save**. Both cards should say **Ready**. Hailbell also checks Firebase ID tokens against that project (signed-in users, below).
5. Optional: **Chat design** (accent for light and dark, title, team photo), **Reviews** (App Store ID and Play package name), **Offers**, Discord or Telegram, and AI replies.

## 2. Add the package

```sh
flutter pub add hailbell
```

or in `pubspec.yaml`:

```yaml
dependencies:
  hailbell: ^1.0.0
```

The package is [hailbell on pub.dev](https://pub.dev/packages/hailbell). Its source is https://github.com/vidursaini/hailbell-flutter.

Requirements:

| | |
| --- | --- |
| Flutter | 3.27 or later, Dart 3.6 or later |
| iOS | 16 or later. Swift Package Manager (Flutter's default) and CocoaPods both work. With CocoaPods, set `platform :ios, '16.0'` in `ios/Podfile`. Also set the Runner's **Minimum Deployments** to 16.0. |
| Android | `minSdk = 26` in `android/app/build.gradle.kts`, Kotlin 2.0 or later. The plugin adds the Compose compiler itself, at the app's Kotlin version, so there's nothing else to set up in Gradle. |

The plugin carries the native SDKs inside it. On Android that brings Compose, OkHttp, Coil and `lifecycle-process`, and the manifest entries (`INTERNET`, `POST_NOTIFICATIONS`, the chat activity) merge by themselves. On iOS it carries Hailbell's `PrivacyInfo.xcprivacy`. Neither side depends on Firebase: your app passes the push token and messages in (step 6).

## 3. Wrap it in one file

Keep every Hailbell call in one place, so the app can turn the chat off by emptying the App IDs:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hailbell/hailbell.dart';

class HailbellSupport {
  static const _iosAppId = 'app_XXXXXXXX';
  static const _androidAppId = 'app_YYYYYYYY';
  static String get _appId => Platform.isIOS ? _iosAppId : _androidAppId;
  static bool get isEnabled => _appId.isNotEmpty;

  static Future<void> configure() async {
    if (!isEnabled) return;
    await Hailbell.configure(appId: _appId);

    await Hailbell.setPaywallPlacements(['winback', 'support_offer']);   // every placement an offer may open
    Hailbell.onPaywall = (placement, purchased) async {
      // Open your paywall for `placement`, and call purchased() if the customer buys (step 7).
      if (await Paywalls.show(placement)) purchased();
    };
  }

  /// `source` names the button, so the dashboard shows where people find the chat.
  static Future<void> open(String source) async {
    if (!isEnabled) return;
    await Hailbell.track('chat_opened', properties: {'source': source});
    await Hailbell.open();
  }

  /// Call at launch and whenever the plan changes.
  static Future<void> updateMetadata({required bool isPro, required String version}) =>
      Hailbell.setMetadata({
        'appVersion': version,
        'plan': isPro ? 'pro' : 'free',
        'superwallUserId': '<Superwall user id>',   // or 'revenueCatUserId': await Purchases.appUserID
      });
}
```

Call it first thing in `main()`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HailbellSupport.configure();
  runApp(const YourApp());
}
```

`Hailbell.open()` throws a `StateError` if `configure` hasn't run, so a missing setup shows up in development rather than as a blank chat.

### Who customers see on replies

The dashboard decides, per app, and your app can't change it: the SDK has no setting for the name or photo on replies, so an app can't sign as someone else. In the dashboard:

- **Chat design › Replies are signed**: **By each teammate** (their name and photo) or **As the team** (the chat title, else "<App> Support", and no personal photo).
- **Profile › In each app**: each teammate can use another name, their own photo or no photo in one app, and their profile everywhere else.

Changes show the next time the chat opens, with no app release. Earlier replies keep the name they were sent with and show the current photo. Agents can read and change the same over MCP (`get_reply_identity`, `update_reply_identity`) and REST (`/v1/reply-identity`).

``Hailbell.setTeamPhoto`` is deprecated. Upload the photo in the dashboard instead: the chat loads it from Hailbell and caches it, so it usually shows offline after the first load. A bundled photo now shows only until the chat first hears from Hailbell, and after that only while the dashboard has no photo of its own for this app. It never shows once the app signs replies as the team, turns photos off, or sets a photo (or no photo) for this app. The chat remembers the last answer, so an offline launch follows it too.

## 4. Entry points

The plugin presents the chat; your app decides where people tap to open it. These four work well:

1. **A "Chat with us" row** in Profile or Settings.
2. **A headset button** in the Profile header with a red dot while there are unread replies:

   ```dart
   ValueListenableBuilder<int>(
     valueListenable: Hailbell.unreadCount,
     builder: (context, unread, _) => IconButton(
       onPressed: () => HailbellSupport.open('profile_header'),
       icon: Badge(isLabelVisible: unread > 0, smallSize: 9, child: const Icon(Icons.headset_mic_outlined)),
     ),
   )
   ```

   `Hailbell.unreadCountStream` gives the same count as a `Stream<int>`, for Bloc, Riverpod or a `StreamBuilder`.
3. **A Home Screen quick action and an Android app shortcut** "Chat with us", for example with the `quick_actions` package. On a cold start, wait about a second before calling `open`, so the first screen is up.
4. **A "Need help?" bar** above the tab bar for free users, 24 hours after they first close a paywall. Most people who buy do so at the first paywall or within minutes of closing it, so waiting a day keeps buyers out of the chat. Check your own paywall data before picking the delay.

The chat opens as a full-height sheet over the app: a native sheet on iOS, and on Android its own activity that you drag down or close with back. `Hailbell.darkMode = true` keeps the chat dark for an always-dark app; the default follows the phone.

## 5. Signed-in users (optional)

Without a token, a chat belongs to the install. To follow a user across devices, your backend signs an HS256 JWT with the app's identity secret, with `sub` set to your user id and optional `name` and `email`:

```dart
await Hailbell.identify(identityToken: jwtFromYourBackend);
await Hailbell.reset();        // on sign-out
await Hailbell.deleteData();   // when the user deletes their account
```

**Firebase Auth apps** don't need a backend for this. Set the app's Firebase project in Hailbell, then pass a function that returns the current ID token:

```dart
final user = FirebaseAuth.instance.currentUser;
if (user != null && !user.isAnonymous) {
  await Hailbell.identify(
    name: user.displayName,
    email: user.email,
    firebaseIdToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  );
}
```

Call it at launch and after sign-in. ID tokens last an hour, so the native SDK calls the function for a fresh token each time it starts a session. If the function throws, Hailbell treats it as no token.

`identify(userId:, name:, email:)` without a token shows those details in the dashboard but never uses them to find a chat. Tick **Only signed-in users can chat** on the app to block anonymous chats.

Call `deleteData()` before deleting the account, and stop if it throws a `HailbellException`, so a retry deletes both. The App Store (guideline 5.1.1(v)) and Google Play both require in-app account deletion to remove this data.

## 6. Push for replies

Replies to a closed chat arrive as notifications. Hailbell sends iOS pushes through APNs directly and Android pushes through FCM. This setup assumes the app uses `firebase_messaging`, as most Flutter apps do. It keeps working for your own pushes.

### Both platforms

```dart
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hailbell/hailbell.dart';

/// Runs in a background isolate when a push arrives while the app is in the background or closed.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  final handled = await HailbellPush.handleMessage(message.data,
      title: message.notification?.title, body: message.notification?.body);
  if (handled) return;
  // … your own background pushes
}

Future<void> setUpPush() async {
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  FirebaseMessaging.onMessage.listen((message) async {
    final handled = await HailbellPush.handleMessage(message.data,
        title: message.notification?.title, body: message.notification?.body);
    if (handled) return;
    // … your own foreground pushes
  });

  final messaging = FirebaseMessaging.instance;
  if (Platform.isIOS) {
    // Hailbell uses the APNs token on iOS, never the FCM token. The plugin also picks it up by itself.
    final apns = await messaging.getAPNSToken();
    if (apns != null) await Hailbell.setPushToken(apns);
  } else {
    final token = await messaging.getToken();
    if (token != null) await Hailbell.setPushToken(token);
    messaging.onTokenRefresh.listen(Hailbell.setPushToken);
  }
}
```

Call `setUpPush()` after `Firebase.initializeApp()` and `HailbellSupport.configure()`. Ask for permission wherever the app already asks: `FirebaseMessaging.instance.requestPermission()` works, and so does `HailbellPush.requestPermission()`. After the customer's first message the chat offers to turn notifications on if they're off. Set `Hailbell.asksForNotifications = false` if your app asks at a better moment.

`HailbellPush.handleMessage` returns false for every message that isn't Hailbell's, including the silent `hb_check` message Hailbell sends to learn whether a customer deleted the app. Never show a notification for a data message your app doesn't recognise, or customers see a blank one.

### Android

- Replies are notification messages on the channel `hailbell_replies` ("YourApp Support"), which the plugin creates. In the background Android shows them itself. In the foreground, `handleMessage` shows them unless the chat is on screen. `firebase_messaging` also passes background notification messages to `onBackgroundMessage`; the plugin knows Android already showed those and doesn't show them twice.
- Tapping a reply opens the chat. If the tap starts the app, the plugin first opens the app, waits for your `configure`, gives `identify` a moment, then opens the chat. Call `identify` right after `configure` so the chat opens on the signed-in person's conversation.
- Campaign pushes from the Push page are data-only, so `handleMessage` shows them, in the foreground and from `onBackgroundMessage`, and confirms their delivery. They use the channel "Offers and updates" (`hailbell_offers`). If the app already has an offers channel, call `HailbellPush.setAndroidOffersChannel('<its id>')` before `configure` and enter the same ID as **Android: offers channel ID** in the push settings.
- A campaign tap opens its link as an intent for your app first, so your normal deep-link handling (`app_links`, `go_router`) receives it.
- The status bar icon is the one set for FCM in `AndroidManifest.xml` (`com.google.firebase.messaging.default_notification_icon`), so all pushes match. Without it Android draws a grey square.
- Marketing opt-in: on Android the notification category is the switch most people know. Read it at launch and on resume, and pass it on with `HailbellPush.setMarketing(...)`.

### iOS

1. In Xcode, open `ios/Runner.xcworkspace`, select **Runner › Signing & Capabilities** and add **Push Notifications**.
2. In `ios/Runner/AppDelegate.swift`, make the app delegate the notification center's delegate before launch finishes. Flutter passes notification taps on to plugins only then, and a tap that launched the app only reaches it if this runs this early:

   ```swift
   import UserNotifications

   override func application(_ application: UIApplication,
                             didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
     UNUserNotificationCenter.current().delegate = self
     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
   }
   ```

What the plugin does on iOS by itself:

- It receives the APNs token from the app delegate and passes it to Hailbell. Passing `getAPNSToken()` as above as well is harmless: the plugin sends each token once. Builds installed from Xcode register as sandbox; TestFlight and App Store builds as production.
- A reply tap opens the chat, including after a cold launch, once `configure` has run.
- Hailbell pushes show as a banner while the app is open. The plugin only answers for Hailbell's own notifications, so `firebase_messaging` and `flutter_local_notifications` keep deciding for theirs.
- A campaign tap is counted, then calls `HailbellPush.onOpen` if you set it, or opens the link. Set it before `configure` to route links yourself:

  ```dart
  HailbellPush.onOpen = (notification) {
    final url = notification.url;
    if (url == null) return false;
    router.go(url.path);   // your router
    return true;           // handled; false lets Hailbell open the link
  };
  ```

If **Send test notification** in the customer panel says the device has no token, check that **Push Notifications** is on, and that `setUpPush()` runs after the user allows notifications.

### Notification Service Extension (iOS, optional)

You need this only for Hailbell's campaign pushes: images, buttons, badge increments and delivery receipts. Chat replies work without it.

1. In Xcode, choose **File › New › Target › Notification Service Extension**. Name it `NotificationService` and set its **Minimum Deployments** to iOS 16.
2. Choose **File › Add Package Dependencies…**, enter `https://github.com/vidursaini/hailbell-ios`, choose **Up to Next Major Version** from `1.1.4`, and add the **HailbellNotificationService** library to the extension only, never to Runner. This works in CocoaPods projects too.
3. Replace the extension's class:

   ```swift
   import HailbellNotificationService
   final class NotificationService: HailbellNotificationService {}
   ```

4. In **Runner › Build Phases**, drag **Embed Foundation Extensions** above **Thin Binary**. Otherwise Xcode stops with "Cycle inside Runner".

For badge increments, give Runner and the extension the same App Group. Override `appGroup` in the extension, and call `HailbellPush.clearBadge(appGroup: 'group.com.yourcompany.yourapp')` when the app opens. The extension needs its own App ID in the developer portal, such as `com.yourcompany.yourapp.NotificationService`, with the same App Group.

### Marketing opt-in

New devices start opted out of marketing pushes. Add an "Offers and updates" switch to your notification settings, off by default, and pass it on:

```dart
await HailbellPush.setMarketing(isOn);
```

The choice is saved and sent with every token, so calling it at every launch costs nothing. Replies and transactional pushes arrive either way. App Store guideline 4.5.4 asks for this opt-in.

`HailbellPush.setTags({'plan': 'pro'})` adds data for segments and `{{tag.plan}}` in messages. `HailbellPush.optOut()` stops Hailbell pushes to the device until the next token.

## 7. Offers

An offer is a chat message with a button that opens one of your paywalls. `setPaywallPlacements` tells the dashboard which placements exist, and `onPaywall` opens the one the customer tapped. Call `purchased()` when they buy, so the dashboard counts purchases per offer:

```dart
Hailbell.onPaywall = (placement, purchased) async {
  final bought = await Paywalls.show(placement);   // Superwall, RevenueCat Paywalls or your own
  if (bought) purchased();
};
```

Name your offers under **Settings › Offers**. To connect purchases, add the Superwall or RevenueCat webhook from the app's **Revenue** settings in the dashboard, and send `superwallUserId` or `revenueCatUserId` with `setMetadata`.

## 8. What's automatic

The plugin uses the native chat, so all of this comes with it:

- Text and up to 4 photos per message, picked with the system photo picker, so no photo-library permission is needed.
- Ticks, typing dots and the online dot.
- An offline cache of the latest 100 messages, "Show earlier messages", and retries while offline.
- Review cards (the App Store review page, Play's in-app review) and offer cards.
- The AI notice and "AI" label when AI replies are on.
- The chat's own words in 14 languages.
- Colours from **Chat design**.

## 9. Store submission

The data the chat collects is the same as in a native app.

### App Store: App Privacy

Add these as **Linked to the user**, **not used for tracking**, with the purpose **App Functionality**. Skip any your app already declares.

| Data type | Why |
| --- | --- |
| Contact Info › Name, Email Address | Only if the app passes them to `identify` |
| User Content › Customer Support | Chat messages |
| User Content › Photos or Videos | Photos attached in the chat |
| Identifiers › User ID | A signed-in user id, `superwallUserId` or `revenueCatUserId` |
| Identifiers › Device ID | The chat's install id and the push token |
| Diagnostics › Other Diagnostic Data | App version, OS version, device model, language and time zone |
| Usage Data › Product Interaction | `track` signals, such as which button opened the chat |
| Purchases › Purchase History | Only if you connect the Superwall or RevenueCat webhook |

No new usage-description strings are needed: the photo picker runs out of process, and push uses the app's existing permission prompt.

### Google Play: Data safety

| Data type | Collected for |
| --- | --- |
| Personal info › Name, Email address | App functionality, only if passed to `identify` |
| Messages › Other in-app messages | App functionality (support chat) |
| Photos and videos › Photos | App functionality, only those the user attaches |
| App info and performance › Diagnostics | App version, Android version, device model, language and time zone |
| App activity › App interactions | `track` signals, such as which button opened the chat |
| Device or other IDs | The chat's install id and the FCM token |

Data is encrypted in transit and is deleted through the in-app account deletion (`deleteData`).

### Notes for App Review

> This version adds in-app support chat. Open it from Profile › Chat with us. Messages go to our support team, who reply in the chat and with a notification. When no one is available, an AI assistant may reply first; the chat says so before the first message and labels every AI reply. Photos are only sent when the user picks them with the system photo picker. Deleting the account in the app also deletes the chat from our servers. No sign-in is needed to use the chat.

Your privacy policy should mention customer support messages and name the AI provider that answers when AI replies are on.

## 10. Rollout checklist

- [ ] App created in the dashboard with iOS and Android platforms, bundle ID, Firebase project, accent and team photo
- [ ] `hailbell` added; iOS 16 and `minSdk 26` set
- [ ] `HailbellSupport` with both App IDs; `configure()` in `main()`
- [ ] Metadata: `appVersion`, `plan`, `superwallUserId` or `revenueCatUserId`
- [ ] Offers: `setPaywallPlacements` and `onPaywall`
- [ ] Entry points, with the unread dot on the header button
- [ ] `deleteData()` in account deletion, `reset()` on sign-out
- [ ] Android: token, `onTokenRefresh`, `onMessage` and `onBackgroundMessage` passed to Hailbell; FCM notification icon set
- [ ] iOS: Push Notifications capability; `UNUserNotificationCenter.current().delegate = self` in `AppDelegate`
- [ ] Marketing switch wired to `setMarketing`
- [ ] Tested on an Android emulator with Google Play: a message, a reply push with the app closed, tapping it, deletion
- [ ] Tested on an iPhone from Xcode (sandbox push), then on TestFlight (production push)
- [ ] App Privacy and Data safety updated

The native SDKs ship inside the plugin, so a Hailbell update reaches customers when you update the package and release the app. Server changes reach them right away.
