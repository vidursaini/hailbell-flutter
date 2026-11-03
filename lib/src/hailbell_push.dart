import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'channel.dart';
import 'hailbell.dart';

/// A button on a Hailbell push.
@immutable
class HailbellNotificationButton {
  /// Creates a button. The plugin builds these from tapped pushes.
  const HailbellNotificationButton({required this.id, required this.text, this.url});

  /// The button's id, as set in the dashboard.
  final String id;

  /// The label shown on the button.
  final String text;

  /// Where the button leads, if it has its own link.
  final Uri? url;
}

/// A tapped Hailbell push, as your app sees it in [HailbellPush.onOpen].
@immutable
class HailbellNotification {
  /// Creates a notification. The plugin builds these from tapped pushes.
  const HailbellNotification({
    required this.id,
    this.url,
    this.imageUrl,
    this.buttons = const [],
    this.data = const {},
    this.actionId,
  });

  /// Builds a notification from the map the native side sends.
  factory HailbellNotification.fromMap(Map<Object?, Object?> map) {
    Uri? uri(Object? value) => value is String && value.isNotEmpty ? Uri.tryParse(value) : null;
    final buttons = (map['buttons'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((b) => HailbellNotificationButton(id: b['id'] as String, text: b['text'] as String, url: uri(b['url'])))
        .toList(growable: false);
    final data = map['data'];
    return HailbellNotification(
      id: map['id'] as String,
      url: uri(map['url']),
      imageUrl: uri(map['imageUrl']),
      buttons: buttons,
      data: data is Map ? Map<String, Object?>.from(data.map((k, v) => MapEntry('$k', v))) : const {},
      actionId: map['actionId'] as String?,
    );
  }

  /// The notification's id in Hailbell.
  final String id;

  /// The link to open: the tapped button's link, or else the notification's own.
  final Uri? url;

  /// The image shown with the notification, if any.
  final Uri? imageUrl;

  /// The notification's buttons.
  final List<HailbellNotificationButton> buttons;

  /// The `data` object sent with the notification.
  final Map<String, Object?> data;

  /// The id of the tapped button, or null when the notification itself was tapped.
  final String? actionId;
}

/// Decides what a tapped Hailbell push does. Return true if you handled [notification] yourself;
/// return false and Hailbell opens its link.
typedef HailbellPushOpenHandler = FutureOr<bool> Function(HailbellNotification notification);

/// Hailbell's push notifications, sent from the dashboard, the REST API or an AI agent.
class HailbellPush {
  HailbellPush._();

  static HailbellPushOpenHandler? _onOpen;
  static bool _wired = false;

  /// Asks for permission to show notifications, then registers for pushes. Returns whether it was
  /// granted.
  ///
  /// On iOS, [provisional] delivers quietly to the Notification Center without a prompt. On
  /// Android 12 and earlier, notifications need no permission and this returns whether they're on.
  /// Apps using `firebase_messaging` can call its `requestPermission()` instead.
  static Future<bool> requestPermission({bool provisional = false}) async =>
      await _invoke<bool>('push.requestPermission', {'provisional': provisional}) ?? false;

  /// Whether the user allows notifications. On Android it also checks Hailbell's reply channel.
  static Future<bool> canNotify() async => await _invoke<bool>('push.canNotify') ?? false;

  /// Key/value data about the user, for segments and `{{tag.plan}}` in messages.
  ///
  /// A null value removes the tag.
  static Future<void> setTags(Map<String, String?> tags) => _invoke<void>('push.setTags', {'tags': tags});

  /// Promotional pushes on or off. Transactional ones and chat replies still arrive.
  ///
  /// New devices start opted out. The choice is saved and sent with every token, so calling this at
  /// every launch with the same value costs nothing.
  static Future<void> setMarketing(bool enabled) => _invoke<void>('push.setMarketing', {'enabled': enabled});

  /// Stops Hailbell pushes to this device until the next [Hailbell.setPushToken].
  static Future<void> optOut() => _invoke<void>('push.optOut');

  /// True when an FCM data map came from Hailbell.
  static bool isHailbell(Map<String, Object?> data) => data.containsKey('hailbell') || data.containsKey('hb');

  /// Hands a `firebase_messaging` message to Hailbell. Returns false for messages that aren't
  /// Hailbell's, which your app handles as before.
  ///
  /// Call it from both `FirebaseMessaging.onMessage` and your `onBackgroundMessage` handler, with
  /// `message.data`, `message.notification?.title` and `message.notification?.body`. On Android it
  /// shows campaign pushes, and chat replies that arrive while the app is open and the chat is not.
  /// Replies in the background are already shown by Android, so it doesn't show them twice. On iOS,
  /// Hailbell pushes come through APNs, not FCM, and the plugin shows them by itself.
  static Future<bool> handleMessage(Map<String, Object?> data, {String? title, String? body}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return isHailbell(data);
    final strings = {
      for (final e in data.entries)
        if (e.value != null) e.key: e.value.toString()
    };
    return await _invoke<bool>('push.handleMessage', {'data': strings, 'title': title, 'body': body}) ?? false;
  }

  /// Called when the customer taps a Hailbell campaign push, or one of its buttons, on iOS.
  ///
  /// Return true if you opened the link yourself, for example with your router. Otherwise Hailbell
  /// opens it. Set it before [Hailbell.configure], so a tap that launched the app reaches it.
  ///
  /// On Android, taps open the link as an intent for your app, so your normal deep-link handling
  /// receives it and this isn't called.
  static HailbellPushOpenHandler? get onOpen => _onOpen;
  static set onOpen(HailbellPushOpenHandler? handler) {
    _onOpen = handler;
    _wire();
    unawaited(_invoke<void>('push.setOpenHandler', {'enabled': handler != null}));
  }

  /// Clears the app icon badge on iOS, and the count kept for badge increments in [appGroup].
  static Future<void> clearBadge({String? appGroup}) => _invoke<void>('push.clearBadge', {'appGroup': appGroup});

  /// Android only: the notification channel campaign pushes use, when your app already has an
  /// offers channel. Set it before [Hailbell.configure], and enter the same id in the dashboard's
  /// push settings. Hailbell then doesn't create its own channel.
  static Future<void> setAndroidOffersChannel(String channelId) =>
      _invoke<void>('push.setOffersChannel', {'id': channelId});

  static void _wire() {
    if (_wired) return;
    _wired = true;
    HailbellChannel.handle('pushOpened', (arguments) async {
      final handler = _onOpen;
      if (handler == null) return false;
      final note = HailbellNotification.fromMap(Map<Object?, Object?>.from(arguments as Map));
      try {
        return await handler(note);
      } catch (e, stack) {
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'hailbell'));
        return false;
      }
    });
  }

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await HailbellChannel.invoke<T>(method, arguments);
    } on PlatformException catch (e) {
      throw HailbellException(e.code, e.message);
    }
  }

  /// Resets the Dart-side state. For tests only.
  @visibleForTesting
  static void debugReset() {
    _onOpen = null;
    _wired = false;
  }
}
