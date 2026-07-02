class FocusModeState {
  static bool enabled = false;
  static int? caseId;
  static String? caseTitle;

  static void start({
    required int id,
    required String title,
  }) {
    enabled = true;
    caseId = id;
    caseTitle = title;
  }

  static void stop() {
    enabled = false;
    caseId = null;
    caseTitle = null;
  }
}
