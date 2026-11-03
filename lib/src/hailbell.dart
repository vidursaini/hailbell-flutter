import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'channel.dart';
import 'hailbell_push.dart';

/// Opens your paywall for [placement] when the customer taps an offer you sent in the chat.
///
/// Call [purchased] if they buy, so the dashboard counts the purchase against the offer.
typedef HailbellPaywallHandler = void Function(String placement, void Function() purchased);

/// Returns the signed-in user's current Firebase ID token, or null when nobody is signed in.
typedef HailbellFirebaseTokenProvider = Future<String?> Function();

/// Thrown when a Hailbell call fails, for example [Hailbell.deleteData] while offline.
class HailbellException implements Exception {
  /// Creates an exception with a [code] from the native SDK and a readable [message].
  const HailbellException(this.code, [this.message]);

  /// A short code, such as `delete_failed` or `no_activity`.
  final String code;

  /// What went wrong, in words.
  final String? message;

  @override
  String toString() => 'HailbellException($code${message == null ? '' : ': $message'})';
}

/// In-app support chat. Replies come from Discord, Telegram or the Hailbell dashboard.
///
/// It wraps Hailbell's native iOS and Android SDKs, so the chat is the same native screen as in
/// Swift and Kotlin apps.
///
/// ```dart
/// await Hailbell.configure(appId: 'app_...');
/// Hailbell.open();
/// ```
class Hailbell {
  Hailbell._();

  static bool _configured = false;
  static HailbellPaywallHandler? _onPaywall;
  static HailbellFirebaseTokenProvider? _firebaseIdToken;
  static bool? _darkMode;
  static bool _asksForNotifications = true;
  static final ValueNotifier<int> _unread = ValueNotifier<int>(0);
  static StreamSubscription<Object?>? _unreadSubscription;
  static final StreamController<int> _unreadChanges = StreamController<int>.broadcast();

  /// Call once at launch, before anything else, after `WidgetsFlutterBinding.ensureInitialized()`.
  ///
  /// [appId] is the platform's App ID from the dashboard (`app_...`). Use a different one for iOS
  /// and Android, since each platform has its own. It is public, so it can live in code.
  static Future<void> configure({required String appId, String baseUrl = 'https://api.hailbell.com'}) async {
    if (appId.isEmpty) throw ArgumentError.value(appId, 'appId', 'is empty');
    _listen();
    await _call('configure', {
      'appId': appId,
      'baseUrl': baseUrl,
      'pushOpenHandler': HailbellPush.onOpen != null,
    });
    _configured = true;
  }

  /// Opens the chat as a full-height sheet over your app.
  ///
  /// Throws a [StateError] if [configure] hasn't been called.
  static Future<void> open() async {
    if (!_configured) throw StateError('Call Hailbell.configure before Hailbell.open.');
    await _call('open');
  }

  /// Tells Hailbell who the user is.
  ///
  /// Only [identityToken] links the chat to the account across devices: an HS256 JWT from your
  /// backend, signed with the app's identity secret, with `sub` set to your user id. Without it,
  /// [userId], [name] and [email] are shown to you, but the chat stays tied to this install.
  ///
  /// Apps on Firebase Auth can pass [firebaseIdToken] instead of a token from a backend:
  ///
  /// ```dart
  /// Hailbell.identify(
  ///   name: user.displayName,
  ///   email: user.email,
  ///   firebaseIdToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  /// );
  /// ```
  ///
  /// Hailbell checks that token against the Firebase project set in the dashboard and uses the
  /// Firebase uid as the user id. ID tokens last an hour, so Hailbell calls [firebaseIdToken] for a
  /// fresh one each time it starts a session. Call [reset] on sign-out.
  static Future<void> identify({
    String? userId,
    String? name,
    String? email,
    String? identityToken,
    HailbellFirebaseTokenProvider? firebaseIdToken,
  }) async {
    if (firebaseIdToken != null && (identityToken != null || userId != null)) {
      throw ArgumentError('Pass firebaseIdToken on its own: the Firebase uid becomes the user id.');
    }
    _listen();
    _firebaseIdToken = firebaseIdToken;
    await _call('identify', {
      'userId': userId,
      'name': name,
      'email': email,
      'identityToken': identityToken,
      'firebase': firebaseIdToken != null,
    });
  }

  /// Context shown next to the conversation, such as `{'plan': 'free'}`.
  ///
  /// It is merged with what you sent before. `appVersion`, `os` and `locale` are sent
  /// automatically. Send `superwallUserId` or `revenueCatUserId` to show the customer's purchases.
  static Future<void> setMetadata(Map<String, String> metadata) => _call('setMetadata', {'metadata': metadata});

  /// Records a signal such as `paywall_decline` or `chat_opened`, shown next to the chat.
  static Future<void> track(String event, {Map<String, String> properties = const {}}) =>
      _call('track', {'event': event, 'properties': properties});

  /// The paywall placements an offer can open, so you can pick them by name in the dashboard.
  static Future<void> setPaywallPlacements(List<String> placements) =>
      _call('setPaywallPlacements', {'placements': placements});

  /// Opens a paywall when the customer taps an offer you sent in the chat.
  ///
  /// ```dart
  /// Hailbell.onPaywall = (placement, purchased) async {
  ///   if (await Paywalls.show(placement)) purchased(); // Superwall, RevenueCat or your own
  /// };
  /// ```
  static HailbellPaywallHandler? get onPaywall => _onPaywall;
  static set onPaywall(HailbellPaywallHandler? handler) {
    _listen();
    _onPaywall = handler;
    unawaited(_call('setPaywallHandler', {'enabled': handler != null}));
  }

