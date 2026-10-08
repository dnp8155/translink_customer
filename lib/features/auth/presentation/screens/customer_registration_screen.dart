import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';

class CustomerRegistrationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const CustomerRegistrationScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<CustomerRegistrationScreen> createState() => _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState extends ConsumerState<CustomerRegistrationScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _selectedGender;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitDetails() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showSnackbar('Please enter your full name');
      return;
    }
    if (_selectedGender == null) {
      _showSnackbar('Please select your gender');
      return;
    }

    // 1. Internet Access Check
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      _showSnackbar('No internet connection. Please check your network.');
      return;
    }

    setState(() => _isLoading = true);

    // 2. Notification Permission Access
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (notifErr) {
      debugPrint('Notification permission error/notice: $notifErr');
    }

    // 3. Location Permission & Fetch Coordinates
    Position? currentPos;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          currentPos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 5)),
          );
        }
      }
    } catch (locErr) {
      debugPrint('Location fetch error: $locErr');
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      dynamic profileResp;
      String? customerId;

      try {
        final profileMap = {
          if (user != null) 'id': user.id,
          'full_name': name,
          'mobile': widget.phoneNumber,
          'email': email.isNotEmpty ? email : null,
          'role': 'customer',
        };

        if (user != null) {
          try {
            profileResp = await Supabase.instance.client
                .from('profiles')
                .upsert(profileMap, onConflict: 'id')
                .select()
                .single();
          } catch (e1) {
            // Fallback in case table has mobile_number instead of mobile
            profileResp = await Supabase.instance.client.from('profiles').upsert({
              'id': user.id,
              'full_name': name,
              'mobile_number': widget.phoneNumber,
              'email': email.isNotEmpty ? email : null,
              'role': 'customer',
            }, onConflict: 'id').select().single();
          }
        } else {
          try {
            profileResp = await Supabase.instance.client
                .from('profiles')
                .insert(profileMap)
                .select()
                .single();
          } catch (e2) {
            // Fallback for custom columns
            profileResp = await Supabase.instance.client.from('profiles').insert({
              'full_name': name,
              'mobile_number': widget.phoneNumber,
              'email': email.isNotEmpty ? email : null,
              'role': 'customer',
            }).select().single();
          }
        }

        // Pre-resolve location city/state/address if GPS position was captured
        String? resolvedCity;
        String? resolvedState;
        String? resolvedAddress;
        String? resolvedPincode;

        if (currentPos != null) {
          try {
            final token = 'pk.eyJ1IjoidG9tODE1NSIsImEiOiJjbXJheGkzZHoyNms2MndxcmE2N3NidzFhIn0.UT6Ql_m2sJScB7mKiIN9MQ';
            final url = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${currentPos.longitude},${currentPos.latitude}.json?access_token=$token&limit=1');
            final geoResponse = await http.get(url);
            if (geoResponse.statusCode == 200) {
              final data = json.decode(geoResponse.body);
              if (data['features'] != null && data['features'].isNotEmpty) {
                final feature = data['features'][0];
                if (feature['place_name'] != null) {
                  resolvedAddress = feature['place_name'];
                }
                if (feature['context'] != null) {
                  for (var c in feature['context']) {
                    final idStr = (c['id'] as String);
                    if (idStr.startsWith('place')) {
                      resolvedCity = c['text'];
                    } else if (idStr.startsWith('region')) {
                      resolvedState = c['text'];
                    } else if (idStr.startsWith('postcode')) {
                      resolvedPincode = c['text'];
                    }
                  }
                }
                if (resolvedCity == null && feature['text'] != null) {
                  resolvedCity = feature['text'];
                }
              }
            }
          } catch (geoEx) {
            debugPrint('Reverse geocoding error: $geoEx');
          }
        }

        String? finalProfileId = profileResp != null ? profileResp['id']?.toString() : user?.id;

        // customers table schema: id, profile_id, full_name, mobile, email, company_name, gst_number
        final customerPayload = {
          if (finalProfileId != null) 'profile_id': finalProfileId,
          'full_name': name,
          'mobile': widget.phoneNumber,
          if (email.isNotEmpty) 'email': email,
        };

        try {
          final custRes = await Supabase.instance.client
              .from('customers')
              .insert(customerPayload)
              .select('id')
              .single();
          customerId = custRes['id']?.toString();
          debugPrint('Customer created successfully: $customerId');
        } catch (custErr) {
          debugPrint('Customers insert error: $custErr');
          // Simple fallback with minimal required fields
          try {
            final custRes = await Supabase.instance.client.from('customers').insert({
              if (finalProfileId != null) 'profile_id': finalProfileId,
              'full_name': name,
              'mobile': widget.phoneNumber,
            }).select('id').maybeSingle();
            if (custRes != null) {
              customerId = custRes['id']?.toString();
            }
          } catch (e) {
            debugPrint('Final customer fallback insert notice: $e');
          }
        }
      } catch (dbError) {
        debugPrint('Supabase profile/customer insert error: $dbError');
        if (mounted) {
          _showSnackbar('Failed to save to database: $dbError');
          setState(() => _isLoading = false);
        }
        return; // Stop here if DB insert fails
      }

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('logged_in_phone', widget.phoneNumber);
        
        if (customerId != null) {
          await prefs.setString('customer_id', customerId);
        }
        
        _showSnackbar('Registration successful!', isSuccess: true);
        if (mounted) {
          context.go('/customer_search');
        }
      }
    } catch (e) {
      _showSnackbar('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Complete Profile', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Apni details bharein',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aapka account set up karne ke liye bas kuch aur jankari chahiye.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Name Input
              const Text('Full Name *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Ramesh Kumar',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Email Input (Optional)
              const Text('Email Address (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'e.g. ramesh@example.com',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Gender Selection
              const Text('Gender *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Male'),
                      value: 'Male',
                      groupValue: _selectedGender,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() => _selectedGender = value);
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Female'),
                      value: 'Female',
                      groupValue: _selectedGender,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() => _selectedGender = value);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black87),
                        )
                      : const Text(
                          'Save & Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
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
