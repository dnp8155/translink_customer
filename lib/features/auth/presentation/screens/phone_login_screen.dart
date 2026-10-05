import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/otp_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final OtpService _otpService = OtpService();
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  String _selectedCountryCode = '+91';
  final List<String> _countryCodes = ['+91', '+1', '+44', '+61', '+971', '+65', '+49', '+33'];

  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _formattedFullPhone = '';

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid mobile number');
      return;
    }

    final fullPhone = '$_selectedCountryCode$rawPhone';
    final regex = RegExp(r'^\+[1-9]\d{6,15}$');
    if (!regex.hasMatch(fullPhone)) {
      setState(() => _errorMessage = 'Invalid phone number format');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final phoneRes = await _otpService.sendOtp(fullPhone);
      setState(() {
        _isOtpSent = true;
        _formattedFullPhone = phoneRes;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final enteredOtp = _otpControllers.map((c) => c.text.trim()).join();
    if (enteredOtp.length < 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final verifiedPhone = await _otpService.verifyOtp(_formattedFullPhone, enteredOtp);
      
      // Check if user exists in customers table
      final customerData = await Supabase.instance.client
          .from('customers')
          .select()
          .eq('phone_number', verifiedPhone)
          .maybeSingle();

      if (mounted) {
        if (customerData == null) {
          // New user, go to registration
          context.go('/registration', extra: verifiedPhone);
        } else {
          // Existing user, save login and go to home
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('logged_in_phone', verifiedPhone);
          if (mounted) context.go('/customer_search');
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isOtpSent
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () {
                  setState(() {
                    _isOtpSent = false;
                    _errorMessage = null;
                    for (final c in _otpControllers) {
                      c.clear();
                    }
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              // Logo
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _isOtpSent ? 'Enter Verification Code' : 'Login / Signup',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isOtpSent
                    ? 'We sent a code to $_formattedFullPhone'
                    : 'Enter your mobile number to continue',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),

              if (!_isOtpSent) ...[
                // Phone Input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCountryCode,
                            items: _countryCodes.map((code) {
                              return DropdownMenuItem(
                                value: code,
                                child: Text(code, style: const TextStyle(fontWeight: FontWeight.bold)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCountryCode = val);
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            hintText: 'Mobile number',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22, width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black87),
                          )
                        : const Text(
                            'Send OTP',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                  ),
                ),
              ] else ...[
                // OTP Input
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      height: 54,
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFFFC107), width: 2),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          } else if (value.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
                          if (index == 5 && value.isNotEmpty) {
                            _handleVerifyOtp();
                          }
                        },
                      ),
                    );
                  }),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isOtpSent = false;
                          _errorMessage = null;
                        });
                      },
                      child: const Text('Change number', style: TextStyle(color: Color(0xFF64748B))),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _handleSendOtp,
                      child: const Text('Resend code', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22, width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black87),
                          )
                        : const Text(
                            'Verify & Continue',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
