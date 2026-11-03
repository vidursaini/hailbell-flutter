/// In-app support chat and push notifications for Flutter apps.
///
/// The plugin wraps Hailbell's native iOS and Android SDKs, so the chat is the same native screen
/// with ticks, typing, photos, review and offer cards.
///
/// ```dart
/// await Hailbell.configure(appId: 'app_...');
/// Hailbell.open();
/// ```
library;

export 'src/hailbell.dart' show Hailbell, HailbellException, HailbellFirebaseTokenProvider, HailbellPaywallHandler;
export 'src/hailbell_push.dart'
    show HailbellNotification, HailbellNotificationButton, HailbellPush, HailbellPushOpenHandler;
