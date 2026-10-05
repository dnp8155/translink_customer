import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  /// Launches WhatsApp with a predefined message.
  /// 
  /// Example message from PRD:
  /// "Hello, I found your truck on Return Translink for Mumbai -> Surat. I would like to discuss the transport requirement. Please contact me."
  static Future<bool> launchWhatsApp({
    required String phoneNumber,
    required String origin,
    required String destination,
  }) async {
    final String message = "Hello, I found your truck on Return Translink for $origin -> $destination. I would like to discuss the transport requirement. Please contact me.";
    final String encodedMessage = Uri.encodeComponent(message);
    
    // Ensure the phone number starts with country code (assuming +91 for India)
    String formattedPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (formattedPhone.length == 10) {
      formattedPhone = '91$formattedPhone';
    }

    final Uri whatsappUri = Uri.parse("https://wa.me/$formattedPhone?text=$encodedMessage");

    try {
      if (await canLaunchUrl(whatsappUri)) {
        return await launchUrl(
          whatsappUri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        print('Could not launch WhatsApp');
        return false;
      }
    } catch (e) {
      print('Exception while launching WhatsApp: $e');
      return false;
    }
  }
}