  /// Registers this device for chat replies and Hailbell pushes.
  ///
  /// On Android, pass the FCM registration token (`FirebaseMessaging.instance.getToken()` and
  /// `onTokenRefresh`). On iOS, Hailbell sends through APNs directly: the plugin picks up the APNs
  /// token by itself. If you pass one, pass the APNs token (`getAPNSToken()`), never the FCM token.
  static Future<void> setPushToken(String token) {
    if (defaultTargetPlatform == TargetPlatform.iOS && !_apnsToken.hasMatch(token)) {
      throw ArgumentError.value(
        token,
        'token',
        'is not an APNs token. On iOS pass FirebaseMessaging.instance.getAPNSToken(), not getToken()',
      );
    }
    return _call('setPushToken', {'token': token});
  }

  static final RegExp _apnsToken = RegExp(r'^[0-9a-fA-F]{32,}$');

  /// Opens the chat when [data] is a tapped Hailbell reply notification. Returns false otherwise.
  ///
  /// The plugin already handles taps on its own notifications. Use this only when your app receives
  /// the notification payload itself, for example from a notification package that consumes taps.
  static Future<bool> handleNotification(Map<String, Object?> data) async {
    if (!data.containsKey('hailbell')) return false;
    return await HailbellChannel.invoke<bool>('handleNotification', {'data': _stringValues(data)}) ?? false;
  }

  /// Replies the customer hasn't read yet. Use it for a badge on your support button.
  static ValueListenable<int> get unreadCount {
    _listen();
    return _unread;
  }

  /// The same count as [unreadCount], as a stream. It starts with the current value.
  static Stream<int> get unreadCountStream async* {
    _listen();
    yield _unread.value;
    yield* _unreadChanges.stream;
  }

  /// On sign-out: clears the identity and the cached chat.
  ///
  /// The next session is this install's anonymous chat.
  static Future<void> reset() {
    _firebaseIdToken = null;
    return _call('reset');
  }

  /// Deletes the user's chat, images and details from Hailbell, for example when they delete their
  /// account in your app.
  ///
  /// It also clears [identify]. Throws a [HailbellException] if the server can't be reached, so
  /// call it before deleting the account and stop if it fails.
  static Future<void> deleteData() async {
    await _call('deleteData');
    _firebaseIdToken = null;
  }

  /// Whether the chat is dark. Null, the default, follows the phone. Set true for an always-dark app.
  static bool? get darkMode => _darkMode;
  static set darkMode(bool? value) {
    _darkMode = value;
    unawaited(_call('setDarkMode', {'value': value}));
  }

  /// After the first message, the chat offers to turn on notifications if they're off. Default true.
  ///
  /// Set false if your app asks for notification permission itself.
  static bool get asksForNotifications => _asksForNotifications;
  static set asksForNotifications(bool value) {
    _asksForNotifications = value;
    unawaited(_call('setAsksForNotifications', {'value': value}));
  }

  /// A photo of the person who replies, as PNG or JPEG bytes bundled in your app, so the chat
  /// header shows it at once and offline. Pass null to use the photo from the dashboard.
  ///
  /// ```dart
  /// final photo = await rootBundle.load('assets/support_photo.jpg');
  /// Hailbell.setTeamPhoto(photo.buffer.asUint8List());
  /// ```
  static Future<void> setTeamPhoto(Uint8List? bytes) => _call('setTeamPhoto', {'bytes': bytes});

  // Internal

  static Future<void> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      await HailbellChannel.invoke<void>(method, arguments);
    } on PlatformException catch (e) {
      throw HailbellException(e.code, e.message);
    }
  }

  static bool _wired = false;

  /// Starts listening to the native side: unread counts, paywalls and Firebase tokens.
  static void _listen() {
    if (_wired) return;
    _wired = true;
    HailbellChannel.handle('paywall', (arguments) async {
      final args = Map<Object?, Object?>.from(arguments as Map);
      final placement = args['placement'] as String;
      final id = args['id'] as String;
      final handler = _onPaywall;
      if (handler == null) return false;
      handler(placement, () => unawaited(_call('paywallPurchased', {'id': id})));
      return true;
    });
    HailbellChannel.handle('firebaseIdToken', (_) async {
      final provider = _firebaseIdToken;
      if (provider == null) return null;
      try {
        return await provider();
      } catch (_) {
        return null;
      }
    });
    _unreadSubscription = HailbellChannel.unread.receiveBroadcastStream().listen((count) {
      if (count is! int || count == _unread.value) return;
      _unread.value = count;
      _unreadChanges.add(count);
    }, onError: (Object _) {});
  }

  static Map<String, String> _stringValues(Map<String, Object?> data) => {
        for (final e in data.entries)
          if (e.value != null) e.key: e.value.toString()
      };

  /// Resets the Dart-side state. For tests only.
  @visibleForTesting
  static Future<void> debugReset() async {
    await _unreadSubscription?.cancel();
    _unreadSubscription = null;
    _wired = false;
    _configured = false;
    _onPaywall = null;
    _firebaseIdToken = null;
    _darkMode = null;
    _asksForNotifications = true;
    _unread.value = 0;
    HailbellChannel.reset();
  }
}
