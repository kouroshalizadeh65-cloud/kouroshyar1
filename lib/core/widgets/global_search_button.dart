import 'package:flutter/material.dart';

import '../../features/search/global_search_screen.dart';

class GlobalSearchButton extends StatelessWidget {
  const GlobalSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'جستجوی سراسری',
      icon: const Icon(Icons.search),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
      ),
    );
  }
}
