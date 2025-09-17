import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Request permission for notifications
    await _requestPermissions();

    // Android initialization settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Para iOS: mostrar notificaciones incluso cuando la app está en primer plano
    final iosImplementation = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> _requestPermissions() async {
    // Request notification permission
    await Permission.notification.request();

    // For Android 13+ (API 33+), request additional permission
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - could navigate to specific screen based on payload
  }

  static Future<void> showAlarmNotification({
    required String sensorType,
    required String source,
    required double value,
    required double threshold,
    required bool isAbove,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'alarm_channel',
        'Sensor Alarms',
        channelDescription: 'Notifications for sensor threshold alarms',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF6366F1),
        enableVibration: true,
        playSound: true,
        showWhen: true,
        when: null,
        autoCancel: true,
        ongoing: false,
        channelAction: AndroidNotificationChannelAction.createIfNotExists,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final String title = '🚨 ${sensorType.toUpperCase()} Alert';
      final String comparisonText = isAbove ? 'above' : 'below';
      final String body =
          '$source: ${value.toStringAsFixed(1)} is $comparisonText threshold ${threshold.toStringAsFixed(1)}';

      final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      await _notifications.show(
        notificationId,
        title,
        body,
        platformDetails,
        payload: 'alarm|$sensorType|$source|$value|$threshold',
      );

    } catch (e) {
      // Handle error silently
    }
  }

  static Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Test notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0,
      'Test Notification',
      'Local notifications are working correctly!',
      platformDetails,
      payload: 'test',
    );
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}