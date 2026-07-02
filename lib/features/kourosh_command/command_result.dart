class CommandResult {
  final String message;
  final String? undoLabel;
  final Future<void> Function()? undoAction;

  const CommandResult({
    required this.message,
    this.undoLabel,
    this.undoAction,
  });

  bool get canUndo => undoAction != null;
}
