import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailbell/hailbell.dart';

const _channel = MethodChannel('hailbell');
const _unread = EventChannel('hailbell/unread_count');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every call the plugin made to the native side, in order.
  late List<MethodCall> calls;

  /// What the fake native side answers, by method name.
  late Map<String, Object? Function(MethodCall call)> answers;

  /// The fake native side's unread count events.
  late StreamController<int> unreadEvents;

  /// Makes the native side call [method] in Dart, as the plugin does for paywalls and tokens.
  Future<Object?> callDart(String method, [Object? arguments]) async {
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      'hailbell',
      _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      reply.complete,
    );
    final data = await reply.future;
    return data == null ? null : _channel.codec.decodeEnvelope(data);
  }

  setUp(() async {
    calls = [];
    answers = {};
    unreadEvents = StreamController<int>.broadcast();
    await Hailbell.debugReset();
    HailbellPush.debugReset();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      final answer = answers[call.method];
      return answer?.call(call);
    });
    messenger.setMockStreamHandler(
      _unread,
      MockStreamHandler.inline(onListen: (_, sink) => unreadEvents.stream.listen(sink.success)),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockStreamHandler(_unread, null);
  });

  MethodCall last(String method) => calls.lastWhere((c) => c.method == method);
  Map<Object?, Object?> argsOf(String method) => last(method).arguments as Map<Object?, Object?>;

  group('configure and open', () {
    test('configure sends the App ID, server and whether a push handler is set', () async {
      HailbellPush.onOpen = (_) => true;
      await Hailbell.configure(appId: 'app_123');
      expect(argsOf('configure'), {'appId': 'app_123', 'baseUrl': 'https://api.hailbell.com', 'pushOpenHandler': true});
    });

    test('a native configure error is a HailbellException and leaves Hailbell unconfigured', () async {
      answers['configure'] = (_) => throw PlatformException(code: 'bad_arguments', message: 'bad baseUrl');
      await expectLater(Hailbell.configure(appId: 'app_123', baseUrl: '::'), throwsA(isA<HailbellException>()));
      expect(Hailbell.open, throwsStateError);
    });

    test('configure rejects an empty App ID', () {
      expect(() => Hailbell.configure(appId: ''), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('open before configure is a clear error, not a broken chat', () {
      expect(Hailbell.open, throwsStateError);
      expect(calls.where((c) => c.method == 'open'), isEmpty);
    });

    test('open after configure opens the native chat', () async {
      await Hailbell.configure(appId: 'app_123');
      await Hailbell.open();
      expect(calls.last.method, 'open');
    });

    test('a native error surfaces as a HailbellException', () async {
      await Hailbell.configure(appId: 'app_123');
      answers['open'] = (_) => throw PlatformException(code: 'no_activity', message: 'No activity');
      await expectLater(
        Hailbell.open(),
        throwsA(isA<HailbellException>().having((e) => e.code, 'code', 'no_activity')),
      );
    });
  });

  group('identify', () {
    test('passes the identity token and details', () async {
      await Hailbell.identify(userId: 'u1', name: 'Ada', email: 'ada@example.com', identityToken: 'jwt');
      expect(argsOf('identify'), {
        'userId': 'u1',
        'name': 'Ada',
        'email': 'ada@example.com',
        'identityToken': 'jwt',
        'firebase': false,
      });
    });

    test('with firebaseIdToken, the native side asks Dart for a fresh token each session', () async {
      var asked = 0;
      await Hailbell.identify(name: 'Ada', firebaseIdToken: () async => 'token-${++asked}');
      expect(argsOf('identify')['firebase'], true);
      expect(await callDart('firebaseIdToken'), 'token-1');
      expect(await callDart('firebaseIdToken'), 'token-2');
    });

    test('a failing Firebase token provider answers null instead of throwing into native code', () async {
      await Hailbell.identify(firebaseIdToken: () async => throw StateError('signed out'));
      expect(await callDart('firebaseIdToken'), isNull);
    });

    test('reset forgets the Firebase token provider', () async {
      await Hailbell.identify(firebaseIdToken: () async => 'token');
      await Hailbell.reset();
      expect(calls.last.method, 'reset');
      expect(await callDart('firebaseIdToken'), isNull);
    });

    test('firebaseIdToken cannot be mixed with a user id or identity token', () {
      expect(() => Hailbell.identify(userId: 'u1', firebaseIdToken: () async => 't'), throwsArgumentError);
      expect(() => Hailbell.identify(identityToken: 'jwt', firebaseIdToken: () async => 't'), throwsArgumentError);
    });
  });

  group('context', () {
    test('metadata, signals and placements reach the native SDK unchanged', () async {
      await Hailbell.setMetadata({'plan': 'pro'});
      await Hailbell.track('paywall_decline', properties: {'placement': 'winback'});
      await Hailbell.track('chat_opened');
      await Hailbell.setPaywallPlacements(['winback', 'support_offer']);
      expect(calls.map((c) => c.method), ['setMetadata', 'track', 'track', 'setPaywallPlacements']);
      expect(calls[0].arguments, {
        'metadata': {'plan': 'pro'},
      });
      expect(calls[1].arguments, {
        'event': 'paywall_decline',
        'properties': {'placement': 'winback'},
      });
      expect(calls[2].arguments, {'event': 'chat_opened', 'properties': <String, String>{}});
      expect(calls[3].arguments, {
        'placements': ['winback', 'support_offer'],
      });
    });

    test('bug report calls reach the native SDK', () async {
      await Hailbell.trackScreen('Settings');
      Hailbell.shakeToReport = true;
      await pumpEventQueue();
      expect(Hailbell.shakeToReport, true);
      expect(argsOf('trackScreen'), {'name': 'Settings'});
      expect(argsOf('setShakeToReport'), {'value': true});
    });

    test('darkMode and asksForNotifications are kept and sent', () async {
      Hailbell.darkMode = true;
      Hailbell.asksForNotifications = false;
      await pumpEventQueue();
      expect(Hailbell.darkMode, true);
      expect(Hailbell.asksForNotifications, false);
      expect(argsOf('setDarkMode'), {'value': true});
      expect(argsOf('setAsksForNotifications'), {'value': false});
      Hailbell.darkMode = null;
      await pumpEventQueue();
      expect(argsOf('setDarkMode'), {'value': null});
    });

    test('the team photo is sent as bytes', () async {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      await Hailbell.setTeamPhoto(bytes);
      expect(argsOf('setTeamPhoto'), {'bytes': bytes});
    });
  });

  group('offers', () {
    test('an offer tap calls onPaywall, and purchased() reports the purchase', () async {
      final opened = <String>[];
      void Function()? buy;
      Hailbell.onPaywall = (placement, purchased) {
        opened.add(placement);
        buy = purchased;
      };
      await pumpEventQueue();
      expect(argsOf('setPaywallHandler'), {'enabled': true});

      expect(await callDart('paywall', {'placement': 'winback', 'id': 'p1'}), true);
      expect(opened, ['winback']);
      buy!();
      await pumpEventQueue();
      expect(argsOf('paywallPurchased'), {'id': 'p1'});
    });

    test('without a handler the tap is declined and the native side is told', () async {
      Hailbell.onPaywall = (placement, purchased) {};
      Hailbell.onPaywall = null;
      await pumpEventQueue();
      expect(argsOf('setPaywallHandler'), {'enabled': false});
      expect(await callDart('paywall', {'placement': 'winback', 'id': 'p1'}), false);
    });
  });

  group('push token', () {
    test('Android passes the FCM token through', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await Hailbell.setPushToken('fcm:APA91b-token');
      expect(argsOf('setPushToken'), {'token': 'fcm:APA91b-token'});
    });

    test('iOS accepts an APNs token', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final apns = 'a1' * 32;
      await Hailbell.setPushToken(apns);
      expect(argsOf('setPushToken'), {'token': apns});
    });

    test('iOS rejects an FCM token, which would never deliver a reply', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(() => Hailbell.setPushToken('dGVzdA:APA91bFCMtoken'), throwsArgumentError);
      expect(calls, isEmpty);
    });
  });

  group('unread count', () {
    test('follows the native count as a ValueListenable and a stream', () async {
      final listenable = Hailbell.unreadCount;
      final seen = <int>[];
      final sub = Hailbell.unreadCountStream.listen(seen.add);
      await pumpEventQueue();
      unreadEvents.add(2);
      await pumpEventQueue();
      unreadEvents.add(2);
      unreadEvents.add(0);
      await pumpEventQueue();
      expect(listenable.value, 0);
      expect(seen, [0, 2, 0]);
      await sub.cancel();
    });
  });

  group('deleteData', () {
    test('succeeds quietly', () async {
      await Hailbell.deleteData();
      expect(calls.single.method, 'deleteData');
    });

    test('throws when the server cannot be reached, so the app can stop', () async {
      answers['deleteData'] = (_) => throw PlatformException(code: 'delete_failed', message: 'offline');
      await expectLater(
        Hailbell.deleteData(),
        throwsA(isA<HailbellException>().having((e) => e.code, 'code', 'delete_failed')),
      );
    });
  });

  group('notifications', () {
    test('handleNotification ignores pushes that are not Hailbell replies', () async {
      expect(await Hailbell.handleNotification({'aps': 'x'}), false);
      expect(calls, isEmpty);
    });

    test('handleNotification opens the chat for a reply', () async {
      answers['handleNotification'] = (_) => true;
      expect(await Hailbell.handleNotification({'hailbell': '1', 'conversationId': 42}), true);
      expect(argsOf('handleNotification'), {
        'data': {'hailbell': '1', 'conversationId': '42'},
      });
    });
  });

  group('HailbellPush', () {
    test('isHailbell recognises replies and campaigns only', () {
      expect(HailbellPush.isHailbell({'hailbell': '1'}), true);
      expect(HailbellPush.isHailbell({'hb': '{"n":"x"}'}), true);
      expect(HailbellPush.isHailbell({'hb_check': '1'}), false);
      expect(HailbellPush.isHailbell({}), false);
    });

    test('handleMessage on Android sends string data, title and body', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answers['push.handleMessage'] = (_) => true;
      final handled = await HailbellPush.handleMessage(
        {'hailbell': '1', 'conversationId': 7, 'skip': null},
        title: 'YourApp Support',
        body: 'Hi',
      );
      expect(handled, true);
      expect(argsOf('push.handleMessage'), {
        'data': {'hailbell': '1', 'conversationId': '7'},
        'title': 'YourApp Support',
        'body': 'Hi',
      });
    });

    test('handleMessage on iOS only answers whether it is Hailbell, since APNs delivers those', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await HailbellPush.handleMessage({'hb': '{}'}), true);
      expect(await HailbellPush.handleMessage({'other': '1'}), false);
      expect(calls, isEmpty);
    });

    test('tags, marketing, opt-out, badge and offers channel reach the native SDK', () async {
      await HailbellPush.setTags({'plan': 'pro', 'old': null});
      await HailbellPush.setMarketing(true);
      await HailbellPush.optOut();
      await HailbellPush.clearBadge(appGroup: 'group.com.example');
      await HailbellPush.setAndroidOffersChannel('offers');
      expect(calls.map((c) => '${c.method} ${c.arguments}'), [
        'push.setTags {tags: {plan: pro, old: null}}',
        'push.setMarketing {enabled: true}',
        'push.optOut null',
        'push.clearBadge {appGroup: group.com.example}',
        'push.setOffersChannel {id: offers}',
      ]);
    });

    test('permission answers come back as booleans, and false when missing', () async {
      answers['push.requestPermission'] = (_) => true;
      expect(await HailbellPush.requestPermission(provisional: true), true);
      expect(argsOf('push.requestPermission'), {'provisional': true});
      expect(await HailbellPush.canNotify(), false);
    });

    test('onOpen receives the tapped notification and decides who opens the link', () async {
      final opened = <HailbellNotification>[];
      HailbellPush.onOpen = (note) {
        opened.add(note);
        return note.actionId == 'later';
      };
      await pumpEventQueue();
      expect(argsOf('push.setOpenHandler'), {'enabled': true});

      final handled = await callDart('pushOpened', {
        'id': 'n1',
        'url': 'yourapp://offer?source=support',
        'buttons': [
          {'id': 'later', 'text': 'Later', 'url': 'https://example.com/later'},
        ],
        'data': {'plan': 'pro'},
        'actionId': 'later',
      });
      expect(handled, true);
      final note = opened.single;
      expect(note.id, 'n1');
      expect(note.url, Uri.parse('yourapp://offer?source=support'));
      expect(note.imageUrl, isNull);
      expect(note.buttons.single.text, 'Later');
      expect(note.buttons.single.url, Uri.parse('https://example.com/later'));
      expect(note.data, {'plan': 'pro'});

      expect(await callDart('pushOpened', {'id': 'n2'}), false);
    });

    test('an onOpen handler that throws lets Hailbell open the link', () async {
      HailbellPush.onOpen = (_) => throw StateError('router not ready');
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      expect(await callDart('pushOpened', {'id': 'n1'}), false);
      expect(errors.single.library, 'hailbell');
    });
  });
}
