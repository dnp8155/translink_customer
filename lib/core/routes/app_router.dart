import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/screens/phone_login_screen.dart';
import '../../features/auth/presentation/screens/customer_registration_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/home/presentation/screens/rapido_home_screen.dart';
import '../../features/splash/presentation/screens/splash_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const PhoneLoginScreen(),
    ),
    GoRoute(
      path: '/registration',
      builder: (context, state) {
        final phone = state.extra as String? ?? '';
        return CustomerRegistrationScreen(phoneNumber: phone);
      },
    ),
    GoRoute(
      path: '/customer_search',
      builder: (context, state) => const RapidoHomeScreen(),
    ),

    GoRoute(
      path: '/home',
      builder: (context, state) => const RapidoHomeScreen(),
    ),
  ],
);
