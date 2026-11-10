import 'seller_phone.dart';

/// Valid Iraqi mobile in E.164, shared by OTP validation and submission.
/// Local leading zero and international dialing prefix must not reach Supabase.
String? iraqiMobileNumber(String input) {
  final phone = SellerPhone.parse(input);
  if (phone == null ||
      !RegExp(r'^9647[0-9]{9}$').hasMatch(phone.whatsappDigits)) {
    return null;
  }
  return phone.telTarget;
}
