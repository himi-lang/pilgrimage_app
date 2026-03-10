class AppRoutes {
  static const String login = '/login';
  static const String modeSelection = '/mode_selection';
  static const String map = '/map';
  static const String versusLobby = '/versus/lobby';
  static const String versusPublicWait = '/versus/public_wait';

  static const String versusRoomPrefix = '/versus/room/';
  static const String versus = '/versus';

  static String versusRoom(String roomId) => '$versusRoomPrefix$roomId';
}
