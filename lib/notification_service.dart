import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart'; 
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'ticket_detail_page.dart';
import 'dart:async';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // Stream para avisar que llegó algo nuevo
  final _onNotificationReceived = StreamController<void>.broadcast();
  Stream<void> get onNotificationReceived => _onNotificationReceived.stream;

  // Global Navigator Key para poder navegar desde aquí
  GlobalKey<NavigatorState>? _navigatorKey;
  
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> init() async {
    debugPrint('NotificationService: Starting init()');
    try {
      // 1. Initialize data for timezones
      tz.initializeTimeZones();
      debugPrint('NotificationService: Timezones initialized data');
      
      try {
        // 2. Get the actual timezone name from the device (e.g., "America/Mexico_City")
        final dynamic location = await FlutterTimezone.getLocalTimezone();
        final String timeZoneName = location is String ? location : location.name;
        
        // 3. Set the local location for the timezone package
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint('NotificationService: Local location successfully set to: $timeZoneName');
        debugPrint('NotificationService: Current time in this zone: ${tz.TZDateTime.now(tz.local)}');
      } catch (e) {
        debugPrint('NotificationService: Error setting local timezone: $e. Falling back to UTC.');
        try {
           tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (_) {}
      }
      
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification tapped local: ${details.payload}');
          _handlePayload(details.payload);
        },
      );
      debugPrint('NotificationService: Plugin successfully initialized');
      
      // 5. Firebase Messaging Setup
      await _initFirebaseMessaging();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        // Solicitar permiso POST_NOTIFICATIONS (Android 13+)
        await androidImpl?.requestNotificationsPermission();

        // Solicitar permiso de alarmas exactas
        try {
          await androidImpl?.requestExactAlarmsPermission();
        } catch (_) {}

        // ── Crear canales explícitamente para que aparezcan en Ajustes ──
        const channelReminders = AndroidNotificationChannel(
          'maintenance_reminders',
          'Recordatorios de Mantenimiento',
          description: 'Alertas de mantenimiento próximos y vencidos',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        const channelTickets = AndroidNotificationChannel(
          'tickets_channel',
          'Tickets de Soporte',
          description: 'Notificaciones de nuevos tickets y actualizaciones',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );

        await androidImpl?.createNotificationChannel(channelReminders);
        await androidImpl?.createNotificationChannel(channelTickets);
        debugPrint('NotificationService: Canales de notificación registrados');
      }
    } catch (globalError) {
      debugPrint('NotificationService: FATAL error in init: $globalError');
    }
  }

  Future<void> scheduleMaintenanceReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required int reminderDays,
    String repeatInterval = 'none', 
  }) async {
    debugPrint('NotificationService: Scheduling request - ID: $id, Date: $scheduledDate, Repeat: $repeatInterval');
    try {
      // Calculate the reminder date (e.g., 1 day before)
      final reminderDate = scheduledDate.subtract(Duration(days: reminderDays));
      
      // IMPORTANT: Construct the TZDateTime using the local timezone components
      // This ensures that 15:35 is 15:35 in the LOCAL time, not UTC.
      final tzScheduledDate = tz.TZDateTime(
        tz.local,
        reminderDate.year,
        reminderDate.month,
        reminderDate.day,
        reminderDate.hour,
        reminderDate.minute,
        reminderDate.second,
      );
      
      final now = tz.TZDateTime.now(tz.local);
      debugPrint('NotificationService: Current Local Time: $now');
      debugPrint('NotificationService: Target Local Time: $tzScheduledDate');

      if (repeatInterval == 'none') {
        if (tzScheduledDate.isBefore(now)) {
          debugPrint('NotificationService: Target time is in the past ($tzScheduledDate < $now). Skipping.');
          return;
        }

        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: tzScheduledDate,
          notificationDetails: _details(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'maintenance_$id',
        );
        debugPrint('NotificationService: Successfully scheduled for $tzScheduledDate');
      } else {
        RepeatInterval? interval;
        if (repeatInterval == 'hourly') interval = RepeatInterval.hourly;
        if (repeatInterval == 'daily') interval = RepeatInterval.daily;
        if (repeatInterval == 'weekly') interval = RepeatInterval.weekly;

        if (interval != null) {
          await flutterLocalNotificationsPlugin.periodicallyShow(
            id: id,
            title: title,
            body: body,
            repeatInterval: interval,
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: 'maintenance_repeat_$id',
          );
          debugPrint('NotificationService: Periodic notification scheduled ($repeatInterval)');
        }
      }
    } catch (e) {
      debugPrint('NotificationService: CRITICAL Error during scheduling: $e');
    }
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'maintenance_reminders',
        'Recordatorios de Mantenimiento',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint('NotificationService: Attempting immediate notification');
    try {
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(),
        payload: payload ?? 'immediate_$id',
      );
      debugPrint('NotificationService: Immediate notification displayed');
    } catch (e) {
      debugPrint('NotificationService: Error in immediate notification: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    debugPrint('NotificationService: Cancelling notification $id');
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  // ─── Firebase Messaging ───

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions (important for iOS/Android 13+)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('User granted permission: ${settings.authorizationStatus}');

    // Register token on server automatically
    final token = await getToken();
    if (token != null) {
      await registerTokenOnServer(token);
    }

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Foreground listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      if (message.notification != null) {
        showImmediateNotification(
          id: message.hashCode,
          title: message.notification?.title ?? 'Nuevo Ticket',
          body: message.notification?.body ?? '',
          payload: jsonEncode(message.data),
        );
      }
      // Avisar a quien esté escuchando que se actualice (ej: Dashboard)
      _onNotificationReceived.add(null);
    });

    // ─── NUEVO: Manejar clics cuando la App está en segundo plano ───
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification clicked (background): ${message.data}');
      _handleData(message.data);
    });

    // ─── NUEVO: Manejar clics cuando la App estaba CERRADA ───
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('Notification clicked (terminated): ${message.data}');
        _handleData(message.data);
      }
    });
  }

  void _handlePayload(String? payload) {
    if (payload == null) return;
    try {
      if (payload.startsWith('{')) {
        final data = jsonDecode(payload);
        _handleData(data);
      }
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }

  void _handleData(Map<String, dynamic> data) {
    final ticketId = data['ticket_id']?.toString();
    if (ticketId != null && _navigatorKey != null) {
      _navigatorKey!.currentState?.push(
        MaterialPageRoute(
          builder: (_) => TicketDetailPage(ticketId: ticketId),
        ),
      );
    }
  }

  Future<String?> getToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      return token;
    } catch (e) {
      debugPrint("NotificationService: Error getting token: $e");
      return null;
    }
  }

  Future<void> registerTokenOnServer(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final email = user?.email ?? 'admin';
      
      debugPrint('NotificationService: Registering token for $email in Supabase');
      
      await Supabase.instance.client.from('user_tokens').upsert({
        'email': email,
        'fcm_token': token,
      }, onConflict: 'fcm_token');
      
      debugPrint('NotificationService: Token registered successfully in Supabase');
    } catch (e) {
      debugPrint('NotificationService: Error registering token in Supabase: $e');
    }
  }

  /// Envía una notificación remota a través del puente PHP en Hostinger
  Future<void> sendRemoteNotification({
    required String title,
    required String body,
  }) async {
    final url = Uri.parse('https://reclutamiento-promsan.com/api-sistemas/tickets/api_notificar.php');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'titulo': title,
          'mensaje': body,
        }),
      );
      debugPrint('Notification Hub Status: ${response.statusCode}');
      debugPrint('Notification Hub Response: ${response.body}');
    } catch (e) {
      debugPrint('Error sending remote notification: $e');
    }
  }
}
