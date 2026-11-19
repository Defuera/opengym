import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'countdown_signal.dart';

/// A local notification for the end of a countdown: the exercise name as the
/// title, "Time is up" as the text, the default sound. One fixed id, so a new
/// schedule replaces the old one.
///
/// The first [schedule] asks for the notification permission. When the person
/// says no, or anything fails, the countdown works without the sound and the
/// question is not asked again in the same app run.
class LocalCountdownSignal extends CountdownSignal {
  LocalCountdownSignal([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int _id = 4711;
  static const String _channel = 'countdown';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  Future<bool> _prepare() async {
    try {
      // The permission is asked below, not at initialisation.
      await _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final bool? ios = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final bool? droid = await android?.requestNotificationsPermission();
      if (android != null && droid != false) {
        await android.requestExactAlarmsPermission();
      }
      return (ios ?? droid ?? false);
    } catch (e) {
      debugPrint('countdown signal: setup failed: $e');
      return false;
    }
  }

  @override
  Future<void> schedule({required DateTime at, required String title}) async {
    try {
      // Asked once per app run: the answer is kept, a "no" is not asked again.
      final bool ok = await (_ready ??= _prepare());
      if (!ok) {
        return;
      }
      final bool exact = await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.canScheduleExactNotifications() ??
          true;
      await _plugin.zonedSchedule(
        id: _id,
        title: title,
        body: 'Time is up',
        // An absolute instant: the zone only names it, so UTC is fine.
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: const NotificationDetails(
          // In the foreground: sound yes, banner and list no.
          iOS: DarwinNotificationDetails(
            presentSound: true,
            presentAlert: false,
            presentBanner: false,
            presentList: false,
            presentBadge: false,
          ),
          android: AndroidNotificationDetails(
            _channel,
            'Countdown',
            channelDescription: 'Sounds when a countdown ends',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode:
            exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('countdown signal: schedule failed: $e');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      if (_ready == null) {
        return;
      }
      await _plugin.cancel(id: _id);
    } catch (e) {
      debugPrint('countdown signal: cancel failed: $e');
    }
  }
}
