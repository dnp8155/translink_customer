import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/network_service.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;
    final location = GoRouterState.of(context).uri.path;
    
    if (location.startsWith('/dashboard')) currentIndex = 0;
    else if (location.startsWith('/add_route')) currentIndex = 1;
    else if (location.startsWith('/activity')) currentIndex = 2;
    else if (location.startsWith('/account')) currentIndex = 3;

    final isOnlineAsyncValue = ref.watch(networkServiceProvider);
    final isOnline = isOnlineAsyncValue.value ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          if (!isOnline)
            Container(
              width: double.infinity,
              color: const Color(0xFFDC2626), // Red color for offline
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 4,
              ),
              child: const Text(
                'No Internet Connection - Offline Mode',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(context, icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', index: 0, currentIndex: currentIndex),
                _buildNavItem(context, icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Add Route', index: 1, currentIndex: currentIndex),
                _buildNavItem(context, icon: Icons.history_outlined, activeIcon: Icons.history, label: 'Activity', index: 2, currentIndex: currentIndex),
                _buildNavItem(context, icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account', index: 3, currentIndex: currentIndex),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, {required IconData icon, required IconData activeIcon, required String label, required int index, required int currentIndex}) {
    final isSelected = index == currentIndex;
    final color = isSelected ? const Color(0xFFFFC107) : const Color(0xFF6B7280);
    
    return InkWell(
      onTap: () {
        if (index == 0) context.go('/dashboard');
        else if (index == 1) context.go('/add_route');
        else if (index == 2) context.go('/activity');
        else if (index == 3) context.go('/account');
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSelected ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
