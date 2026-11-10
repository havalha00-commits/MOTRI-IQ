/// تنظيف رقم هاتف البائع وتحويله إلى الصيغتين اللتين تحتاجهما أزرار التواصل.
///
/// لماذا ملف مستقل
/// ---------------
///
/// رقم الهاتف هو الجزء الوحيد القابل للخطأ في زرَّي «اتصال» و«واتساب»، وهو
/// لا يحتاج Widget ولا `url_launcher`. فصله هنا يجعل كل قاعدة فيه قابلة
/// للاختبار، ويمنع تكرار التحويل في كل صفحة تعرض رقم بائع.
///
/// لماذا يهم التنظيف
/// ----------------
///
/// البائع يكتب الرقم بصيغ مختلفة: `0770 123 4567` أو `+964 770 123 4567`
/// أو `٠٧٧٠١٢٣٤٥٦٧` بالأرقام العربية-الهندية. إرسال ما كُتب حرفيًّا إلى
/// `wa.me` يفشل، لأن واتساب لا يقبل مسافات ولا `+` ولا حروفًا غير رقمية.
library;

/// أقل عدد أرقام مقبول لرقم هاتف حقيقي.
///
/// ما دون ذلك ليس رقمًا ناقصًا بل خطأ إدخال، والزر الذي يظهر مع رقم ناقص
/// يعطي المستخدم تجربة مكسورة، فالأفضل ألا يظهر أصلًا.
const int _minDigits = 10;

/// أقصى عدد أرقام في صيغة E.164، وتجاوزه يعني أن الحقل لا يحتوي رقمًا واحدًا.
const int _maxDigits = 15;

/// رقم بائع مُنقّى، جاهز للاستعمال في `tel:` و`wa.me`.
class SellerPhone {
  const SellerPhone._(this.whatsappDigits);

  /// أرقام فقط بالصيغة الدولية: `9647701234567`.
  ///
  /// هذا ما يُرسَل إلى `wa.me` — بلا `+` وبلا مسافات، لأن أيًّا منهما يجعل
  /// الرابط يفتح صفحة خطأ بدل المحادثة.
  final String whatsappDigits;

  /// القيمة التي تُرسَل إلى `tel:`، وهي نفسها مع `+` في المقدّمة.
  ///
  /// تطبيقات الهاتف تحتاج `+` لتعرف أن `964` رمز دولة لا جزء من الرقم،
  /// وبدونه قد يفسّر الرقم كرقم محلي.
  String get telTarget => '+$whatsappDigits';

  /// يبقي أرقام ASCII فقط، بعد تحويل الأرقام العربية-الهندية والفارسية.
  ///
  /// المسافات والشرطات والأقواس و`+` كلّها تُحذف هنا بلا استثناء، لأنها لا
  /// تعني شيئًا في رقم الهاتف وتكسر الرابط إن بقيت.
  static String _toAsciiDigits(String input) {
    final StringBuffer out = StringBuffer();
    for (final int rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + (rune - 0x0660));
        continue;
      }
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + (rune - 0x06F0));
        continue;
      }
      final String ch = String.fromCharCode(rune);
      final int code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        out.write(ch);
      }
    }
    return out.toString();
  }

  /// يقرأ الرقم من أي مصدر في الإعلان ويُرجع `null` إن لم يكن صالحًا.
  ///
  /// لا يرمي استثناءً: الإعلان قد يكون بلا رقم، والـ`null` هنا هو ما يخفي
  /// الزر بدل أن يترك المستخدم يضغط زرًّا لا يفعل شيئًا.
  static SellerPhone? parse(Object? raw) {
    final String digits = _toAsciiDigits(raw?.toString() ?? '');

    // الصيغ المقبولة للرقم العراقي: `07XXXXXXXXX` محلي، و`9647XXXXXXXXX`
    // دولي، و`009647XXXXXXXXX` بصيغة الاتصال الدولي.
    String international;
    if (digits.startsWith('00')) {
      international = digits.substring(2);
    } else if (digits.startsWith('964')) {
      international = digits;
    } else if (digits.startsWith('0')) {
      international = '964${digits.substring(1)}';
    } else if (digits.length == 10 && digits.startsWith('7')) {
      international = '964$digits';
    } else {
      // رقم من بلد آخر مكتوب بصيغة دولية — لا يُختلق له رمز دولة.
      international = digits;
    }

    if (international.length < _minDigits) return null;
    if (international.length > _maxDigits) return null;
    return SellerPhone._(international);
  }
}
