// اختبار تنظيف رقم البائع قبل إرساله إلى `tel:` و`wa.me`.
//
// كل حالة هنا خطأ شائع في السوق العراقي: الرقم يُكتب بمسافات، أو بصيغة
// دولية، أو بالأرقام العربية-الهندية، أو يُدخل خطأً.

import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/contact/seller_phone.dart';

void main() {
  group('صيغة واتساب', () {
    test('«07XXXXXXXXX» يصبح «9647XXXXXXXXX»', () {
      expect(
        SellerPhone.parse('07701234567')!.whatsappDigits,
        '9647701234567',
        reason: 'الرقم العراقي المحلي بلا 0 وبلا رمز دولة يفشل في wa.me',
      );
    });

    test('المسافات والشرطات والأقواس تُحذف', () {
      expect(
        SellerPhone.parse('0770 123 4567')!.whatsappDigits,
        '9647701234567',
      );
      expect(
        SellerPhone.parse('+964 770 123 4567')!.whatsappDigits,
        '9647701234567',
      );
      expect(
        SellerPhone.parse('(0770) 123-4567')!.whatsappDigits,
        '9647701234567',
      );
    });

    test('لا `+` ولا مسافة داخل الرقم المُعاد', () {
      final SellerPhone phone = SellerPhone.parse('+964 770 123 4567')!;
      expect(phone.whatsappDigits.contains('+'), isFalse);
      expect(phone.whatsappDigits.contains(' '), isFalse);
      expect(RegExp(r'^\d+$').hasMatch(phone.whatsappDigits), isTrue);
    });

    test('«00964…» بصيغة الاتصال الدولي', () {
      expect(
        SellerPhone.parse('009647701234567')!.whatsappDigits,
        '9647701234567',
      );
    });

    test('«964…» يُترك كما هو', () {
      expect(
        SellerPhone.parse('9647701234567')!.whatsappDigits,
        '9647701234567',
      );
    });

    test('«7XXXXXXXXX» بلا صفر ولا رمز دولة', () {
      expect(
        SellerPhone.parse('7701234567')!.whatsappDigits,
        '9647701234567',
      );
    });

    test('الأرقام العربية-الهندية تُحوَّل إلى ASCII', () {
      expect(
        SellerPhone.parse('٠٧٧٠١٢٣٤٥٦٧')!.whatsappDigits,
        '9647701234567',
      );
      expect(
        SellerPhone.parse('۰۷۷۰۱۲۳۴۵۶۷')!.whatsappDigits,
        '9647701234567',
      );
    });

    test('رقم من بلد آخر لا يُختلق له رمز دولة', () {
      expect(
        SellerPhone.parse('+971 50 123 4567')!.whatsappDigits,
        '971501234567',
        reason: 'إضافة 964 لرقم خليجي تفتح محادثة مع رقم لا وجود له',
      );
    });
  });

  group('صيغة الهاتف', () {
    test('tel: يأخذ الصيغة الدولية مع `+`', () {
      expect(SellerPhone.parse('07701234567')!.telTarget, '+9647701234567');
    });

    test('«+» لا يُكرَّر إن كان الرقم دوليًّا فعلًا', () {
      expect(SellerPhone.parse('+9647701234567')!.telTarget, '+9647701234567');
    });
  });

  group('لا رقم = لا زر', () {
    test('إعلان بلا هاتف يُرجع null بدل رمي استثناء', () {
      expect(SellerPhone.parse(null), isNull);
      expect(SellerPhone.parse(''), isNull);
      expect(SellerPhone.parse('   '), isNull);
    });

    test('نص ليس رقمًا يُرجع null', () {
      expect(SellerPhone.parse('اتصل بي على الخاص'), isNull);
      expect(SellerPhone.parse('12345'), isNull, reason: 'أقل من ١٠ أرقام');
    });

    test('رقم طويل جدًّا يُرجع null', () {
      expect(SellerPhone.parse('9647701234567890'), isNull);
    });

    test('عمود فارغ في الإعلان يعني «لا رقم» لا خطأ', () {
      // `seller_phone` nullable: الإعلان بلا هاتف يجب أن يقرأ كـ`null`،
      // فالزرّان يختفيان بدل أن يرمي التطبيق استثناءً.
      final Map<String, dynamic> car = <String, dynamic>{
        'id': 'x',
        'seller_phone': null,
      };
      expect(SellerPhone.parse(car['seller_phone']), isNull);
    });
  });
}
