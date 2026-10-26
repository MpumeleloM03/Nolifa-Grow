import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show NoticeSender;

import 'package:ubuntu_core/tr.dart' show tr;
/// Real notifications on the phone. iOS asks the person once; after that this
/// shows a banner even while the app is open.
class PhoneNotifier implements NoticeSender {
  PhoneNotifier._();
  static final PhoneNotifier instance = PhoneNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('notifications: could not start: $e');
    }
  }

  @override
  Future<void> show({required String title, required String body}) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++,
        title: tr(title),
        body: tr(body),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true, presentBadge: true),
          android: AndroidNotificationDetails('nolifa_updates', 'Nolifa updates',
              channelDescription: 'Welcome back and what needs you', importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (e) {
      debugPrint('notifications: could not show: $e');
    }
  }
}
