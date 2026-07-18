import 'package:flutter/material.dart';

import '../../features/search/global_search_screen.dart';
import 'compact_search_field.dart';

/// Compact global-search entry shown inside the main-page app bars.
/// Typing the first character opens the live global results screen.
class GlobalSearchField extends StatefulWidget {
  const GlobalSearchField({super.key});

  @override
  State<GlobalSearchField> createState() => _GlobalSearchFieldState();
}

class _GlobalSearchFieldState extends State<GlobalSearchField> {
  final TextEditingController _controller = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSearch([String? rawQuery]) async {
    if (_opening || !mounted) return;
    final query = (rawQuery ?? _controller.text).trim();
    _opening = true;
    FocusScope.of(context).unfocus();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GlobalSearchScreen(initialQuery: query.isEmpty ? null : query),
      ),
    );
    if (!mounted) return;
    _controller.clear();
    _opening = false;
  }

  void _onChanged(String value) {
    if (value.trim().isNotEmpty) {
      _openSearch(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompactSearchField(
      controller: _controller,
      hintText: 'جستجو...',
      onChanged: _onChanged,
      onSubmitted: _openSearch,
      onTap: () {
        // An empty tap keeps focus here; the first character opens live results.
      },
      showClearButton: false,
    );
  }
}
