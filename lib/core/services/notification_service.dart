import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Request permission (important for iOS, also good practice for Android 13+)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission for notifications');
      
      // Get the FCM token for this device
      String? token = await _messaging.getToken();
      print('FCM Token: $token');
      // In a full implementation, you would save this token to Supabase partner_profiles table

      // Handle messages when app is in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print('Message also contained a notification: ${message.notification?.title}');
          // Could trigger a local snackbar or toast here
        }
      });
      
      // Background and terminated state handling would be setup in main.dart
    } else {
      print('User declined or has not accepted notification permissions');
    }
  }
}
