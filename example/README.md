# Hailbell example

A profile screen with the usual Hailbell entry points: a headset button with an unread dot, a "Chat with us" row, sign-in and sign-out, plan metadata, signals, notification permission, the marketing switch, the chat's look and account deletion.

```sh
flutter run --dart-define=HAILBELL_APP_ID=app_...
```

Use the App ID of the platform you run on: iOS and Android each have their own. Push replies also need Firebase on Android and the Push Notifications capability on iOS; see [GUIDE.md](../GUIDE.md).
