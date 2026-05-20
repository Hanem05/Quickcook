import 'package:flutter/material.dart';

import 'all_recipes_landing_screen.dart';
import 'home_screen.dart';

class MainLandingShellScreen extends StatefulWidget {
  const MainLandingShellScreen({super.key});

  @override
  State<MainLandingShellScreen> createState() => _MainLandingShellScreenState();
}

class _MainLandingShellScreenState extends State<MainLandingShellScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs = const [
    AllRecipesLandingScreen(),
    HomeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        animationDuration: const Duration(milliseconds: 280),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen_rounded),
            label: 'Home',
          ),
        ],
        backgroundColor: cs.surface,
      ),
    );
  }
}
