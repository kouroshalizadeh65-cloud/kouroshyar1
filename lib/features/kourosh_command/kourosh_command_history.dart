
class KouroshCommandHistory {
  static final List<String> _items = [];

  static List<String> get items => List.unmodifiable(_items.reversed);

  static void add(String command) {
    final text = command.trim();
    if (text.isEmpty) return;
    _items.remove(text);
    _items.add(text);
    if (_items.length > 20) {
      _items.removeAt(0);
    }
  }

  static void clear() {
    _items.clear();
  }
}
