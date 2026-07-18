import 'package:flutter/material.dart';

class GlobalSettingsButton extends StatelessWidget {
  const GlobalSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'تنظیمات',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.pushNamed(context, '/settings'),
    );
  }
}
