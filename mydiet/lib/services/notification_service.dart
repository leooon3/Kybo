import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart'; // [NEW] Required for permissions
import 'dart:io';
import 'storage_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Initialize Timezone Database
    tz.initializeTimeZones();

    // 2. AUTO-DETECT DEVICE TIMEZONE
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint("✅ Timezone detected: $timeZoneName");
    } catch (e) {
      debugPrint("⚠️ Timezone Error: $e");
      // Fallback only if detection fails
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    // [NOTE] request...Permission: false allows us to ask manually later
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint("Notification Tapped: ${details.payload}");
      },
    );

    _isInitialized = true;
  }

  /// Requests Notifications and Exact Alarm permissions.
  /// Returns true if at least notifications were granted.
  Future<bool> requestPermissions() async {
    bool notificationsGranted = false;

    if (Platform.isIOS) {
      final bool? result = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      notificationsGranted = result ?? false;
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      // 1. Request Notification Permission (Android 13+)
      final bool? granted = await androidImplementation
          ?.requestNotificationsPermission();
      notificationsGranted = granted ?? false;

      // 2. Request Exact Alarm Permission (Required for precise scheduling)
      // This is often a separate system dialog or setting.
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    }
    return notificationsGranted;
  }

  // --- DYNAMIC SCHEDULING ---

  Future<void> scheduleAllMeals() async {
    await cancelMealReminders();

    final storage = StorageService();
    final times = await storage.loadMealTimes();

    await _scheduleMeal(
      10,
      "Colazione ☕",
      "È ora di fare il pieno di energia!",
      times["colazione"] ?? "08:00",
    );
    await _scheduleMeal(
      11,
      "Pranzo 🥗",
      "Buon appetito! Segui il piano.",
      times["pranzo"] ?? "13:00",
    );
    await _scheduleMeal(
      12,
      "Cena 🍽️",
      "Chiudi la giornata con gusto.",
      times["cena"] ?? "20:00",
    );
  }

  Future<void> _scheduleMeal(
    int id,
    String title,
    String body,
    String timeStr,
  ) async {
    try {
      final parts = timeStr.split(":");
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      await _scheduleDaily(id, title, body, hour, minute);
    } catch (e) {
      debugPrint("⚠️ Error parsing time $timeStr: $e");
    }
  }

  Future<void> cancelMealReminders() async {
    await flutterLocalNotificationsPlugin.cancel(10);
    await flutterLocalNotificationsPlugin.cancel(11);
    await flutterLocalNotificationsPlugin.cancel(12);
  }

  Future<void> _scheduleDaily(
    int id,
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'meal_reminders_v2',
          'Meal Reminders',
          channelDescription: 'Reminders for your daily meals',
          importance: Importance.max,
          priority: Priority.high,
        );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("⚠️ Exact Alarm Failed, using Inexact: $e");
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
