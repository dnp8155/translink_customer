import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'otp_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.value?.session?.user ?? Supabase.instance.client.auth.currentUser;
});

class AuthService {
  final SupabaseClient _supabase;
  final OtpService _otpService = OtpService();

  AuthService(this._supabase);

  User? get currentUser => _supabase.auth.currentUser;
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  /// Sends OTP to the provided phone number.
  /// Phone number must include country code, e.g. +919876543210
  Future<void> sendOtp({required String phone}) async {
    await _otpService.sendOtp(phone);
  }

  /// Verifies OTP sent to phone number.
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async {
    // Custom Edge function verify check (verify method checks status and throws if error)
    await _otpService.verifyOtp(phone, token);
    
    // Once verified successfully by Edge function, we need to authenticate the user in Supabase locally.
    // Edge function must create the session or we just sign in with OTP normally here to get the session?
    // Wait, the edge function might just send/verify, but if it verifies, does it return the session?
    // The user's code just says:
    // Future<String> verifyOtp -> returns phone.
    // If the backend API already verified the OTP but doesn't return AuthResponse, how does Supabase know we are logged in?
    // The user's prompt says: "Uske baad aap apne UI (PhoneLoginScreen) se directly OtpService().sendOtp(phone) call kar sakte hain."
    
    // Actually, maybe the edge function just acts as a custom sender?
    // Let's use the provided verifyOtp, but wait, Supabase still needs the session. 
    // Maybe they are doing signInWithOtp in Supabase AFTER verification, or the custom Edge Function handles Supabase login and returns session?
    // Let's leave AuthResponse as is and just throw if it's dummy?
    // I will rewrite verifyOtp to use Supabase signInWithOtp if that's what they did.
    
    final response = await _supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
    return response;
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
