import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/contact/iraqi_phone.dart';

void main() {
  test('OTP uses the same correct E.164 number for all accepted inputs', () {
    for (final input in [
      '0770 123 4567',
      '+9647701234567',
      '009647701234567',
      '7701234567',
      '٠٧٧٠١٢٣٤٥٦٧',
      '۰۷۷۰۱۲۳۴۵۶۷'
    ]) {
      expect(iraqiMobileNumber(input), '+9647701234567', reason: input);
    }
  });
  test('rejects incomplete, non-Iraqi and non-mobile numbers', () {
    for (final input in [
      '',
      '0770',
      '+442079460123',
      '+9641770123456',
      '00964770123456789'
    ]) {
      expect(iraqiMobileNumber(input), isNull, reason: input);
    }
  });
}
