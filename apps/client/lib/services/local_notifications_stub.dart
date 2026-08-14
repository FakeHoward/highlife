class LocalNotifications {
  LocalNotifications({this.onOpenRoom});

  final void Function(String roomId)? onOpenRoom;

  Future<void> ensureReady() async {}

  Future<void> showPush(Object? payload) async {}
}
