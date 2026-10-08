import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    // Check auth status and navigate after animation completes
    Future.delayed(const Duration(milliseconds: 2500), () async {
      final prefs = await SharedPreferences.getInstance();
      final loggedInPhone = prefs.getString('logged_in_phone');
      if (mounted) {
        if (loggedInPhone != null && loggedInPhone.isNotEmpty) {
          try {
            dynamic profileData;
            try {
              profileData = await Supabase.instance.client
                  .from('profiles')
                  .select('id, full_name')
                  .eq('mobile', loggedInPhone)
                  .limit(1)
                  .maybeSingle();
            } catch (_) {
              profileData = await Supabase.instance.client
                  .from('profiles')
                  .select('id, full_name')
                  .eq('mobile_number', loggedInPhone)
                  .limit(1)
                  .maybeSingle();
            }

            if (mounted) {
              if (profileData != null) {
                // Profile exists in DB, fetch customer_id if possible
                try {
                  final custData = await Supabase.instance.client
                      .from('customers')
                      .select('id')
                      .eq('profile_id', profileData['id'])
                      .limit(1)
                      .maybeSingle();
                  if (custData != null && custData['id'] != null) {
                    await prefs.setString('customer_id', custData['id'].toString());
                  }
                } catch (_) {}
                
                context.go('/customer_search');
              } else {
                // No profile in DB, go to registration
                context.go('/registration', extra: loggedInPhone);
              }
            }
          } catch (e) {
            // Agar internet issue ho, try to go home anyway
            if (mounted) {
              context.go('/customer_search');
            }
          }
        } else {
          context.go('/login');
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Spacer(flex: 3),

              // Animated Logo Section
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36.0),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 290,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // Subtle bottom loading indicator & tagline
              FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 36.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connecting Return Transportation Opportunities',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
