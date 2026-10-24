import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
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
      tzdata.initializeTimeZones();
      // South Africa has one time zone and no daylight saving.
      tz.setLocalLocation(tz.getLocation('Africa/Johannesburg'));
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

  /// Repeats a reminder every day at [hour]:[minute] until it is cancelled.
  /// Ids from [baseId] up to [baseId] + 99 are kept for these, so a new set of
  /// times can replace the old one.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    if (!_ready) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: id,
        title: tr(title),
        body: tr(body),
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
          android: AndroidNotificationDetails('nolifa_care', 'Herd care reminders',
              channelDescription: 'Water, feed and vaccination reminders', importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('notifications: could not schedule: $e');
    }
  }

  Future<void> cancelRange(int from, int to) async {
    await init();
    if (!_ready) return;
    for (var i = from; i < to; i++) {
      try {
        await _plugin.cancel(id: i);
      } catch (_) {}
    }
  }
}
