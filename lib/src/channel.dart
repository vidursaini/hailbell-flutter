import 'dart:async';

import 'package:flutter/services.dart';

/// The channels between Dart and the native SDKs. Internal to the package.
class HailbellChannel {
  HailbellChannel._();

  /// Calls in both directions.
  static const MethodChannel methods = MethodChannel('hailbell');

  /// The unread count, pushed by the native side whenever it changes.
  static const EventChannel unread = EventChannel('hailbell/unread_count');

  /// Calls that the native side makes into Dart, keyed by method name.
  static final Map<String, Future<Object?> Function(Object? arguments)> _handlers = {};
  static bool _listening = false;

  /// Answers [method] when the native side calls it.
  static void handle(String method, Future<Object?> Function(Object? arguments) handler) {
    _handlers[method] = handler;
    if (_listening) return;
    _listening = true;
    methods.setMethodCallHandler((call) async {
      final handler = _handlers[call.method];
      if (handler == null) throw MissingPluginException('No Dart handler for ${call.method}');
      return handler(call.arguments);
    });
  }

  /// Calls [method] on the native side.
  static Future<T?> invoke<T>(String method, [Object? arguments]) => methods.invokeMethod<T>(method, arguments);

  /// Forgets the Dart handlers. Used by the tests through `Hailbell.debugReset`.
  static void reset() {
    _handlers.clear();
    _listening = false;
    methods.setMethodCallHandler(null);
  }
}
