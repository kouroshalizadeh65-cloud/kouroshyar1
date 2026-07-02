class SessionContext {
  static int? lastCaseId;
  static String? lastCaseTitle;
  static String? lastCommand;

  static void setLastCase({
    required int id,
    required String title,
  }) {
    lastCaseId = id;
    lastCaseTitle = title;
  }

  static void setLastCommand(String command) {
    lastCommand = command;
  }

  static void clear() {
    lastCaseId = null;
    lastCaseTitle = null;
    lastCommand = null;
  }
}
