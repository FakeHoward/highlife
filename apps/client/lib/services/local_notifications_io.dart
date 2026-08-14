import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/push_copy.dart';

/// Shows a local notification for an incoming UnifiedPush payload.
class LocalNotifications {
  LocalNotifications({this.onOpenRoom});

  final void Function(String roomId)? onOpenRoom;
  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onOpenRoom?.call(payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> showPush(Object? payload) async {
    await ensureReady();
    final body = pushNotificationBody(payload);
    final roomId = roomIdFromPush(payload);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'HighLife',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'highlife.messages',
          'Messages',
          channelDescription: 'New messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: roomId,
    );
  }
}
