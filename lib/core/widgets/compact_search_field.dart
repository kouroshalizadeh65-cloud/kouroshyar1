import 'package:flutter/material.dart';

/// A uniform compact search box used throughout the app.
/// Filtering starts from the first entered character through [onChanged].
class CompactSearchField extends StatefulWidget {
  const CompactSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.showClearButton = true,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool showClearButton;

  @override
  State<CompactSearchField> createState() => _CompactSearchFieldState();
}

class _CompactSearchFieldState extends State<CompactSearchField> {
  TextEditingController? _ownedController;

  TextEditingController get _controller => widget.controller ?? (_ownedController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant CompactSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(_refresh);
      if (widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      }
      _controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _ownedController?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        onTap: widget.onTap,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          prefixIcon: const Icon(Icons.search, size: 21),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          suffixIcon: widget.showClearButton && hasText
              ? IconButton(
                  tooltip: 'پاک کردن جستجو',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 19),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
