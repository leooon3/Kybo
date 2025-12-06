import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const MethodChannel _platform = MethodChannel(
    'com.example.mydiet/timezone',
  );

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz_data.initializeTimeZones();

    try {
      final String timeZoneName = await _platform.invokeMethod(
        'getLocalTimezone',
      );
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint("Timezone initialized (Native): $timeZoneName");
    } catch (e) {
      debugPrint("Could not get local timezone: $e");
      tz.setLocalLocation(tz.UTC);
    }

    // [FIX] Changed icon to 'ic_launcher' (PNG) to avoid XML Adaptive Icon issues
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint("Notification clicked: ${details.payload}");
      },
    );

    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    _isInitialized = true;
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'meal_channel_v7', // [CHANGED] New ID
      'Pasti e Promemoria',
      description: 'Notifiche per i pasti',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      final bool? notifications = await androidImplementation
          ?.requestNotificationsPermission();
      // We still ask for exact alarms to ensure scheduling precision
      final bool? alarms = await androidImplementation
          ?.requestExactAlarmsPermission();

      return (notifications ?? false) && (alarms ?? false);
    }
    return false;
  }

  Future<void> showInstantNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'meal_channel_v7',
          'Pasti e Promemoria',
          channelDescription: 'Notifiche per i pasti',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(
      999,
      'Test Notifica',
      'Se leggi questo, le notifiche funzionano!',
      details,
    );
  }

  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    final scheduledDate = _nextInstanceOfTime(time);

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'meal_channel_v7', // Match Channel ID
          'Pasti e Promemoria',
          channelDescription: 'Notifiche per i pasti',
          importance: Importance.max,
          priority: Priority.high,
          // [FIX] Removed 'fullScreenIntent' (caused permissions issues)
          // [FIX] Removed 'category: alarm' (caused persistent icon issues)
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(''), // Ensures expansion
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      // [FIX] Switched to exactAllowWhileIdle.
      // It's robust but behaves like a Notification, not an Alarm Clock.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint(
      "✅ SCHEDULED (v7) '$title' per: $scheduledDate (${tz.local.name})",
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
