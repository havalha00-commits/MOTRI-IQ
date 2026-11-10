import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backend_api.dart';
import 'auth/backend_auth_session.dart';
import 'contact/seller_phone.dart';
import 'contact/iraqi_phone.dart';
import 'plate_detector.dart';
import 'car_image_watermark.dart';
import 'market_images.dart';
import 'home_banner_ad.dart';
import 'l10n/app_delegates.dart';
import 'l10n/app_locale.dart';
import 'search/search_vocabulary.dart';
import 'search/smart_query.dart';
import 'search/saved_search_criteria.dart';
import 'seller_trust_cache.dart';
import 'ui/search_filters_sheet.dart';
import 'ui/language_picker_sheet.dart';
import 'ui/username_editor_dialog.dart';
import 'ui/message_hub_sheet.dart';
import 'ui/settled_dialog.dart';
import 'ui/generic_ad_editor_dialog.dart';
import 'ui/owned_vehicle_dialog.dart';
import 'ui/vehicle_offer_dialog.dart';
import 'ui/vehicle_sale_dialog.dart';
import 'ui/vehicle_report_dialog.dart';
import 'ui/user_report_dialog.dart';
import 'submission_id.dart';
import 'business/submission.dart';
import 'ui/content_direction.dart';
import 'ui/seller_profile_summary.dart';
import 'search/business_categories.dart';
import 'design/app_icons.dart';
import 'ui/carousel_position.dart';
import 'ui/app_state_panel.dart';
import 'ui/form_section.dart';
import 'ui/business_form_section.dart';
import 'ui/photo_gallery.dart';
import 'ui/seller_profile_header.dart';
import 'ui/seller_rating_dialog.dart';
import 'ui/otp_verification_dialog.dart';
import 'auth/auth_feedback.dart';
import 'auth/auth_capabilities.dart';
import 'ui/policy_document.dart';
import 'ui/ugc_policy_consent.dart';
import 'ui/activity_notification_tile.dart';
import 'ui/account_navigation_tile.dart';
import 'ui/car_request_editor_dialog.dart';
import 'ui/compact_listing_card.dart';
import 'ui/app_bottom_navigation.dart';
import 'ui/account_feed_state.dart';
import 'ui/account_scoped_view.dart';
import 'ui/web_app_frame.dart';
import 'release_channel.dart';
import 'wallet/wallet_admin_review_page.dart';
import 'wallet/wallet_top_up_page.dart';

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://frfqpxviebzkyvppuzdb.supabase.co');
const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_SjsZuIwSgA9G5Pqa1HZxDg_ABLQw959');

/// M1E local isolation: when true, startup must not contact production Supabase config.
/// Set via --dart-define=MOTRI_LOCAL_TEST=true (no project file edits required for values).
/// Outside this mode, existing behavior is preserved.
const bool kMotriLocalTest =
    bool.fromEnvironment('MOTRI_LOCAL_TEST', defaultValue: false);

const String kDarkModePref = 'motri.darkMode';
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://10.0.2.2:3000',
);
// رقم الدعم: المصدر الوحيد له في التطبيق، فلا رقم مكرَّر في أكثر من موضع.
// مكتوب بالشكل المحلي `07…`، وكل تحويل إلى صيغة دولية يمرّ من
// `supportWhatsAppUri` فلا يدخل يدويًا في أي رابط.
const String kSupportPhone = '07715339922';

/// رابط واتساب لرقم الدعم: `https://wa.me/9647715339922`.
///
/// `SellerPhone.parse` هو المكان الوحيد الذي يحوّل `07…` إلى `9647…`، وهو
/// محلٌّ مُختبَر، فيخرج الرابط بأرقام دولية **بلا `+` وبلا مسافات** كما
/// يشترط واتساب.
Uri supportWhatsAppUri() {
  // `kSupportPhone` رقم عراقي صحيح ومعادله مُختبَر، فلا يصل إلى `null`.
  final SellerPhone phone = SellerPhone.parse(kSupportPhone)!;
  return Uri.https('wa.me', '/${phone.whatsappDigits}');
}

/// رابط الاتصال: `tel:07715339922` بالرقم المحلي كما هو.
Uri supportCallUri() => Uri(scheme: 'tel', path: kSupportPhone);

Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// External apps may be unavailable (especially on simulators). Report failure
/// without allowing a platform exception to break navigation.
Future<void> openExternalLink(BuildContext context, Uri? uri,
    {String failureKey = 'fines_open_failed',
    Future<bool> Function(Uri)? launcher}) async {
  try {
    if (uri == null ||
        !await (launcher?.call(uri) ??
            launchUrl(uri, mode: LaunchMode.externalApplication))) {
      throw StateError('External application unavailable');
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(failureKey))),
    );
  }
}

// انحناء موحّد لكل إطارات الصور في التطبيق: قيمة واحدة مهما اختلف الموديل
// أو الشاشة، فيبدو العرض متناسقاً بدل أن تتغيّر الزوايا من بطاقة إلى أخرى.
const double imgRadius = 16;

// نسبة إطار واحدة لصور السيارات (4:3 أفقي). سكربت تطبيع الصور يقصّ كل صورة
// مصدرية إلى هذه النسبة، فيبقى قصّ BoxFit.cover متطابقاً في كل الشاشات
// (البانر، الشبكة، صفحة التفاصيل، المصغّرات) ولا تُقطع السيارة من أطرافها.
const double carPhotoAspect = 4 / 3;

final ValueNotifier<ThemeMode> darkModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.light);

final ValueNotifier<bool> carGridLayoutNotifier = ValueNotifier<bool>(true);

ThemeData buildAppTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final Color surface = dark ? const Color(0xFF18181C) : Colors.white;
  final Color canvas = dark ? const Color(0xFF0E0E11) : const Color(0xFFF8FAFB);
  final Color line = dark ? const Color(0xFF2C2C34) : const Color(0xFFE5E7EB);
  final Color lineStrong =
      dark ? const Color(0xFF3E3E49) : const Color(0xFFD1D5DB);
  final Color ink = dark ? const Color(0xFFF2F2F4) : const Color(0xFF111827);
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: red,
    brightness: brightness,
  ).copyWith(
    primary: red,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF482430) : const Color(0xFFF8E8ED),
    onPrimaryContainer: dark ? const Color(0xFFFFB4C3) : red,
    surface: surface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerHighest: surface,
    surfaceBright: surface,
    surfaceTint: Colors.transparent,
    onSurface: ink,
    outline: lineStrong,
    outlineVariant: line,
  );
  final scriptFont = appLocale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans';
  final buttonTextStyle = TextStyle(
      fontFamily: 'MotriLatin',
      fontFamilyFallback: [scriptFont],
      fontWeight: FontWeight.w700);
  final BorderRadius radius = BorderRadius.circular(14);
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: scheme.onPrimaryContainer),
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: line,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.onPrimaryContainer,
      selectionColor: scheme.onPrimaryContainer.withValues(alpha: 0.2),
      selectionHandleColor: scheme.onPrimaryContainer,
    ),
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: line),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          fontFamily: 'MotriLatin',
          fontFamilyFallback: [
            appLocale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans'
          ],
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w800),
      iconTheme:
          IconThemeData(size: 24, weight: 400, opticalSize: 24, color: ink),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: red,
        foregroundColor: Colors.white,
        disabledBackgroundColor: lineStrong,
        disabledForegroundColor: surface,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonTextStyle,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: red,
        foregroundColor: Colors.white,
        disabledBackgroundColor: lineStrong,
        disabledForegroundColor: surface,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonTextStyle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onPrimaryContainer,
        backgroundColor: surface,
        side: BorderSide(color: lineStrong),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonTextStyle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onPrimaryContainer,
        textStyle: buttonTextStyle,
      ),
    ),
    iconTheme: IconThemeData(
        size: 24,
        weight: 400,
        opticalSize: 24,
        color: dark ? const Color(0xFFF2F2F4) : const Color(0xFF374151)),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelStyle:
          WidgetStateTextStyle.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.error)
                  ? scheme.error
                  : states.contains(WidgetState.focused)
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant)),
      errorMaxLines: 4,
      filled: true,
      prefixIconColor: WidgetStateColor.resolveWith((states) =>
          states.contains(WidgetState.focused)
              ? scheme.onPrimaryContainer
              : ink.withValues(alpha: 0.6)),
      suffixIconColor: ink.withValues(alpha: 0.6),
      fillColor: dark ? const Color(0xFF1C1C22) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.onPrimaryContainer, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      side: BorderSide(color: line),
      labelStyle: buttonTextStyle.copyWith(
        color: dark ? const Color(0xFFF2F2F4) : const Color(0xFF111827),
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final bool on = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'MotriLatin',
          fontFamilyFallback: [scriptFont],
          fontSize: 12,
          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          color: on
              ? scheme.onPrimaryContainer
              : (dark ? const Color(0xFFA8A8B2) : const Color(0xFF6B7280)),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final bool on = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: on
              ? scheme.onPrimaryContainer
              : (dark ? const Color(0xFFA8A8B2) : const Color(0xFF6B7280)),
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      titleAlignment: ListTileTitleAlignment.center,
      iconColor: dark ? const Color(0xFFF2F2F4) : const Color(0xFF374151),
    ),
    useMaterial3: true,
    fontFamily: 'MotriLatin',
    fontFamilyFallback: [
      appLocale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans'
    ],
    textTheme: const TextTheme(
      titleLarge:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.35),
      titleMedium:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
      titleSmall:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, height: 1.45),
      labelLarge:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
    ),
  );
}

Widget _buildHomeCarGrid(
    BuildContext context, List<Map<String, dynamic>> cars) {
  return ValueListenableBuilder<bool>(
    valueListenable: carGridLayoutNotifier,
    builder: (context, isGrid, _) {
      if (!isGrid) {
        return Column(
          children: [
            for (final car in cars)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CarCard(
                  key: ValueKey(car['id']),
                  car: car,
                ),
              ),
          ],
        );
      }
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 320 ? 1 : 2;
          final tileWidth =
              (constraints.maxWidth - (columns - 1) * 8) / columns;
          final cardHeight = (tileWidth / 1.65 + 104 * scale)
              .clamp(224.0 * scale, 360.0 * scale);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: cardHeight,
            ),
            itemCount: cars.length,
            itemBuilder: (context, index) {
              final car = cars[index];
              return CarCard(
                key: ValueKey(car['id']),
                car: car,
                square: true,
                homeSectionStyle: true,
              );
            },
          );
        },
      );
    },
  );
}

Future<void> setDarkMode(bool enabled) async {
  if (AppColors.isDark == enabled) return;
  AppColors.isDark = enabled;
  darkModeNotifier.value = enabled ? ThemeMode.dark : ThemeMode.light;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDarkModePref, enabled);
  } catch (_) {}
}

Future<void> setCarGridLayout(bool enabled) async {
  final previous = carGridLayoutNotifier.value;
  carGridLayoutNotifier.value = enabled;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('motri.cars.grid_layout', enabled)) {
      throw StateError('Could not persist car layout preference');
    }
  } catch (_) {
    carGridLayoutNotifier.value = previous;
    rethrow;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Limit image cache to ~100MB / 200 images to prevent memory bloat on slow networks.
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool saved = prefs.getBool(kDarkModePref) ?? false;
    AppColors.isDark = saved;
    darkModeNotifier.value = saved ? ThemeMode.dark : ThemeMode.light;
    carGridLayoutNotifier.value =
        prefs.getBool('motri.cars.grid_layout') ?? true;
  } catch (_) {}
  await loadAppLocale();
  // M1E-ISOLATION: in local test mode, do not initialize Supabase with embedded production defaults.
  // This prevents startup from contacting production Supabase config. Market image upload uses backend JWT only.
  if (!kMotriLocalTest) {
    await Supabase.initialize(
        url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  backendAuthSession = BackendAuthSession(baseUrl: backendUrl);
  runApp(const MotriIqApp());
  unawaited(_restoreBackendSession());
}

Future<void> _restoreBackendSession() async {
  try {
    await backendAuthSession.restoreSession();
  } on AuthSessionException catch (error) {
    debugPrint('Backend session restoration failed: $error');
  }
}

final bool supabaseInitialized = !kMotriLocalTest;
// In M1E local test mode Supabase is never initialized (no production contact).
// Outside test mode, behavior is unchanged. In test mode, direct `supabase` access throws (fail-fast) if reached.
SupabaseClient get supabase {
  if (!supabaseInitialized) {
    throw StateError('Supabase is disabled in M1E local test mode');
  }
  return Supabase.instance.client;
}

SupabaseClient? get supabaseClientOrNull =>
    supabaseInitialized ? Supabase.instance.client : null;
late BackendAuthSession backendAuthSession;

String? get _authenticatedUserId =>
    backendAuthSession.user?.id ?? supabaseClientOrNull?.auth.currentUser?.id;

String _backendDisplayName({String? fallback}) {
  final u = backendAuthSession.user;
  final v = (u?.fullName ?? '').trim().isNotEmpty
      ? u!.fullName!.trim()
      : (u?.username ?? '').trim().isNotEmpty
          ? u!.username!.trim()
          : (u?.email ?? '').trim();
  if (v.isNotEmpty) return v;
  final fb = fallback?.trim();
  if (fb != null && fb.isNotEmpty) return fb;
  final su = supabaseClientOrNull?.auth.currentUser;
  final meta = su?.userMetadata?['full_name']?.toString().trim();
  if (meta != null && meta.isNotEmpty) return meta;
  return su?.email ?? t('default_seller_name');
}

BackendApi backendApi = BackendApi(
  baseUrl: backendUrl,
  backendOnly:
      kMotriLocalTest, // M1E-ISOLATION: market/app test mode uses backend JWT only, no Supabase token fallback.
  accessTokenAsync: () async {
    final t = await backendAuthSession.validAccessToken();
    if (t != null && t.isNotEmpty) return t;
    if (kMotriLocalTest) return null;
    return supabaseClientOrNull?.auth.currentSession?.accessToken;
  },
  accessToken: () =>
      backendAuthSession.accessToken ??
      (kMotriLocalTest
          ? null
          : supabaseClientOrNull?.auth.currentSession?.accessToken),
  backendAccessTokenAsync: () => backendAuthSession.validAccessToken(),
  backendAccessToken: () => backendAuthSession.accessToken,
);

/// ذاكرةBatch واحدة لل-session: المفضلة + سمعة البائع + توثيقه.
/// قبلها كان كل CarCard يرسل 1–2 طلباً خاصاً به في initState، فتصير
/// الصفحة الواحدة ~40–100 طلباً. الآن الصفحة تجلب الدفعة مرة واحدة
/// والبطاقات تقرأ من الذاكرة. تُبطَل عند تبديل المستخدم (انظر signOut).
final TrustCache trustCache = TrustCache(
  backendAuthSession,
  loadSellerReviews: (sellerIds) async {
    final response = await backendApi.get(
      'sellers/reviews',
      query: {'seller_ids': sellerIds.join(',')},
      anonymous: true,
    );
    if (response is! Map ||
        response['success'] != true ||
        response['data'] is! List) {
      throw const BackendApiException('تعذر تحميل تقييمات البائعين');
    }
    return List<Map<String, dynamic>>.from(response['data'] as List);
  },
  loadSellerVerifications: (sellerIds) async {
    final response = await backendApi.get(
      'sellers/verifications',
      query: {'ids': sellerIds.join(',')},
      anonymous: true,
    );
    if (response is! Map ||
        response['success'] != true ||
        response['data'] is! List) {
      throw const BackendApiException('تعذر تحميل توثيق البائعين');
    }
    return List<Map<String, dynamic>>.from(response['data'] as List);
  },
  loadFavoriteRows: (userId) async {
    if (backendAuthSession.user?.id != userId) {
      throw const BackendApiException('تغير الحساب الحالي');
    }
    // TrustCache must distinguish auth failure from a successful empty response.
    // Do not convert Backend authentication required into [] (would hide saved data).
    final response = await backendApi.get('favorites', backendOnly: true);
    if (response is! Map || response['data'] is! List) {
      throw const BackendApiException('تعذر تحميل المفضلة');
    }
    return List<Map<String, dynamic>>.from(response['data'] as List);
  },
);

/// اللون الرئيسي للتطبيق: أحمر عنابي هادئ (نفس عائلة اللون في المرجع).
const red = Color(0xFF8B0D25);
const redSoft = Color(0xFFB11230);

final RegExp _thousandsSeparator = RegExp(r'\B(?=(\d{3})+(?!\d))');
final RegExp _usernamePattern = RegExp(r'^[a-zA-Z0-9_]{3,24}$');

class AppColors {
  AppColors._();

  static bool isDark = false;

  static Color get surface =>
      isDark ? const Color(0xFF18181C) : const Color(0xFFFFFFFF);

  static Color get scaffold =>
      isDark ? const Color(0xFF0E0E11) : const Color(0xFFF8FAFB);

  static Color get placeholder =>
      isDark ? const Color(0xFF1C1C22) : const Color(0xFFFFFFFF);

  static Color get text =>
      isDark ? const Color(0xFFF2F2F4) : const Color(0xFF111827);

  static Color get textStrong =>
      isDark ? const Color(0xFFEDEDF0) : const Color(0xFF1F2937);

  static Color get textMuted =>
      isDark ? const Color(0xFFA8A8B2) : const Color(0xFF4B5563);

  static Color get textFaint =>
      isDark ? const Color(0xFF8A8A95) : const Color(0xFF6B7280);

  static Color get textHint =>
      isDark ? const Color(0xFF71717C) : const Color(0xFF9CA3AF);

  static Color get border =>
      isDark ? const Color(0xFF2C2C34) : const Color(0xFFE5E7EB);

  static Color get borderStrong =>
      isDark ? const Color(0xFF3E3E49) : const Color(0xFFD1D5DB);

  static Color get emptyGradientA =>
      isDark ? const Color(0xFF1B1B21) : const Color(0xFFE8E8E8);

  static Color get emptyGradientB =>
      isDark ? const Color(0xFF23232B) : const Color(0xFFF2F2F2);

  static Color get emptyGradientTint =>
      isDark ? const Color(0xFF2B1A1E) : const Color(0xFFFBE7EB);

  /// ظل ناعم موحّد يُستخدم في الكروت والأقسام البيضاء.
  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x0D101828),
      blurRadius: 18,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];

  /// ظل أخف للعناصر الصغيرة (شارات، أزرار ثانوية).
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: Color(0x0A101828),
      blurRadius: 10,
      spreadRadius: -2,
      offset: Offset(0, 3),
    ),
  ];
}

Color get card => AppColors.surface;
Color get panel => AppColors.surface;

/// عميل HTTP مشترك لإعادة استخدام الاتصالات وتقليل زمن الاستجابة عند تحميل صور متعددة.
final _sharedHttpClient = http.Client();

/// إطار موحّد لكل صور السيارات في التطبيق: نفس الانحناء، ونسبة العرض نفسها،
/// ونفس العنصر النائب أثناء التحميل وعند فشل الرابط، مع تلاشٍ ناعم عند
/// الوصول. كل صورة تمر من هنا، فيبدو العرض وكأنها من مصدر واحد.
class CarPhoto extends StatelessWidget {
  const CarPhoto({
    super.key,
    required this.urls,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.radius = imgRadius,
    this.width,
    this.height,
    this.placeholderColor,
    this.placeholderIcon = Icons.directions_car_rounded,
    this.iconScale = 0.3,
    this.showWatermark = false,
    this.plateRegions,
  });

  /// روابط الصورة، الأول هو الذي يُعرض (بقية الصور تُعرض في المعرض).
  final List<String> urls;

  /// نسبة الإطار الثابتة (carPhotoAspect) أو null لملء المساحة المتاحة.
  final double? aspectRatio;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final Color? placeholderColor;
  final IconData placeholderIcon;

  /// نسبة حجم أيقونة العنصر النائب من ضلع الإطار الأصغر.
  final double iconScale;
  final bool showWatermark;

  /// مناطق لوحة السيارة للصورة الأولى (نسبية 0.0 إلى 1.0).
  /// إذا توفرت، يتم طمس اللوحة بمستطيل معتم فوق الصورة.
  final List<PlateRegion>? plateRegions;

  @override
  Widget build(BuildContext context) {
    Widget frame = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (urls.isEmpty)
            placeholder
          else
            LayoutBuilder(
              builder: (context, constraints) =>
                  _networkImage(context, constraints),
            ),
          // طمس اللوحة: تراكب خفيف فوق منطقة اللوحة إذا توفرت إحداثياتها
          if (plateRegions != null && plateRegions!.isNotEmpty)
            _buildPlateBlurOverlay(),
        ],
      ),
    );

    if (aspectRatio != null) {
      frame = AspectRatio(aspectRatio: aspectRatio!, child: frame);
    }
    if (width != null || height != null) {
      frame = SizedBox(width: width, height: height, child: frame);
    }
    return frame;
  }

  /// نسخة احتياطية نصية تُستخدم إذا لم يتم العثور على لوحة
  /// أو كانت معالجة الصورة غير متاحة.
  Widget _buildWatermark() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.45),
            ],
          ),
        ),
        child: Center(
          child: Text(
            'MOTRI IQ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  /// تراكب لطمس لوحة السيارة: مستطيل معتم فوق إحداثيات اللوحة.
  /// يستخدم CustomPaint لرسم مستطيلات سوداء شبه شفافة عند إحداثيات نسبية.
  Widget _buildPlateBlurOverlay() {
    return CustomPaint(
      size: Size.infinite,
      painter: _PlateBlurPainter(plateRegions!),
    );
  }

  /// يحمّل الصورة، يكتشف لوحة السيارة، ويضيف شعار MOTRI IQ
  /// فوقها باستخدام معالجة خفيفة. النتيجة تُخزن مؤقتاً.
  Widget _watermarkedImage(
    BoxConstraints constraints,
    int? cacheWidth,
    int? cacheHeight,
  ) {
    return LayoutBuilder(
      builder: (context, innerConstraints) {
        return FutureBuilder<Uint8List>(
          future: _loadAndWatermarkImage(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Image.memory(
                snapshot.data!,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                errorBuilder: (_, __, ___) => placeholder,
              );
            }
            // أثناء المعالجة أو فشلها، نعرض الصورة الأصلية
            final String fallbackUrl = urls.first;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  fallbackUrl,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  loadingBuilder: (context, child, progress) =>
                      AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    child: progress == null
                        ? KeyedSubtree(
                            key: const ValueKey<String>('car-photo'),
                            child: child,
                          )
                        : KeyedSubtree(
                            key: const ValueKey<String>('car-photo-loading'),
                            child: placeholder,
                          ),
                  ),
                  errorBuilder: (_, __, ___) => placeholder,
                ),
                _buildWatermark(),
              ],
            );
          },
        );
      },
    );
  }

  Future<Uint8List> _loadAndWatermarkImage() async {
    final cacheKey = '${urls.first}_${plateRegions?.hashCode ?? 0}';
    final cached = processedImageCache.get(cacheKey);
    if (cached != null) return cached;

    try {
      final response = await _sharedHttpClient.get(Uri.parse(urls.first));
      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final result = await processCarImageWithWatermark(
          bytes,
          plateRegions: plateRegions,
        );
        processedImageCache.set(cacheKey, result);
        return result;
      }
    } catch (_) {}

    return Uint8List(0);
  }

  /// الصور الأصلية ~358KB وبأبعادها الكاملة، بينما بطاقة في القائمة
  /// بعرض 160px فقط. `cacheWidth`/`cacheHeight` يجعل Flutter يفكّ الترميز
  /// عند مقاس العرض الفعلي مضروباً في كثافة الشاشة، فتبقى النتيجة المعروضة
  /// مطابقة تماماً (نفس الدقة على نفس الجهاز) بينما تنخفض الذاكرة
  /// المستهلكة ويسرّع أول رسم للبطاقة.
  ///
  /// ⚠️ تنبيه مهم: `cacheWidth`/`cacheHeight` يتحكمان في **حجم فك الترميز**
  /// (decoding) فقط، لا في **حجم التحميل** (download). الصورة الكاملة تُحمّل
  /// من Supabase ثم تُصغّر محلياً. لتقليل استهلاك البيانات (bandwidth) فعلياً،
  /// يجب تفعيل تحويل الصور على الخادم (Supabase Image Transformation) أو إنشاء
  /// thumbnails مسبقة عند الرفع. المسار الحالي /render/image يرجع 404.
  ///
  /// لا يُمرَّر إلا بُعد واحد حتى تبقى نسبة أبعاد الصورة الأصلية، فلا
  /// يحدث أي اختلاف بصري.
  Widget _networkImage(BuildContext context, BoxConstraints constraints) {
    final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    int? cacheWidth;
    int? cacheHeight;
    if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
      cacheWidth = (constraints.maxWidth * dpr).round().clamp(1, 4096);
    }
    if (constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
      cacheHeight = (constraints.maxHeight * dpr).round().clamp(1, 4096);
    }

    // استخدام الرابط الأصلي مباشرة، لأن تحويل الصور على الخادم (/render/image/) يعيد 404
    final String imageUrl = urls.first;
    const filterQuality = FilterQuality.medium;

    if (showWatermark) {
      return _watermarkedImage(constraints, cacheWidth, cacheHeight);
    }

    return Image.network(
      imageUrl,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      loadingBuilder: (context, child, progress) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        child: progress == null
            ? KeyedSubtree(
                key: const ValueKey<String>('car-photo'),
                child: child,
              )
            : KeyedSubtree(
                key: const ValueKey<String>('car-photo-loading'),
                child: placeholder,
              ),
      ),
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  Widget get placeholder {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double side = constraints.biggest.shortestSide;
        return ColoredBox(
          color: placeholderColor ?? AppColors.placeholder,
          child: Center(
            child: _AnimatedIqIndicator(
              size: (side.isFinite ? side * iconScale : 40)
                  .clamp(16.0, 72.0)
                  .toDouble(),
              color: AppColors.borderStrong,
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedIqIndicator extends StatelessWidget {
  const _AnimatedIqIndicator({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontFamily: 'Arial',
      letterSpacing: 0.5,
    );

    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('IQ',
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            style: style),
      ),
    );
  }
}

class _PlateBlurPainter extends CustomPainter {
  final List<PlateRegion> regions;

  _PlateBlurPainter(this.regions);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    for (final region in regions) {
      final rect = Rect.fromLTWH(
        region.x * size.width,
        region.y * size.height,
        region.width * size.width,
        region.height * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlateBlurPainter oldDelegate) {
    return oldDelegate.regions != regions;
  }
}

final Map<String, Color> badgeColors = {
  'gold': const Color(0xFFFFD700),
  'silver': const Color(0xFFC0C0C0),
  'bronze': const Color(0xFFCD7F32),
};

String badgeLabel(String tier) {
  switch (tier) {
    case 'gold':
      return t('tier_gold');
    case 'silver':
      return t('tier_silver');
    case 'bronze':
      return t('tier_bronze');
    default:
      return '';
  }
}

Color badgeColor(String tier) => badgeColors[tier] ?? AppColors.textHint;

Widget sellerBadge(String tier, double size, {double fontSize = 10}) {
  if (tier == 'none' || tier.isEmpty) return const SizedBox.shrink();
  return Tooltip(
    message: 'بائع ${badgeLabel(tier)}',
    child: Icon(Icons.star_rounded, color: badgeColor(tier), size: size),
  );
}

Future<Map<String, dynamic>?> fetchSellerReputation(String sellerId) async {
  try {
    final response = await backendApi.get('sellers/reputation/$sellerId');
    final data = response is Map ? response['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  } catch (_) {
    return null;
  }
}

Future<bool> fetchSellerVerified(String? sellerId) async {
  final String id = sellerId?.trim() ?? '';
  if (id.isEmpty) return false;
  try {
    final response = await backendApi.get(
      'sellers/verifications',
      query: {'ids': id},
    );
    return response is Map &&
        response['data'] is List &&
        (response['data'] as List).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// شارة توثيق بجانب اسم البائع: أيقونة فقط، تظهر عند وجود سجل في
/// `seller_verifications` ولا تشغل مساحة قبل تحميل الإجابة.
class SellerVerifiedTick extends StatefulWidget {
  const SellerVerifiedTick(
      {super.key, required this.sellerId, this.size = 17, this.future});

  final String sellerId;
  final double size;
  final Future<bool>? future;

  @override
  State<SellerVerifiedTick> createState() => _SellerVerifiedTickState();
}

class _SellerVerifiedTickState extends State<SellerVerifiedTick> {
  late Future<bool> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = _resolve();
  }

  @override
  void didUpdateWidget(covariant SellerVerifiedTick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId ||
        oldWidget.future != widget.future) {
      _lookup = _resolve();
    }
  }

  Future<bool> _resolve() =>
      widget.future ?? trustCache.verifiedOf(widget.sellerId);

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return FutureBuilder<bool>(
      future: _lookup,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: 5),
          child: Tooltip(
            message: t('seller_verified'),
            child: Icon(Icons.verified_rounded,
                color: const Color(0xFF42A5F5), size: widget.size),
          ),
        );
      },
    );
  }
}

String _badgeFromRatingAndCount(double avg, int count) {
  if (avg >= 4.5 && count >= 10) return 'gold';
  if (avg >= 4.0 && count >= 5) return 'silver';
  if (avg >= 3.5 && count >= 1) return 'bronze';
  return 'none';
}

final ValueNotifier<List<Map<String, dynamic>>> compareCars = ValueNotifier([]);

void toggleCompareCar(Map<String, dynamic> car, BuildContext context) {
  final id = car['id']?.toString().trim();
  if (id == null || id.isEmpty) return;
  final current = List<Map<String, dynamic>>.from(compareCars.value);
  if (current.any((item) => item['id']?.toString().trim() == id)) {
    current.removeWhere((item) => item['id']?.toString().trim() == id);
  } else if (current.length >= 2) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t('compare_two_only'))));
    return;
  } else {
    current.add(Map<String, dynamic>.from(car));
  }
  compareCars.value = current;
}

const iraqiProvinces = [
  'بغداد',
  'البصرة',
  'أربيل',
  'السليمانية',
  'دهوك',
  'نينوى',
  'كركوك',
  'الأنبار',
  'ديالى',
  'صلاح الدين',
  'واسط',
  'بابل',
  'كربلاء',
  'النجف',
  'القادسية',
  'ذي قار',
  'ميسان',
  'المثنى',
];
const vehicleBodyTypes = [
  'سيدان',
  'SUV',
  'هاتشباك',
  'بيك أب',
  'كوبيه',
  'فان',
  'أخرى',
];

const double iqdPerUsd = 1310;

const String kSectionCars = 'cars';
const String kSectionMarket = 'market';
const String kSectionJobs = 'jobs';

String sectionTitleOf(String key) => switch (key) {
      kSectionCars => t('section_cars'),
      kSectionMarket => t('section_market'),
      kSectionJobs => t('section_jobs'),
      _ => key,
    };

/// Isolate complete numeric/currency runs from surrounding RTL prose.
String _currencyRun(String value) =>
    '\u2066${value.replaceAll(' USD', '\u00a0USD').replaceAll(' IQD', '\u00a0IQD')}\u2069';

String formatCurrency(double amount) {
  if (!amount.isFinite) return t('compare_price_unknown');
  final converted = amount * iqdPerUsd;
  if (!converted.isFinite) return t('compare_price_unknown');
  final iqd = converted.round();
  return _currencyRun(
      '${formatIqdOnly(amount)} USD • ${formatIqdOnly(iqd)} IQD');
}

String formatCurrencyLines(double amount) {
  final converted = amount * iqdPerUsd;
  if (!amount.isFinite || !converted.isFinite) {
    return t('compare_price_unknown');
  }
  return '${formatUsd(amount)}\n${formatIqd(converted.round())}';
}

String formatIqd(int amount) => _currencyRun('${formatIqdOnly(amount)} IQD');

String formatIqdOnly(num amount) {
  final formatted = amount.toStringAsFixed(0).replaceAllMapped(
        _thousandsSeparator,
        (match) => ',',
      );
  return formatted;
}

String formatUsd(double amount) => amount.isFinite
    ? _currencyRun('${formatIqdOnly(amount)} USD')
    : t('compare_price_unknown');

String formatUsdSymbol(double amount) => amount.isFinite
    ? _currencyRun('\$${formatIqdOnly(amount)}')
    : t('compare_price_unknown');

/// Car asking prices are entered in USD; never infer units from magnitude.
String buildCarShareText(Map<String, dynamic> car) {
  final name = [car['brand'], car['model']]
      .where((value) => value != null)
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .join(' ');
  final year = car['year']?.toString().trim() ?? '';
  final price = car['price']?.toString().trim() ?? '';
  final location = [car['province'], car['city']]
      .where((value) => value != null)
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .join('، ');
  return '${t('share_car_prefix')} ${name.isEmpty ? t('car_word') : name}${year.isEmpty ? '' : ' $year'}'
      '${price.isEmpty ? '' : '\n\n${t('share_price_label')}: ${formatPriceDisplay(price)}'}'
      '${location.isEmpty ? '' : '\n${t('share_location_label')}: $location'}\n\n${t('share_view_on_app')}';
}

/// Business-ad price is the advertising package fee, not a public offer price.
String buildBusinessAdShareText(BusinessAdData ad) =>
    '${t('share_market_prefix')} ${ad.businessName}'
    '${ad.locationText.isEmpty ? '' : '\n${t('share_location_label')}: ${ad.locationText}'}'
    '\n\n${t('share_view_on_app')}';

String formatPriceDisplay(String priceStr) {
  final price = parseFormDecimal(priceStr);
  if (price == null) return _priceFallback(priceStr);
  return formatCurrency(price);
}

String _priceFallback(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      const ['nan', 'infinity', '-infinity'].contains(trimmed.toLowerCase())) {
    return t('compare_price_unknown');
  }
  return trimmed;
}

String formatPriceDisplayCompact(String priceStr) {
  final price = parseFormDecimal(priceStr);
  if (price == null) return _priceFallback(priceStr);
  final converted = price * iqdPerUsd;
  if (!converted.isFinite) return t('compare_price_unknown');
  return _currencyRun(
      '${formatIqdOnly(price)} USD / ${formatIqdOnly(converted.round())} IQD');
}

/// LRU cache for parsed image URLs to prevent unbounded growth.
/// Max 500 entries (typical car listings with images).
class _ImageUrlCache {
  static const int _maxSize = 500;
  final Map<String, List<String>> _cache = {};
  final List<String> _accessOrder = [];

  List<String>? get(String key) {
    if (!_cache.containsKey(key)) return null;
    _accessOrder.remove(key);
    _accessOrder.add(key);
    return _cache[key];
  }

  void set(String key, List<String> value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= _maxSize) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }

  bool containsKey(String key) => _cache.containsKey(key);
}

final _ImageUrlCache _imageUrlCache = _ImageUrlCache();

/// Global set to track URLs already sent to precacheImage to avoid duplicate network requests.
/// Flutter's image cache handles deduplication, but this prevents redundant precacheImage calls.
final Set<String> _precachedImageUrls = {};

/// Smart precache that avoids duplicate requests.
/// Returns true if precache was initiated, false if already requested.
bool smartPrecacheImage(String url, BuildContext context) {
  if (_precachedImageUrls.contains(url)) return false;
  _precachedImageUrls.add(url);
  precacheImage(NetworkImage(url), context,
      onError: (Object error, StackTrace? stack) {});
  return true;
}

List<String> carImageUrls(Map<String, dynamic> car) {
  // Prefer additive safe display URLs from API (A1 delivery URLs or legacy absolute URLs).
  final display = car['image_urls'];
  if (display is List) {
    final resolved = display
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .map(_resolveCarImageUrl)
        .toList();
    if (resolved.isNotEmpty) return resolved;
  }
  if (display is String && display.trim().isNotEmpty) {
    final parsed = _parseImageUrls(display.trim())
        .where((e) =>
            e.startsWith('http://') ||
            e.startsWith('https://') ||
            e.startsWith('/api/'))
        .map(_resolveCarImageUrl)
        .toList();
    if (parsed.isNotEmpty) return parsed;
  }
  // Fallback: legacy image_url field. Preserve legacy absolute URLs only; never treat raw object keys as display URLs.
  final raw = car['image_url'];
  if (raw == null) return [];
  final value = raw.toString().trim();
  if (value.isEmpty) return [];
  final cached = _imageUrlCache.get(value);
  if (cached != null) return cached;
  final result = _parseImageUrls(value)
      .where((e) =>
          e.startsWith('http://') ||
          e.startsWith('https://') ||
          e.startsWith('/api/'))
      .map(_resolveCarImageUrl)
      .toList();
  _imageUrlCache.set(value, result);
  return result;
}

String _resolveCarImageUrl(String url) => url.startsWith('/api/')
    ? Uri.parse(backendUrl).resolve(url).toString()
    : url;

List<String> _parseImageUrls(String value) {
  if (value.startsWith('[')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }
  return [value];
}

/// يقرأ إحداثيات مناطق اللوحات المخزّنة في قاعدة البيانات.
/// يُرجع قائمة موازية لـ [carImageUrls] — كل عنصر قائمة
/// بمناطق اللوحة (أو null إذا لم يتم التخزين).
List<List<PlateRegion>?>? carImagePlateRegions(Map<String, dynamic> car) {
  final raw = car['plate_regions'];
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.map<List<PlateRegion>?>((e) {
        if (e == null) return null;
        if (e is List) {
          return e.map((item) {
            if (item is Map<String, dynamic>) {
              return PlateRegion.fromJson(Map<String, dynamic>.from(item));
            }
            return PlateRegion(0.4, 0.7, 0.3, 0.08);
          }).toList();
        }
        return null;
      }).toList();
    }
  } catch (_) {}
  return null;
}

class MotriIqApp extends StatelessWidget {
  const MotriIqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: darkModeNotifier,
      builder: (BuildContext context, ThemeMode mode, Widget? _) {
        return ValueListenableBuilder<AppLocale>(
          valueListenable: appLocaleNotifier,
          builder: (BuildContext context, AppLocale locale, Widget? _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'MOTRI IQ',
              themeMode: mode,
              theme: buildAppTheme(Brightness.light),
              darkTheme: buildAppTheme(Brightness.dark),
              locale: locale.locale,
              supportedLocales: const <Locale>[
                Locale('ar'),
                Locale('ku'),
                Locale('en'),
              ],
              localizationsDelegates: appLocalizationsDelegates,
              builder: (BuildContext context, Widget? child) => AppStringsScope(
                locale: appLocale,
                child: kIsWeb
                    ? WebAppFrame(child: child ?? const SizedBox.shrink())
                    : child ?? const SizedBox.shrink(),
              ),
              home: const HomePage(),
            );
          },
        );
      },
    );
  }
}

class BrandLogo extends StatefulWidget {
  final double size;
  final bool showName;
  const BrandLogo({super.key, this.size = 58, this.showName = false});

  @override
  State<BrandLogo> createState() => _BrandLogoState();
}

class _BrandLogoState extends State<BrandLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final logo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .29),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.emptyGradientA, AppColors.emptyGradientB],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x44000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
        border: Border.all(color: const Color(0x998B0D25), width: 1.2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text.rich(
            textScaler: TextScaler.noScaling,
            textDirection: TextDirection.ltr,
            semanticsLabel: 'MOTRI IQ',
            maxLines: 1,
            TextSpan(
              children: [
                TextSpan(
                  text: 'M',
                  style: TextStyle(
                      color: AppColors.textStrong, fontSize: size * .49),
                ),
                TextSpan(
                  text: 'IQ',
                  style: TextStyle(color: red, fontSize: size * .49),
                ),
              ],
            ),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: size * -.045,
              height: 1,
              shadows: const [
                Shadow(color: Color(0x998B0D25), blurRadius: 12),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              return Positioned(
                bottom: size * .16,
                left: size * (.13 + .40 * _motion.value),
                child: Container(
                  width: size * .27,
                  height: size * .045,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, AppColors.textStrong, red],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: red, blurRadius: 5),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: size * .16,
            left: size * .15,
            child: Container(
              width: size * .7,
              height: 1,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );

    if (!widget.showName) return logo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MOTRI IQ',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4)),
            Text('IRAQ CAR MARKET',
                style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    letterSpacing: 1.1)),
          ],
        ),
      ],
    );
  }
}

class CarMarqueeStrip extends StatefulWidget {
  const CarMarqueeStrip({super.key, required this.cars});

  final List<Map<String, dynamic>> cars;

  @override
  State<CarMarqueeStrip> createState() => _CarMarqueeStripState();
}

class _CarMarqueeStripState extends State<CarMarqueeStrip> {
  static const Duration _delay = Duration(seconds: 4);
  static const double _preferredHeight = 248;

  late final PageController _pageController;
  Timer? _timer;
  int _page = 0;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.90);
    _timer = Timer.periodic(_delay, (_) => _next());
  }

  @override
  void didUpdateWidget(covariant CarMarqueeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.cars.length;
    if (count == 0) return;
    if (_page > count - 1) {
      _page = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (!mounted ||
        _userDragging ||
        !TickerMode.valuesOf(context).enabled ||
        (MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context))) {
      return;
    }
    final count = widget.cars.length;
    if (count < 2 || !_pageController.hasClients) return;
    final target = (_page + 1) % count;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
  }

  void _moveBy(int delta) {
    if (!_pageController.hasClients || widget.cars.length < 2) return;
    final target = (_page + delta) % widget.cars.length;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
  }

  void _onPageChanged(int index) {
    final count = widget.cars.length;
    if (!mounted || count == 0) return;
    setState(() => _page = index % count);
  }

  @override
  Widget build(BuildContext context) {
    final cars = widget.cars;
    if (cars.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxH = constraints.maxHeight;
        final double height = constraints.hasBoundedHeight
            ? (maxH < _preferredHeight ? maxH : _preferredHeight)
            : _preferredHeight;
        final bool showDots = cars.length > 1 && height >= 44;

        return SizedBox(
          height: height,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Directionality(
                  textDirection: appLocale.direction,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification &&
                          notification.dragDetails != null) {
                        _userDragging = true;
                      } else if (notification is ScrollEndNotification) {
                        _userDragging = false;
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: cars.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: _BannerCarCard(car: cars[index]),
                      ),
                    ),
                  ),
                ),
              ),
              if (showDots) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (height >= 120)
                    IconButton(
                      tooltip: t('ui_carousel_previous'),
                      onPressed: () => _moveBy(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  Flexible(
                      child: CarouselPosition(
                          count: cars.length,
                          active: _page,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          inactiveColor: AppColors.borderStrong)),
                  if (height >= 120)
                    IconButton(
                      tooltip: t('ui_carousel_next'),
                      onPressed: () => _moveBy(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BannerCarCard extends StatelessWidget {
  const _BannerCarCard({required this.car});

  final Map<String, dynamic> car;

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final images = carImageUrls(car);
    final plateRegions = carImagePlateRegions(car);
    final firstPlateRegions = (plateRegions != null && plateRegions.isNotEmpty)
        ? plateRegions.first
        : null;
    final name =
        '${(car['brand'] ?? '').toString()} ${(car['model'] ?? '').toString()}'
            .trim();
    final rawPrice = (car['price'] ?? '').toString();
    final amount = parseFormDecimal(rawPrice);
    final price = amount == null ? rawPrice : formatUsdSymbol(amount);

    return InkWell(
      borderRadius: BorderRadius.circular(imgRadius),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CarDetailsPage(car: car)),
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(imgRadius),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.shadow,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CarPhoto(urls: images, plateRegions: firstPlateRegions),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x8A000000)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      price,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                name.isEmpty ? t('car_word') : name,
                textDirection: contentTextDirection(context, name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestCarsGridSkeleton extends StatelessWidget {
  const _LatestCarsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      key: const ValueKey('home_cars_loading'),
      container: true,
      liveRegion: true,
      label: t('ui_loading_title'),
      child: ExcludeSemantics(
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 320 ? 1 : 2;
                final tileWidth =
                    (constraints.maxWidth - (columns - 1) * 8) / columns;
                final cardHeight = (tileWidth / 1.65 + 104 * scale)
                    .clamp(224.0 * scale, 360.0 * scale);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: cardHeight,
                  ),
                  itemCount: 4,
                  itemBuilder: (context, index) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 1.65,
                          child: _AdSlotPlaceholder(),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  height: 12,
                                  width: 90,
                                  color: AppColors.border,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 12,
                                  width: 120,
                                  color: AppColors.border,
                                ),
                                const Spacer(),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Container(
                                    height: 14,
                                    width: 76,
                                    color: AppColors.border,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdSlotPlaceholder extends StatelessWidget {
  const _AdSlotPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(imgRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: const CarPhoto(urls: <String>[]),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _homeTabIndex = 0;
  static const int _searchTabIndex = 3;

  final ScrollController _homeScrollController = ScrollController();

  int selectedTab = _homeTabIndex;
  late final List<Widget> pages;

  _HomePageState() {
    pages = <Widget>[
      HomeTab(
        scrollController: _homeScrollController,
        onOpenSearch: () => _selectTab(_searchTabIndex),
      ),
      const SectionPage(
        key: ValueKey('cars_tab'),
        title: kSectionCars,
        icon: AppIcons.cars,
        showAddAction: false,
      ),
      const SectionPage(
        key: ValueKey('market_tab'),
        title: kSectionMarket,
        icon: AppIcons.market,
      ),
      SearchTab(key: SearchTab.searchKey),
      const AddCarTab(),
      const AccountTab(),
    ];
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  void _selectTab(int value) {
    if (value == selectedTab) return;
    setState(() => selectedTab = value);
  }

  void _replaySavedSearch(String query) {
    _selectTab(_searchTabIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && selectedTab == _searchTabIndex) {
        SearchTab.setQueryAndSearch(query);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        body: SafeArea(child: pages[selectedTab]),
        bottomNavigationBar: AppBottomNavigation(
          selectedIndex: selectedTab,
          onSelected: _selectTab,
        ),
      ),
    );
  }
}

class _HomeSearchBox extends StatelessWidget {
  const _HomeSearchBox({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('home_search_panel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark
            ? const Color(0xFF292028)
            : const Color(0xFF351B28),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('ui_search_start'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                child: Row(children: [
                  Icon(AppIcons.search,
                      size: 22, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(t('home_search_hint'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant))),
                  const SizedBox(width: 8),
                  Icon(AppIcons.disclosure,
                      size: 20, color: scheme.onPrimaryContainer),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بيانات علامة تجارية واحدة في قائمة "أشهر ماركات السيارات في العراق".
///
/// [displayName] اسم العلامة المعروض للمستخدم (عربي).
/// [dbValue] القيمة الفعلية في عمود `brand` في Supabase — يجب أن تكون
/// مطابقة تمامًا لضمان الفلترة الصحيحة.
/// [englishName] اسم العلامة بالإنجليزية للعرض في البطاقة.
/// [color] لون العلامة التجارية المميز.
/// [logoAsset] مسار ملف الشعار في assets/logos/.
class CarBrand {
  const CarBrand({
    required this.displayName,
    required this.dbValue,
    required this.englishName,
    required this.color,
    required this.logoAsset,
  });

  final String displayName;
  final String dbValue;
  final String englishName;
  final Color color;
  final String logoAsset;
}

/// العلامات التجارية العشرة الشائعة على الصفحة الرئيسية.
///
/// القائمة ثابتة — لا استعلام للقاعدة عند فتح الصفحة الرئيسية.
/// ألوان العلامات تعكس الهوية البصرية الخاصة بكل ماركة.
const List<CarBrand> kCarBrands = <CarBrand>[
  CarBrand(
      displayName: 'تويوتا',
      dbValue: 'Toyota',
      englishName: 'Toyota',
      color: Color(0xFFE60012),
      logoAsset: 'assets/logos/toyota.svg'),
  CarBrand(
      displayName: 'كيا',
      dbValue: 'Kia',
      englishName: 'Kia',
      color: Color(0xFF1A1A1A),
      logoAsset: 'assets/logos/kia.svg'),
  CarBrand(
      displayName: 'هيونداي',
      dbValue: 'Hyundai',
      englishName: 'Hyundai',
      color: Color(0xFF0066B0),
      logoAsset: 'assets/logos/hyundai.svg'),
  CarBrand(
      displayName: 'شيري',
      dbValue: 'Chery',
      englishName: 'Chery',
      color: Color(0xFFFA5427),
      logoAsset: 'assets/logos/chery.svg'),
  CarBrand(
      displayName: 'MG',
      dbValue: 'MG',
      englishName: 'MG',
      color: Color(0xFF005500),
      logoAsset: 'assets/logos/mg.svg'),
  CarBrand(
      displayName: 'نيسان',
      dbValue: 'Nissan',
      englishName: 'Nissan',
      color: Color(0xFF003366),
      logoAsset: 'assets/logos/nissan.svg'),
  CarBrand(
      displayName: 'GMC',
      dbValue: 'GMC',
      englishName: 'GMC',
      color: Color(0xFF000000),
      logoAsset: 'assets/logos/gmc.svg'),
  CarBrand(
      displayName: 'فورد',
      dbValue: 'Ford',
      englishName: 'Ford',
      color: Color(0xFF000000),
      logoAsset: 'assets/logos/ford.svg'),
  CarBrand(
      displayName: 'شفروليه',
      dbValue: 'Chevrolet',
      englishName: 'Chevrolet',
      color: Color(0xFF003366),
      logoAsset: 'assets/logos/chevrolet.svg'),
  CarBrand(
      displayName: 'هافال',
      dbValue: 'Haval',
      englishName: 'Haval',
      color: Color(0xFF000000),
      logoAsset: 'assets/logos/haval.svg'),
];

/// بطاقة ماركة واحدة في الشبكة. تتميز بـ:
/// * ظهور ناعم عند بناء الويدجت (TweenAnimationBuilder).
/// * ضغط خفيف (AnimatedScale) فقط — لا Animation مستمر.
///
/// شعار العلامة الرسمي (SVG من assets) في المنتصف، بدون نصوص.
class _BrandGridItem extends StatefulWidget {
  const _BrandGridItem({required this.brand, required this.onTap});

  final CarBrand brand;
  final VoidCallback onTap;

  @override
  State<_BrandGridItem> createState() => _BrandGridItemState();
}

class _BrandGridItemState extends State<_BrandGridItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (_, double value, child) =>
          Transform.scale(scale: value, child: child),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Card(
            elevation: 0,
            color: card,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border, width: 0.6),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SvgPicture.asset(
                  widget.brand.logoAsset,
                  width: 56,
                  height: 56,
                  fit: BoxFit.contain,
                  placeholderBuilder: (context) => Icon(
                    AppIcons.cars,
                    size: 32,
                    color: widget.brand.color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab(
      {super.key,
      this.scrollController,
      this.marketSectionKey,
      this.marketSelected,
      this.onOpenSearch});

  final ScrollController? scrollController;
  final Key? marketSectionKey;
  final ValueListenable<bool>? marketSelected;
  final VoidCallback? onOpenSearch;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

/// بيانات الصفحة الرئيسية المحسوبة مرة واحدة لتجنب إعادة الفلترة.
/// تحتوي على القوائم المفلترة الجاهزة للاستخدام المباشر في الويدجتس.
class _HomeCarsData {
  const _HomeCarsData({
    required this.allCars,
    required this.withImages,
    required this.topAds,
    required this.latestCars,
  });

  final List<Map<String, dynamic>> allCars;
  final List<Map<String, dynamic>> withImages;
  final List<Map<String, dynamic>> topAds;
  final List<Map<String, dynamic>> latestCars;
}

/// يحسب بيانات الصفحة الرئيسية دفعة واحدة من بيانات السيارات الخام.
/// يتجنب تكرار الفلترة واستخراج الصور في عدة مستقبلات.
Future<_HomeCarsData> _computeHomeCarsData(
    Future<List<Map<String, dynamic>>> carsFuture) async {
  final allCars = await carsFuture;
  final withImages = allCars.where((c) => carImageUrls(c).isNotEmpty).toList();
  final topAds = withImages.take(5).toList();
  final latestCars = allCars.take(4).toList();
  return _HomeCarsData(
    allCars: allCars,
    withImages: withImages,
    topAds: topAds,
    latestCars: latestCars,
  );
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  static const int _homeCarsPageSize = 20;

  late Future<List<Map<String, dynamic>>> cars;
  late Future<List<Map<String, dynamic>>> hotCars;
  late Future<List<Map<String, dynamic>>> newCars;
  late Future<List<Map<String, dynamic>>> marketFeed;

  /// إعلانات الأعمال في الرئيسية. كانت تُنشأ داخل `build`، فكل إعادة
  /// بناء (تبديل لغة، ثيم، أي تنبيه) يرسل طلباً جديداً لنفس البيانات.
  /// الآن تُنشأ مرة واحدة وتُعاد فقط عند السحب للتحديث أو تبديل الجلسة.
  late Future<List<BusinessAdData>> homeBusinessAds;

  /// Future موحد للبيانات المفلترة لتجنب تكرار الفلترة في عدة FutureBuilder
  late Future<_HomeCarsData> homeCarsData;

  final List<Map<String, dynamic>> _homeMoreCars = <Map<String, dynamic>>[];
  int _homeCarsGeneration = 0;
  int _homeCarsOffset = 0;
  bool _homeCarsReady = false;
  bool _homeCarsHasMore = false;
  bool _homeCarsLoadingMore = false;
  bool _homeCarsMoreFailed = false;
  ScrollController? _homeScrollController;

  StreamSubscription<AuthState>? _authSubscription;
  VoidCallback? _homeAuthListener;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Load all car lists in parallel for faster home page initialization
    final carsFuture = loadCars();
    final hotCarsFuture = loadHotCars();
    final newCarsFuture = loadNewCars();

    cars = carsFuture;
    _homeScrollController = widget.scrollController;
    _homeScrollController?.addListener(_onHomeCarsScroll);
    _startHomeCarsPagination(carsFuture);
    hotCars = hotCarsFuture;
    newCars = newCarsFuture;
    marketFeed = loadMarketFeed();
    homeBusinessAds = loadActiveBusinessAds(limit: 3);
    homeCarsData = _computeHomeCarsData(carsFuture);
    homeCarsData.ignore();
    marketFeed.ignore();
    _homeAuthListener = () {
      trustCache.reset();
      unawaited(_refreshHome());
    };
    backendAuthSession.addListener(_homeAuthListener!);
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _homeScrollController?.removeListener(_onHomeCarsScroll);
      _homeScrollController = widget.scrollController;
      _homeScrollController?.addListener(_onHomeCarsScroll);
    }
  }

  int _resetHomeCarsPagination() {
    _homeCarsGeneration++;
    _homeMoreCars.clear();
    _homeCarsOffset = 0;
    _homeCarsReady = false;
    _homeCarsHasMore = false;
    _homeCarsLoadingMore = false;
    _homeCarsMoreFailed = false;
    return _homeCarsGeneration;
  }

  void _startHomeCarsPagination(Future<List<Map<String, dynamic>>> firstPage) {
    final generation = _resetHomeCarsPagination();
    unawaited(_primeHomeCars(firstPage, generation));
  }

  Future<void> _primeHomeCars(
    Future<List<Map<String, dynamic>>> firstPage,
    int generation,
  ) async {
    try {
      final rows = await firstPage;
      if (!mounted || generation != _homeCarsGeneration) return;
      setState(() {
        _homeCarsOffset = rows.length;
        _homeCarsHasMore = rows.length == _homeCarsPageSize;
        _homeMoreCars
          ..clear()
          ..addAll(rows.skip(4));
        _homeCarsReady = true;
      });
    } catch (error) {
      debugPrint('Home car feed first page failed: $error');
      if (!mounted || generation != _homeCarsGeneration) return;
      setState(() {
        _homeCarsReady = true;
      });
    }
  }

  void _onHomeCarsScroll() {
    final controller = _homeScrollController;
    if (controller == null ||
        !controller.hasClients ||
        !_homeCarsReady ||
        !_homeCarsHasMore ||
        _homeCarsLoadingMore ||
        _homeCarsMoreFailed) {
      return;
    }
    if (controller.position.extentAfter < 650) {
      unawaited(_loadMoreHomeCars());
    }
  }

  Future<void> _loadMoreHomeCars() async {
    if (!mounted ||
        !_homeCarsReady ||
        !_homeCarsHasMore ||
        _homeCarsLoadingMore) {
      return;
    }
    final generation = _homeCarsGeneration;
    final offset = _homeCarsOffset;
    setState(() {
      _homeCarsLoadingMore = true;
      _homeCarsMoreFailed = false;
    });
    try {
      final response = await backendApi.get(
        'cars',
        query: {
          'limit': '$_homeCarsPageSize',
          'offset': '$offset',
        },
        anonymous: true,
      );
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! List) {
        throw StateError('Home cars page response is invalid');
      }
      final rows = List<Map<String, dynamic>>.from(
        (response['data'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      await _withTrust(rows);
      if (!mounted || generation != _homeCarsGeneration) return;
      final knownIds = _homeMoreCars
          .map((car) => car['id']?.toString())
          .whereType<String>()
          .toSet();
      setState(() {
        _homeMoreCars.addAll(rows.where((car) {
          final id = car['id']?.toString();
          return id == null || knownIds.add(id);
        }));
        _homeCarsOffset = offset + rows.length;
        _homeCarsHasMore = rows.length == _homeCarsPageSize;
        _homeCarsLoadingMore = false;
      });
    } catch (error) {
      debugPrint('Home car feed next page failed: $error');
      if (!mounted || generation != _homeCarsGeneration) return;
      setState(() {
        _homeCarsLoadingMore = false;
        _homeCarsMoreFailed = true;
      });
    }
  }

  Widget _buildHomeMoreCars() {
    if (!_homeCarsReady ||
        (_homeMoreCars.isEmpty &&
            !_homeCarsLoadingMore &&
            !_homeCarsMoreFailed)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.cars, color: red, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t('home_more_cars'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildHomeCarGrid(context, _homeMoreCars),
          if (_homeCarsLoadingMore)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_homeCarsMoreFailed)
            AppStatePanel(
              key: const ValueKey('home_more_cars_error'),
              title: t('ui_load_error_title'),
              message: t('ui_load_error_body'),
              icon: AppIcons.cloudOff,
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: _loadMoreHomeCars,
            ),
        ],
      ),
    );
  }

  Future<void> _refreshHome() async {
    if (!mounted) return;
    final nextCars = loadCars();
    final generation = _resetHomeCarsPagination();
    setState(() {
      cars = nextCars;
      homeCarsData = _computeHomeCarsData(cars);
      hotCars = loadHotCars();
      newCars = loadNewCars();
      marketFeed = loadMarketFeed();
      homeBusinessAds = loadActiveBusinessAds(limit: 3);
      homeCarsData.ignore();
      marketFeed.ignore();
    });
    unawaited(_primeHomeCars(nextCars, generation));
    try {
      // Keep the refresh indicator visible until every feed has completed.
      await Future.wait<Object?>([
        homeCarsData,
        hotCars,
        newCars,
        marketFeed,
        homeBusinessAds,
      ]).timeout(const Duration(seconds: 20));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('misc_ads_load_failed'))),
      );
    }
  }

  @override
  void dispose() {
    final l = _homeAuthListener;
    if (l != null) backendAuthSession.removeListener(l);
    _homeAuthListener = null;
    _homeScrollController?.removeListener(_onHomeCarsScroll);
    _homeScrollController = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }

  /// يجلب سمعة وتوثيق كل بائعي الدفعة والمفضلة في استعلامات مجمّعة
  /// (3 طلبات للصفحة كلها) قبل بناء أي بطاقة، فتبتلع البطاقات الطلبات
  /// من الذاكرة بدل استعلام خاص لكل بطاقة. الدوال الخمس تُستدعى معاً،
  /// و TrustCache يزيل تكرار نفس البائع بينها.
  Future<List<Map<String, dynamic>>> _withTrust(
      List<Map<String, dynamic>> rows) async {
    await trustCache.preloadForRows(rows);
    return rows;
  }

  Future<List<Map<String, dynamic>>> loadMarketFeed() async {
    final response =
        await backendApi.get('market/items?limit=5', anonymous: true);
    if (response is! Map ||
        response['success'] != true ||
        response['data'] is! List) {
      throw StateError('Market feed response is invalid');
    }
    final rows = List<Map<String, dynamic>>.from(
      (response['data'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    return await _withTrust(rows);
  }

  Future<List<Map<String, dynamic>>> loadCars() async {
    try {
      final decoded = await backendApi.get(
        'cars',
        query: {'limit': '$_homeCarsPageSize', 'offset': '0'},
        anonymous: true,
      );

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['data'] is! List) {
        throw Exception('Invalid cars API response');
      }

      final rows = List<Map<String, dynamic>>.from(
        (decoded['data'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      return await _withTrust(rows);
    } catch (e) {
      debugPrint('loadCars API error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadHotCars() async {
    final oneWeekAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .toUtc()
        .toIso8601String();
    final response = await backendApi.get(
      'cars/featured',
      query: {'since': oneWeekAgo, 'limit': '10'},
      anonymous: true,
    );
    if (response is! Map ||
        response['success'] != true ||
        response['data'] is! List) {
      throw StateError('Featured cars response is invalid');
    }
    return await _withTrust(
      List<Map<String, dynamic>>.from(response['data'] as List),
    );
  }

  Future<List<Map<String, dynamic>>> loadNewCars() async {
    final oneDayAgo = DateTime.now()
        .subtract(const Duration(hours: 24))
        .toUtc()
        .toIso8601String();
    final response = await backendApi.get(
      'cars/featured',
      query: {'since': oneDayAgo, 'limit': '10'},
      anonymous: true,
    );
    if (response is! Map ||
        response['success'] != true ||
        response['data'] is! List) {
      throw StateError('Featured cars response is invalid');
    }
    return await _withTrust(
      List<Map<String, dynamic>>.from(response['data'] as List),
    );
  }

  void openSection(String title, IconData icon, {String? brand}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SectionPage(title: title, icon: icon, brand: brand)));
  }

  Widget _buildCarsHighlights() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMarketSubsection(
            t('home_most_requested'), Icons.local_fire_department, hotCars),
        _buildMarketSubsection(t('ad_new'), Icons.new_releases, newCars),
      ],
    );
  }

  Widget _buildFeedSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required IconData cardIcon,
    required Future<List<Map<String, dynamic>>> future,
    required String emptyText,
    required VoidCallback onSeeAll,
    bool showEmpty = false,
  }) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: AppStatePanel(
              title: title,
              message: t('ui_load_error_body'),
              icon: AppIcons.cloudOff,
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: _refreshHome,
            ),
          );
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          if (!showEmpty) return const SizedBox.shrink();
          if (snapshot.hasError) {
            return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: AppStatePanel(
                    key: const ValueKey('home_market_error'),
                    title: title,
                    message: t('ui_load_error_body'),
                    icon: AppIcons.cloudOff,
                    isError: true,
                    actionLabel: t('ui_retry'),
                    onAction: _refreshHome));
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: red),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: snapshot.connectionState == ConnectionState.waiting
                  ? const LinearProgressIndicator()
                  : Text(snapshot.hasError
                      ? t('misc_ads_load_failed')
                      : emptyText),
              trailing: Icon(AppIcons.disclosure),
              onTap: onSeeAll,
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: red, size: 20),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                Flexible(
                    child: TextButton(
                        onPressed: onSeeAll,
                        child: Text(t('compare_see_all'),
                            textAlign: TextAlign.center))),
              ],
            ),
            Text(subtitle,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
                height: (MediaQuery.textScalerOf(context).scale(14) * 12)
                            .clamp(180, 280) *
                        .75 +
                    MediaQuery.textScalerOf(context).scale(14) * 7.5 +
                    24,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final item = list[i];
                    return SizedBox(
                        width: (MediaQuery.textScalerOf(context).scale(14) * 12)
                            .clamp(180, 280)
                            .toDouble(),
                        child: GenericAdCard(
                            key: ValueKey(item['id']),
                            item: item,
                            icon: cardIcon,
                            square: true));
                  },
                )),
            const SizedBox(height: 26),
          ],
        );
      },
    );
  }

  Widget _buildMarketSubsection(
      String title, IconData icon, Future<List<Map<String, dynamic>>> future,
      {bool showErrors = false, Key? errorKey}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (showErrors && snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: AppStatePanel(
              key: errorKey,
              title: title,
              message: t('ui_load_error_body'),
              icon: AppIcons.cloudOff,
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: _refreshHome,
            ),
          );
        }
        final list = snapshot.data ?? [];
        // Optional recommendations have no useful action until items exist.
        // Collapse the complete section, including its heading and spacing.
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 8),
              _buildHomeCarGrid(context, list),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    context.dependOnAppStrings();
    return RefreshIndicator(
      onRefresh: _refreshHome,
      child: ListView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Row(
            children: [
              const BrandLogo(size: 40),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('MOTRI IQ',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8)),
              ),
              ValueListenableBuilder<List<Map<String, dynamic>>>(
                valueListenable: compareCars,
                builder: (context, selected, _) => IconButton.filledTonal(
                  tooltip: t('compare_title'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CompareCarsPage())),
                  icon: Badge(
                    isLabelVisible: selected.isNotEmpty,
                    label: Text('${selected.length}'),
                    child: const Icon(AppIcons.compare),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HomeSearchBox(onTap: widget.onOpenSearch),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final action in <(IconData, String, VoidCallback)>[
              (
                AppIcons.cars,
                'nav_cars',
                () => openSection(kSectionCars, AppIcons.cars)
              ),
              (
                AppIcons.market,
                'nav_market',
                () => openSection(kSectionMarket, AppIcons.market)
              ),
              if (!restrictPaidFeatures)
                (
                  AppIcons.campaign,
                  'ui_home_services',
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BusinessAdsPage()))
                ),
            ])
              ActionChip(
                  avatar: Icon(action.$1,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                  label: Text(t(action.$2)),
                  onPressed: action.$3),
          ]),
          const SizedBox(height: 20),
          FutureBuilder<_HomeCarsData>(
            future: homeCarsData,
            builder: (context, snapshot) {
              final featured =
                  snapshot.data?.topAds ?? const <Map<String, dynamic>>[];
              if (featured.isEmpty) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('ui_home_featured'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    CarMarqueeStrip(
                        key: const ValueKey('home_featured_carousel'),
                        cars: featured),
                    const SizedBox(height: 24),
                  ]);
            },
          ),
          Row(
            children: [
              Expanded(
                  child: Text(t('home_latest_cars'),
                      style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w900))),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: TextButton(
                    onPressed: () => openSection(kSectionCars, AppIcons.cars),
                    child:
                        Text(t('compare_see_all'), textAlign: TextAlign.center),
                  )),
            ],
          ),
          const SizedBox(height: 5),
          FutureBuilder<_HomeCarsData>(
            future: homeCarsData,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                // تُحجز مساحة الشبكة النهائية (صفّان بنفس
                // المندوب ونسبة الأبعاد) أثناء التحميل،
                // فلا يتغير ارتفاع الصفحة بعد ظهور الإعلانات.
                return const _LatestCarsGridSkeleton();
              }
              final data = snapshot.data;
              if (snapshot.hasError || data == null) {
                return AppStatePanel(
                    key: const ValueKey('home_cars_error'),
                    title: t('ui_load_error_title'),
                    message: t('ui_load_error_body'),
                    icon: AppIcons.cloudOff,
                    isError: true,
                    actionLabel: t('ui_retry'),
                    onAction: _refreshHome);
              }
              final list = data.latestCars;
              if (list.isEmpty) {
                return _EmptyCard(text: t('car_no_ads'));
              }
              return Column(children: [
                _buildHomeCarGrid(context, list),
              ]);
            },
          ),
          const SizedBox(height: 26),
          _buildCarsHighlights(),
          _buildHomeMoreCars(),
          Container(
            key: widget.marketSectionKey,
            child: ValueListenableBuilder<bool>(
              valueListenable:
                  widget.marketSelected ?? const AlwaysStoppedAnimation(false),
              builder: (context, selected, _) => _buildFeedSection(
                showEmpty: selected,
                title: t('home_latest_market'),
                subtitle: t('home_latest_market_sub'),
                icon: AppIcons.market,
                cardIcon: AppIcons.market,
                future: marketFeed,
                emptyText: t('market_no_ads'),
                onSeeAll: () => openSection(kSectionMarket, AppIcons.market),
              ),
            ),
          ),
          const HomeBannerAd(),
          const SizedBox(height: 10),
          FutureBuilder<List<BusinessAdData>>(
            future: homeBusinessAds,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              if (snapshot.hasError) {
                return Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    key: const ValueKey('home_business_ads_retry'),
                    onPressed: () => setState(() {
                      homeBusinessAds = loadActiveBusinessAds(limit: 3);
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(t('ui_retry')),
                  ),
                );
              }
              final ads = snapshot.data ?? [];
              if (ads.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(AppIcons.campaign, color: red, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(t('account_business_ads_all'),
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...ads.map((ad) => BusinessAdBanner(ad: ad)),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BusinessAdsPage())),
                      icon:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      iconAlignment: IconAlignment.end,
                      label: Text(t('home_all_business_ads')),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RequestDraftChangedException implements Exception {}

class CarRequestsPage extends StatefulWidget {
  const CarRequestsPage({super.key});

  @override
  State<CarRequestsPage> createState() => _CarRequestsPageState();
}

class _CarRequestsPageState extends State<CarRequestsPage> {
  bool viewingMine = false, _creating = false;
  late Future<_ActivityRowsResult> requests;
  VoidCallback? _authListener;
  final Set<String> _busy = {}, _offering = {}, _updatingDecisions = {};
  @override
  void initState() {
    super.initState();
    requests = loadRequests();
    _authListener = () {
      if (mounted) reload();
    };
    backendAuthSession.addListener(_authListener!);
  }

  @override
  void dispose() {
    final l = _authListener;
    if (l != null) backendAuthSession.removeListener(l);
    super.dispose();
  }

  Future<_ActivityRowsResult> loadRequests() async {
    final user = backendAuthSession.user;
    final mine = viewingMine;
    if (mine && user == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get(
        mine ? 'requests/mine' : 'requests',
      );
      if (backendAuthSession.user?.id != user?.id) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  Future<void> reload() async {
    final next = loadRequests();
    setState(() {
      requests = next;
    });
    await next;
  }

  void _message(String key) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(key))));
    }
  }

  String _title(Map<String, dynamic> request) {
    final title = [request['brand'], request['model']]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    return title.isEmpty ? t('account_requests_cars') : title;
  }

  Widget _requestPrice(String raw) {
    final theme = Theme.of(context);
    final amount = parseFormDecimal(raw);
    final lines =
        (amount == null ? formatPriceDisplay(raw) : formatCurrencyLines(amount))
            .split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lines.first,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (lines.length > 1)
          Text(
            lines.last,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Future<void> createRequest() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _message('req_login_publish');
      return;
    }
    if (_creating) return;
    setState(() {
      _creating = true;
    });
    final requestId = newSubmissionId();
    Map<String, dynamic>? attemptedPayload;

    bool samePayload(Map<String, dynamic> first, Map<String, dynamic> second) {
      if (first.length != second.length) return false;
      return first.entries.every(
        (entry) =>
            second.containsKey(entry.key) && second[entry.key] == entry.value,
      );
    }

    try {
      final created = await showDialog<bool>(
        context: context,
        builder: (_) => CarRequestEditorDialog(
          errorKey: (error) => supabase.auth.currentUser?.id != user.id
              ? 'ui_business_session_changed'
              : error is _RequestDraftChangedException
                  ? 'ui_request_already_saved'
              : 'req_publish_failed',
          onSubmit: (payload) async {
            if (supabase.auth.currentUser?.id != user.id) {
              throw StateError('Session changed');
            }
            if (attemptedPayload != null &&
                !samePayload(attemptedPayload!, payload)) {
              throw _RequestDraftChangedException();
            }
            attemptedPayload = Map<String, dynamic>.from(payload);
            final response = await backendApi.post(
              'requests',
              body: {'id': requestId, ...payload},
            );
            final created = response is Map ? response['data'] : null;
            if (supabase.auth.currentUser?.id != user.id ||
                created is! Map ||
                created['id']?.toString() != requestId) {
              throw StateError('Request not acknowledged');
            }
          },
        ),
      );
      if (created == true &&
          mounted &&
          supabase.auth.currentUser?.id == user.id) {
        setState(() {
          viewingMine = true;
        });
        await reload();
        if (supabase.auth.currentUser?.id == user.id) {
          _message('req_sent');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> sendOffer(Map<String, dynamic> request) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _message('req_login_offer');
      return;
    }
    if (user.id == request['buyer_id']) {
      _message('req_cannot_offer');
      return;
    }
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty || request['status'] != 'open' || _offering.contains(id)) {
      return;
    }
    setState(() {
      _offering.add(id);
    });
    try {
      final sent = await showDialog<bool>(
        context: context,
        builder: (_) => CarRequestEditorDialog(
          offer: true,
          errorKey: (error) => supabase.auth.currentUser?.id != user.id
              ? 'ui_business_session_changed'
              : error is BackendApiException && error.statusCode == 409
                  ? 'req_offer_sent'
                  : 'ui_request_offer_failed',
          onSubmit: (payload) async {
            if (supabase.auth.currentUser?.id != user.id) {
              throw StateError('Session changed');
            }
            final response = await backendApi.post(
              'requests/$id/offers',
              body: payload,
            );
            final created = response is Map ? response['data'] : null;
            if (supabase.auth.currentUser?.id != user.id ||
                created is! Map ||
                (created['id']?.toString().isEmpty ?? true)) {
              throw StateError('Offer not acknowledged');
            }
          },
        ),
      );
      if (mounted && supabase.auth.currentUser?.id == user.id) {
        await reload();
        if (sent == true && supabase.auth.currentUser?.id == user.id) {
          _message('req_offer_sent_to_you');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _offering.remove(id);
        });
      }
    }
  }

  Future<void> _decide(
    Map<String, dynamic> request, {
    Map<String, dynamic>? offer,
    String status = 'closed',
  }) async {
    final user = supabase.auth.currentUser;
    final id = request['id']?.toString() ?? '';
    if (user == null ||
        request['buyer_id'] != user.id ||
        id.isEmpty ||
        request['status'] != 'open' ||
        _busy.contains(id)) {
      return;
    }
    setState(() {
      _busy.add(id);
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(
            t(
              offer == null
                  ? 'req_close_request'
                  : status == 'accepted'
                      ? 'offer_accept'
                      : 'offer_reject',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(offer?['vehicle']?.toString() ?? _title(request)),
              if (offer != null)
                _requestPrice(offer['offer_price']?.toString() ?? ''),
              const SizedBox(height: 12),
              Text(t('ui_request_decision_confirm')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('ui_business_confirm')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (supabase.auth.currentUser?.id != user.id) {
        _message('ui_business_session_changed');
        return;
      }
      setState(() => _updatingDecisions.add(id));
      final response = offer == null
          ? await backendApi.patch('requests/$id/close')
          : await backendApi.patch(
              'requests/$id/offers/${offer['id']}',
              body: {'status': status},
            );
      final updated = response is Map ? response['data'] : null;
      final expectedId = offer?['id']?.toString() ?? id;
      if (supabase.auth.currentUser?.id != user.id ||
          updated is! Map ||
          updated['id']?.toString() != expectedId ||
          updated['status'] != status) {
        throw StateError('Decision not acknowledged');
      }
      if (mounted) {
        await reload();
        if (supabase.auth.currentUser?.id == user.id) {
          _message('ui_request_updated');
        }
      }
    } catch (_) {
      _message(
        supabase.auth.currentUser?.id != user.id
            ? 'ui_business_session_changed'
            : offer == null
                ? 'req_close_failed'
                : 'ui_request_decision_failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(id);
          _updatingDecisions.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_requests_cars')),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _creating ? null : createRequest,
              icon: const Icon(Icons.add_rounded),
              label: Text(t('misc_request_cta')),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mine in [false, true])
                    ChoiceChip(
                      label: Text(t(mine ? 'my_requests' : 'ui_requests_open')),
                      selected: viewingMine == mine,
                      onSelected: (_) {
                        if (viewingMine != mine) {
                          setState(() {
                            viewingMine = mine;
                            requests = loadRequests();
                          });
                        }
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_ActivityRowsResult>(
                future: requests,
                builder: (context, snapshot) {
                  if (viewingMine &&
                      backendAuthSession.user == null &&
                      supabase.auth.currentUser == null) {
                    return AppStateView(
                      title: t('req_login_publish'),
                      icon: AppIcons.locked,
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(reload);
                  }
                  final rows = snapshot.data?.rows ?? [];
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: rows.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: AppStateView(
                                    title: t(
                                      viewingMine
                                          ? 'account_requests_empty'
                                          : 'account_requests_none',
                                    ),
                                    icon: AppIcons.receipt,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final request = rows[index],
                                  scheme = Theme.of(context).colorScheme;
                              final mine = request['buyer_id'] ==
                                  supabase.auth.currentUser?.id;
                              final offers =
                                  ((request['car_request_offers'] as List?) ??
                                          [])
                                      .whereType<Map>()
                                      .map(
                                        (row) => Map<String, dynamic>.from(row),
                                      )
                                      .toList();
                              final sent = offers.any(
                                (offer) =>
                                    offer['seller_id'] ==
                                    supabase.auth.currentUser?.id,
                              );
                              final busy = _busy.contains(
                                request['id']?.toString(),
                              );
                              final years = [
                                request['year_from'],
                                request['year_to'],
                              ].where((value) => value != null).join(' – ');
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title(request),
                                      textDirection: contentTextDirection(
                                        context,
                                        _title(request),
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    _requestPrice(
                                      request['max_price']?.toString() ?? '',
                                    ),
                                    if (years.isNotEmpty)
                                      Text(
                                        '${t('field_year')}: \u2066$years\u2069',
                                      ),
                                    if ((request['province']?.toString() ?? '')
                                        .isNotEmpty)
                                      Text(
                                        '${t('field_province_prefix')}${request['province']}',
                                      ),
                                    if ((request['details']?.toString() ?? '')
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          request['details'].toString(),
                                          textDirection: contentTextDirection(
                                            context,
                                            request['details'].toString(),
                                          ),
                                        ),
                                      ),
                                    if (_updatingDecisions
                                        .contains(request['id']?.toString()))
                                      const LinearProgressIndicator(),
                                    if (!mine && request['status'] == 'open')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: sent ||
                                                    _offering.contains(
                                                      request['id']?.toString(),
                                                    )
                                                ? null
                                                : () => sendOffer(request),
                                            icon: const Icon(AppIcons.offer),
                                            label: Text(
                                              t(
                                                sent
                                                    ? 'req_offer_sent'
                                                    : 'req_offer_for_your_car',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (mine) ...[
                                      const Divider(height: 24),
                                      Text(
                                        t('req_seller_offers'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      if (request['status'] == 'open')
                                        TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => _decide(request),
                                          child: Text(t('req_close_request')),
                                        ),
                                      if (request['status'] == 'closed')
                                        Text(t('ad_status_closed')),
                                      if (offers.isEmpty)
                                        Text(
                                          t('req_seller_offers_waits'),
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      for (final offer in offers)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: scheme.outlineVariant,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                offer['vehicle']?.toString() ??
                                                    t('common_unspecified'),
                                                textDirection:
                                                    contentTextDirection(
                                                  context,
                                                  offer['vehicle']
                                                          ?.toString() ??
                                                      '',
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                              _requestPrice(
                                                offer['offer_price']
                                                        ?.toString() ??
                                                    '',
                                              ),
                                              if ((offer['message']
                                                          ?.toString() ??
                                                      '')
                                                  .isNotEmpty)
                                                Text(
                                                  offer['message'].toString(),
                                                  textDirection:
                                                      contentTextDirection(
                                                    context,
                                                    offer['message'].toString(),
                                                  ),
                                                ),
                                              Text(
                                                t(
                                                  offer['status'] == 'pending'
                                                      ? 'account_waiting_reply'
                                                      : offer['status'] ==
                                                              'accepted'
                                                          ? 'offer_accepted'
                                                          : offer['status'] ==
                                                                  'rejected'
                                                              ? 'offer_rejected'
                                                              : 'common_unspecified',
                                                ),
                                              ),
                                              if (offer['status'] ==
                                                      'pending' &&
                                                  request['status'] == 'open')
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    TextButton(
                                                      onPressed: busy
                                                          ? null
                                                          : () => _decide(
                                                                request,
                                                                offer: offer,
                                                                status:
                                                                    'rejected',
                                                              ),
                                                      child: Text(
                                                        t('offer_reject'),
                                                      ),
                                                    ),
                                                    FilledButton.tonal(
                                                      onPressed: busy
                                                          ? null
                                                          : () => _decide(
                                                                request,
                                                                offer: offer,
                                                                status:
                                                                    'accepted',
                                                              ),
                                                      child: Text(
                                                        t('offer_accept'),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const SectionCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                    color: Color(0x228B0D25), shape: BoxShape.circle),
                child: Icon(icon, color: red, size: 17),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextDirection _carNameDirection(BuildContext context, String value) {
  int rtl = 0;
  int ltr = 0;
  for (final int code in value.runes) {
    if ((code >= 0x0590 && code <= 0x08FF) || code == 0x200F) {
      rtl++;
    } else if ((code >= 0x0041 && code <= 0x005A) ||
        (code >= 0x0061 && code <= 0x007A) ||
        (code >= 0x00C0 && code <= 0x024F)) {
      ltr++;
    }
  }
  if (rtl == 0 && ltr == 0) return Directionality.of(context);
  return rtl > ltr ? TextDirection.rtl : TextDirection.ltr;
}

class CarCard extends StatefulWidget {
  final Map<String, dynamic> car;
  final bool square;
  final bool homeSectionStyle;

  const CarCard({
    super.key,
    required this.car,
    this.square = false,
    this.homeSectionStyle = false,
  });

  @override
  State<CarCard> createState() => _CarCardState();
}

class _CarCardState extends State<CarCard> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? sellerRep;
  bool _sellerRepLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSellerReputation();
  }

  @override
  void didUpdateWidget(covariant CarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.car['user_id'] != widget.car['user_id']) {
      sellerRep = null;
      _sellerRepLoaded = false;
      _loadSellerReputation();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// تقرأ من ذاكرة الدفعة بدل استعلام خاص بالبطاقة. إن لم تكن ضمن دفعة
  /// مُحمَّلة مسبقاً (بحث/مفضلة/ملف بائع) يجلب استعلاماً واحداً لنفسه،
  /// ونفس البائع لم يُستعلم عنه مرتين عبر بطاقات مختلفة.
  Future<void> _loadSellerReputation() async {
    final sellerId = widget.car['user_id']?.toString();
    if (sellerId == null || sellerId.isEmpty) {
      if (mounted) setState(() => _sellerRepLoaded = true);
      return;
    }
    final rep = await trustCache.reputationOfFuture(sellerId);
    if (mounted && widget.car['user_id']?.toString() == sellerId) {
      setState(() {
        sellerRep = rep;
        _sellerRepLoaded = true;
      });
    }
  }

  String _repTier() {
    final tier = sellerRep?['badge_tier']?.toString() ?? 'none';
    if (tier == 'none' || tier.isEmpty) return 'none';
    return tier;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    context.dependOnAppStrings();
    final car = widget.car;
    final images = carImageUrls(car);
    final plateRegions = carImagePlateRegions(car);
    final firstPlateRegions = (plateRegions != null && plateRegions.isNotEmpty)
        ? plateRegions.first
        : null;
    final status = car['status']?.toString() ?? 'active';
    final isSold = status == 'sold';
    final brand = car['brand']?.toString() ?? '';
    final model = car['model']?.toString() ?? '';
    final year = car['year']?.toString() ?? '';
    final city = car['city']?.toString() ?? '';
    final province = car['province']?.toString() ?? '';
    final price = car['price']?.toString() ?? '';
    final mileage = (car['mileage_km'] ?? car['mileage'])?.toString() ?? '';
    final fuel = car['fuel']?.toString() ?? '';
    final name =
        '$brand $model'.trim().isEmpty ? t('car_word') : '$brand $model'.trim();
    final TextDirection nameDir = _carNameDirection(context, name);
    final TextAlign nameAlign = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.start
        : TextAlign.left;

    final originalAmount =
        parseFormDecimal(car['original_price']?.toString() ?? '');
    if (widget.square) {
      final amount = parseFormDecimal(price);
      final primaryPrice = amount == null
          ? formatPriceDisplay(price)
          : widget.homeSectionStyle
              ? formatUsdSymbol(amount)
              : formatCurrencyLines(amount).split('\n').first;
      final secondaryPrice = amount != null && !widget.homeSectionStyle
          ? formatCurrencyLines(amount).split('\n').last
          : '';
      final trim = [
        car['trim'],
        car['trim_level'],
        car['grade'],
        car['version'],
      ]
          .map((value) => value?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      return CompactListingCard(
        title: name,
        titleDirection: nameDir,
        homeSectionStyle: widget.homeSectionStyle,
        primaryPrice: price.isEmpty ? '' : primaryPrice,
        secondaryPrice: secondaryPrice,
        previousPrice:
            amount != null && originalAmount != null && originalAmount > amount
                ? widget.homeSectionStyle
                    ? formatUsdSymbol(originalAmount)
                    : formatUsd(originalAmount)
                : '',
        metadata: [
          if (year.isNotEmpty) year,
          if (mileage.isNotEmpty) '$mileage ${t('unit_km_short')}',
          if (trim.isNotEmpty) trim,
        ].join(' • '),
        location: {
          if (city.trim().isNotEmpty) city.trim(),
          if (province.trim().isNotEmpty) province.trim()
        }.join('، '),
        photo: CarPhoto(
          urls: images,
          fit: BoxFit.cover,
          radius: 0,
          plateRegions: firstPlateRegions,
        ),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CarDetailsPage(car: car))),
        photoActions: [
          if (isSold)
            PositionedDirectional(
                bottom: 5,
                start: 5,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: red, borderRadius: BorderRadius.circular(6)),
                    child: Text(t('car_sold'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)))),
        ],
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final location = [city, province]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' · ');
    final amount = parseFormDecimal(price);
    final priceLines = (amount == null
            ? formatPriceDisplay(price)
            : formatCurrencyLines(amount))
        .split('\n');
    Widget details() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Directionality(
              textDirection: nameDir,
              child: Text(name,
                  textAlign: nameAlign,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: 8),
          if (price.isNotEmpty) ...[
            if (amount != null &&
                originalAmount != null &&
                originalAmount > amount)
              Text(formatUsd(originalAmount),
                  style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: scheme.onSurfaceVariant)),
            Text(priceLines.first,
                style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface, fontWeight: FontWeight.w800)),
            if (priceLines.length > 1)
              Text(priceLines.last,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
          ],
          if (year.isNotEmpty || mileage.isNotEmpty || fuel.isNotEmpty)
            Text(
                [
                  if (year.isNotEmpty) year,
                  if (mileage.isNotEmpty) '$mileage ${t('unit_km_short')}',
                  if (fuel.isNotEmpty) fuel,
                ].join(' • '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          if (location.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.location,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Expanded(
                          child:
                              Text(location, style: theme.textTheme.bodySmall)),
                    ])),
          if (images.length > 1)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    t('ui_photo_count')
                        .replaceAll('{count}', '${images.length}'),
                    style: theme.textTheme.bodySmall)),
          if (_sellerRepLoaded && _repTier() != 'none')
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.workspace_premium_rounded,
                      size: 18, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 5),
                  Flexible(
                      child: Text(badgeLabel(_repTier()),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600))),
                ])),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child:
                    Text(t('car_details'), style: theme.textTheme.bodySmall)),
            Icon(AppIcons.disclosure, size: 20, color: scheme.onSurfaceVariant),
          ]),
        ]);
    Widget photo() => AspectRatio(
        aspectRatio: carPhotoAspect,
        child: Stack(fit: StackFit.expand, children: [
          CarPhoto(
            urls: images,
            fit: BoxFit.cover,
            plateRegions: firstPlateRegions,
          ),
          if (isSold)
            PositionedDirectional(
                top: 8,
                start: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: red, borderRadius: BorderRadius.circular(8)),
                  child: Text(t('car_sold'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                )),
        ]));
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(imgRadius),
          side: BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CarDetailsPage(car: car))),
        child: LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          if (stacked) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  photo(),
                  Padding(padding: const EdgeInsets.all(16), child: details())
                ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 168, child: photo()),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.all(16), child: details())),
          ]);
        }),
      ),
    );
  }
}

class CompareCarsPage extends StatelessWidget {
  const CompareCarsPage({super.key});

  String _title(Map<String, dynamic> car) {
    final title = [car['brand'], car['model']]
        .where((v) => v != null)
        .map((v) => v.toString().trim())
        .where((v) => v.isNotEmpty)
        .join(' ');
    return title.isEmpty ? t('car_details') : title;
  }

  String _value(Map<String, dynamic> car, String field) {
    var value = car[field]?.toString().trim() ?? '';
    if (field == 'mileage_km' && value.isEmpty) {
      value = car['mileage']?.toString().trim() ?? '';
    }
    if (value.isEmpty) {
      return t(
        field == 'price' ? 'compare_price_unknown' : 'common_unspecified',
      );
    }
    if (field == 'price') {
      return formatPriceDisplay(value);
    }
    if (field == 'mileage_km' && parseFormDecimal(value) != null) {
      return '\u2066$value ${t('unit_km_short')}\u2069';
    }
    return value;
  }

  void _remove(Map<String, dynamic> car) {
    final id = car['id']?.toString().trim() ?? '';
    compareCars.value = compareCars.value
        .where(
          (item) => id.isEmpty
              ? !identical(item, car)
              : item['id']?.toString().trim() != id,
        )
        .toList();
  }

  Widget _header(BuildContext context, Map<String, dynamic> car, int index) {
    final scheme = Theme.of(context).colorScheme;
    final regions = carImagePlateRegions(car);
    return Container(
      key: ValueKey('compare_car_$index'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 88,
                  child: CarPhoto(
                    urls: carImageUrls(car),
                    aspectRatio: carPhotoAspect,
                    plateRegions:
                        regions?.isNotEmpty == true ? regions!.first : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _title(car),
                  textDirection: contentTextDirection(context, _title(car)),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CarDetailsPage(car: car)),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(t('ad_view')),
              ),
              TextButton.icon(
                key: ValueKey('compare_remove_$index'),
                onPressed: () => _remove(car),
                icon: const Icon(Icons.close_rounded),
                label: Text(t('ui_compare_remove')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('compare_title'))),
        body: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: compareCars,
          builder: (context, cars, _) {
            if (cars.isEmpty) {
              return AppStateView(
                title: t('compare_add_hint'),
                icon: AppIcons.compare,
              );
            }
            const fields = [
              ('field_price', 'price'),
              ('field_year', 'year'),
              ('field_province', 'province'),
              ('field_city', 'city'),
              ('field_body_type', 'body_type'),
              ('field_fuel', 'fuel'),
              ('field_transmission', 'transmission'),
              ('field_mileage', 'mileage_km'),
              ('field_color', 'color'),
            ];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 620 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 20;
                      final width = wide && cars.length > 1
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
                      final scheme = Theme.of(context).colorScheme;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (cars.length == 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                t('compare_add_second'),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var i = 0; i < cars.length; i++)
                                SizedBox(
                                  width: width,
                                  child: _header(context, cars[i], i),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          for (final field in fields)
                            Container(
                              key: ValueKey('compare_spec_${field.$2}'),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    t(field.$1),
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, inner) => Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        for (var i = 0; i < cars.length; i++)
                                          SizedBox(
                                            width: wide && cars.length > 1
                                                ? (inner.maxWidth - 16) / 2
                                                : inner.maxWidth,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _title(cars[i]),
                                                  textDirection:
                                                      contentTextDirection(
                                                    context,
                                                    _title(cars[i]),
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                SelectableText(
                                                  _value(cars[i], field.$2),
                                                  textDirection:
                                                      contentTextDirection(
                                                    context,
                                                    _value(
                                                      cars[i],
                                                      field.$2,
                                                    ),
                                                  ),
                                                  key: ValueKey(
                                                    'compare_${field.$2}_$i',
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: field.$2 ==
                                                                'price'
                                                            ? scheme
                                                                .onPrimaryContainer
                                                            : scheme.onSurface,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => compareCars.value = [],
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(t('compare_clear')),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MarketPriceEstimate {
  final double medianPrice;
  final int sampleCount;
  final bool local;

  const MarketPriceEstimate({
    required this.medianPrice,
    required this.sampleCount,
    required this.local,
  });
}

class _CarDetailActions extends StatefulWidget {
  const _CarDetailActions({required this.car});

  final Map<String, dynamic> car;

  @override
  State<_CarDetailActions> createState() => _CarDetailActionsState();
}

class _CarDetailActionsState extends State<_CarDetailActions> {
  bool _favorite = false;
  bool _loading = true;
  bool _writing = false;
  int _read = 0;

  @override
  void initState() {
    super.initState();
    trustCache.addListener(_favoriteChanged);
    _loadFavorite();
  }

  @override
  void didUpdateWidget(covariant _CarDetailActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.car['id']?.toString() != widget.car['id']?.toString()) {
      _favorite = trustCache.isFavorite(widget.car['id']?.toString());
      _loading = true;
      _loadFavorite();
    }
  }

  @override
  void dispose() {
    trustCache.removeListener(_favoriteChanged);
    super.dispose();
  }

  void _favoriteChanged() {
    if (!mounted) return;
    setState(() {
      _favorite = trustCache.isFavorite(widget.car['id']?.toString());
      _loading = true;
    });
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final read = ++_read;
    final id = widget.car['id']?.toString();
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final value = await trustCache.favoriteOf(id);
    if (mounted && read == _read) {
      setState(() {
        _favorite = value;
        _loading = _writing || trustCache.favoriteBusy(id);
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_loading || _writing) return;
    final user = backendAuthSession.user;
    final id = widget.car['id']?.toString();
    if (user == null) {
      _showMessage(t('ad_login_to_fav'));
      return;
    }
    if (id == null || id.isEmpty) {
      _showMessage(t('ad_no_id'));
      return;
    }
    final generation = trustCache.beginFavoriteChange(id);
    if (generation == null) return;
    final removing = trustCache.isFavorite(id);
    setState(() {
      _loading = true;
      _writing = true;
    });
    try {
      final response = await backendApi.put(
        'favorites/$id',
        body: {'favorite': !removing},
        backendOnly: true,
      );
      if (backendAuthSession.user?.id != user.id ||
          !trustCache.favoriteChangeCurrent(id, generation)) {
        return;
      }
      if (response is! Map ||
          response['car_id']?.toString() != id ||
          response['favorite'] != !removing) {
        throw StateError('Favorite change not acknowledged');
      }
      trustCache.setFavorite(id, !removing);
      if (mounted && widget.car['id']?.toString() == id) {
        setState(() => _favorite = !removing);
      }
    } on BackendApiException catch (error) {
      if (error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.message == 'Backend authentication required') {
        _showMessage(t('login_required_first'));
      } else {
        _showMessage(t('ui_favorite_failed'));
      }
    } catch (_) {
      _showMessage(t('ui_favorite_failed'));
    } finally {
      trustCache.endFavoriteChange(id, generation);
      if (mounted) {
        setState(() {
          _loading = false;
          _writing = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, textDirection: appLocale.direction)),
      );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      children: [
        IconButton.filledTonal(
          tooltip: t('ad_saved_deal'),
          onPressed: _loading ? null : _toggleFavorite,
          icon: Icon(
            AppIcons.favorite,
            fill: _favorite ? 1 : 0,
            color: _favorite ? scheme.onPrimaryContainer : null,
          ),
        ),
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: compareCars,
          builder: (context, selected, _) {
            final isSelected = selected.any(
              (item) => item['id']?.toString() == widget.car['id']?.toString(),
            );
            return IconButton.filledTonal(
              tooltip: t('ad_compare'),
              onPressed: () => toggleCompareCar(widget.car, context),
              icon: Icon(
                AppIcons.compare,
                color: isSelected ? scheme.onPrimaryContainer : null,
              ),
            );
          },
        ),
      ],
    );
  }
}

class CarDetailsPage extends StatefulWidget {
  final Map<String, dynamic> car;

  const CarDetailsPage({super.key, required this.car});

  @override
  State<CarDetailsPage> createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends State<CarDetailsPage>
    with AccountFeedState<CarDetailsPage> {
  int current = 0;
  List<List<PlateRegion>?>? plateRegions;

  late Future<MarketPriceEstimate?> marketEstimate;
  bool _isAdmin = false;
  bool _adminDeleting = false;
  bool _sharing = false;
  final ScrollController _detailsScrollController = ScrollController();
  final GlobalKey<_SimilarCarsSectionState> _similarCarsKey =
      GlobalKey<_SimilarCarsSectionState>();

  /// Track which image URLs have been preloaded to avoid duplicates
  final Set<String> _preloadedUrls = {};

  /// Guard to ensure image preloading runs only once
  bool _imagesPreloaded = false;

  @override
  void reloadAccountFeed() {
    _isAdmin = false;
    _adminDeleting = false;
    unawaited(_checkAdmin());
  }

  @override
  void initState() {
    super.initState();
    _detailsScrollController.addListener(_loadMoreSimilarCarsNearBottom);
    marketEstimate = loadMarketEstimate().catchError((Object error) => null);
    _checkAdmin();
  }

  void _loadMoreSimilarCarsNearBottom() {
    if (_detailsScrollController.hasClients &&
        _detailsScrollController.position.extentAfter < 650) {
      _similarCarsKey.currentState?.loadMore();
    }
  }

  @override
  void dispose() {
    _detailsScrollController.removeListener(_loadMoreSimilarCarsNearBottom);
    _detailsScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesPreloaded) {
      _imagesPreloaded = true;
      _preloadAdjacentImages();
    }
  }

  /// Preload adjacent images for smooth swipe navigation
  void _preloadAdjacentImages() {
    final urls = carImageUrls(widget.car);
    if (urls.isEmpty || current < 0 || current >= urls.length) return;
    // Preload current, next, and previous (if exists)
    final indicesToPreload = <int>{current};
    if (current + 1 < urls.length) indicesToPreload.add(current + 1);
    if (current - 1 >= 0) indicesToPreload.add(current - 1);

    for (final i in indicesToPreload) {
      final url = urls[i];
      if (!_preloadedUrls.contains(url)) {
        _preloadedUrls.add(url);
        precacheImage(
          NetworkImage(url),
          context,
          onError: (Object error, StackTrace? stack) {},
        );
      }
    }
  }

  /// Preload next/previous image when page changes
  void _onPageChanged(int index) {
    setState(() => current = index);
    _preloadAdjacentImages();
  }

  /// يتحقّق من صلاحية الأدمن لعرض زر الحذف فقط.
  /// الفحص ليس الحماية — الحماية في `admin_delete_ad` داخل Supabase.
  Future<void> _checkAdmin() async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    final isAdmin = await currentUserIsAdmin();
    if (!mounted || !accountMatches(actor, epoch)) return;
    setState(() => _isAdmin = isAdmin);
  }

  /// حذف إداري للإعلان الحالي، ثم العودة للخلف.
  Future<void> _adminDeleteThisCar() async {
    if (_adminDeleting || !_isAdmin) return;
    final id = widget.car['id']?.toString();
    final account = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (account == null || id == null || id.isEmpty) return;
    setState(() => _adminDeleting = true);
    try {
      final confirmed = await confirmAdminDeleteAd(context,
          itemTitle: [
            widget.car['brand'],
            widget.car['model'],
            widget.car['year']
          ].where((value) => value != null).join(' '),
          sectionKey: 'section_cars');
      if (!mounted || confirmed != true || !accountMatches(account, epoch)) {
        return;
      }
      final ok = await adminDeleteAd('cars', id);
      if (!mounted || !accountMatches(account, epoch)) return;
      adminDeleteMessage(context, ok);
      if (ok) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted && accountMatches(account, epoch)) {
        setState(() => _adminDeleting = false);
      }
    }
  }

  /// رقم البائع كما كُتب في الإعلان.
  ///
  /// `seller_phone` هو العمود الذي تكتبه صفحة الإضافة وصفحة التعديل. `phone`
  /// قراءة احتياطية للإعلانات القديمة التي سبقت عمود `seller_phone`، ولا
  /// عمود جديد في القاعدة: الحقلان موجودان أصلًا.
  String get _rawSellerPhone {
    final Object? value = widget.car['seller_phone'] ?? widget.car['phone'];
    return value?.toString().trim() ?? '';
  }

  /// الرقم مُنقّى وجاهز، أو `null` إن كان الإعلان بلا رقم صالح.
  ///
  /// صفرُه يخفي زرَّي الاتصال والواتساب معًا — زرٌّ يفتح صفحة خطأ أسوأ من
  /// زرٍّ غير موجود.
  SellerPhone? get _sellerPhone => SellerPhone.parse(_rawSellerPhone);

  void _contactMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textDirection: appLocale.direction)),
    );
  }

  /// يفتح تطبيق الهاتف على رقم البائع.
  Future<void> callSeller() async {
    final SellerPhone? phone = _sellerPhone;
    if (phone == null) return;
    try {
      final bool opened = await launchUrl(
        Uri(scheme: 'tel', path: phone.telTarget),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _contactMessage(t('misc_call_app_failed'));
    } catch (_) {
      _contactMessage(t('misc_call_app_failed'));
    }
  }

  /// يفتح محادثة واتساب مباشرة مع البائع.
  Future<void> whatsappSeller() async {
    final SellerPhone? phone = _sellerPhone;
    if (phone == null) return;
    try {
      final bool opened = await launchUrl(
        Uri.https('wa.me', '/${phone.whatsappDigits}'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _contactMessage(t('misc_whatsapp_failed'));
    } catch (_) {
      _contactMessage(t('misc_whatsapp_failed'));
    }
  }

  /// زرا الاتصال والواتساب — يظهران معًا أو يختفيان معًا.
  ///
  /// الشكل يتبع أزرار التواصل الموجودة في صفحة إعلان الشركة: زر محدَّد
  /// (`OutlinedButton`) بارتفاع موحّد، فيأخذ كلٌّ منهما نصف العرض.
  Widget _buildSellerContactButtons() {
    if (_sellerPhone == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ResponsiveFormPair(
        first: _sellerContactButton(
          icon: AppIcons.call,
          label: t('settings_call'),
          onTap: callSeller,
        ),
        second: _sellerContactButton(
          icon: AppIcons.chat,
          label: t('contact_whatsapp'),
          onTap: whatsappSeller,
        ),
      ),
    );
  }

  Widget _sellerContactButton({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) =>
      OutlinedButton.icon(
        onPressed: () => onTap(),
        icon: Icon(icon, size: 20),
        label: Text(label, textAlign: TextAlign.center),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      );

  Future<void> _shareCar() async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: buildCarShareText(widget.car),
          sharePositionOrigin: shareOrigin(context),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('ui_support_share_failed'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  Future<MarketPriceEstimate?> loadMarketEstimate() async {
    final car = widget.car;
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';
    final year = int.tryParse(car['year']?.toString() ?? '');
    if (brand.isEmpty || model.isEmpty || year == null) return null;

    final response = await backendApi.get(
      'cars/search',
      query: {
        'filters': jsonEncode([
          {'column': 'brand', 'operator': 'eq', 'value': brand},
          {'column': 'model', 'operator': 'eq', 'value': model},
          {'column': 'year', 'operator': 'eq', 'value': '$year'},
        ]),
        'limit': '100',
      },
    );
    if (response is! Map || response['data'] is! List) {
      throw StateError('Comparable cars response is invalid');
    }
    final rows = List<Map<String, dynamic>>.from(response['data'] as List);
    final currentId = car['id']?.toString();
    final comparable = List<Map<String, dynamic>>.from(rows)
        .where((row) => row['id']?.toString() != currentId)
        .map(
          (row) => MapEntry(
            row,
            double.tryParse(
              (row['price'] ?? '').toString().replaceAll(',', ''),
            ),
          ),
        )
        .where((entry) => entry.value != null && entry.value! > 0)
        .toList();

    final province = car['province']?.toString().trim() ?? '';
    final localCars = province.isEmpty
        ? <MapEntry<Map<String, dynamic>, double>>[]
        : comparable
            .where(
              (entry) => entry.key['province']?.toString().trim() == province,
            )
            .toList();
    final useLocal = localCars.length >= 3;
    final sample = useLocal ? localCars : comparable;
    if (sample.length < 3) return null;

    final prices = sample.map((entry) => entry.value!).toList()..sort();
    final middle = prices.length ~/ 2;
    final median = prices.length.isOdd
        ? prices[middle]
        : (prices[middle - 1] + prices[middle]) / 2;
    return MarketPriceEstimate(
      medianPrice: median,
      sampleCount: sample.length,
      local: useLocal,
    );
  }

  void openImage(int index) {
    final images = carImageUrls(widget.car);
    if (images.isEmpty) return;
    final regions = plateRegions;
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: appLocale.direction,
        child: PhotoGallery(
          count: images.length,
          initialIndex: index,
          hint: t('car_swipe'),
          resetZoomLabel: t('ui_reset_zoom'),
          itemBuilder: (context, imageIndex) => CarPhoto(
            urls: [images[imageIndex]],
            fit: BoxFit.contain,
            plateRegions: regions != null && regions.length > imageIndex
                ? regions[imageIndex]
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> submitOffer(
    String sellerId,
    String carName,
    String originalPrice,
  ) async {
    final user = backendAuthSession.user;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('req_login_price'))));
      return;
    }
    if (sellerId.isEmpty || widget.car['id'] == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('ad_cannot_seller'))));
      return;
    }
    if (user.id == sellerId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('req_cannot_price'))));
      return;
    }
    if (_offerDialogOpen) return;
    _offerDialogOpen = true;
    try {
      final sent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VehicleOfferDialog(
          carId: widget.car['id'].toString(),
          sellerId: sellerId,
          carTitle: carName,
          originalPrice: originalPrice,
        ),
      );
      if (sent == true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('req_offer_sent_to_seller'))));
      }
    } finally {
      _offerDialogOpen = false;
    }
  }

  bool _offerDialogOpen = false,
      _saleDialogOpen = false,
      _reportDialogOpen = false;
  bool _markedSold = false;
  String get _carStatus =>
      _markedSold ? 'sold' : widget.car['status']?.toString() ?? 'active';

  Future<void> reportCar(String sellerId) async {
    if (_reportDialogOpen) return;
    final user = backendAuthSession.user;
    if (user == null || sellerId == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(user == null ? 'report_login_first' : 'req_cannot_report'),
          ),
        ),
      );
      return;
    }
    _reportDialogOpen = true;
    try {
      final feedback = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VehicleReportDialog(
          carId: widget.car['id']?.toString() ?? '',
          sellerId: sellerId,
        ),
      );
      if (mounted &&
          feedback != null &&
          backendAuthSession.user?.id == user.id) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(feedback))));
      }
    } finally {
      _reportDialogOpen = false;
    }
  }

  Future<void> markCarAsSold() async {
    if (_saleDialogOpen || _carStatus == 'sold') return;
    final ownerId =
        (widget.car['user_id'] ?? widget.car['seller_id'])?.toString() ?? '';
    if (backendAuthSession.user?.id != ownerId || ownerId.isEmpty) return;
    _saleDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VehicleSaleDialog(
          carId: widget.car['id']?.toString() ?? '',
          ownerId: ownerId,
        ),
      );
      if (mounted &&
          confirmed == true &&
          backendAuthSession.user?.id == ownerId) {
        setState(() => _markedSold = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('misc_status_to_sold'))));
      }
    } finally {
      _saleDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final car = widget.car;
    final images = carImageUrls(car);
    plateRegions = carImagePlateRegions(car);
    final status = _carStatus;
    final isSold = status == 'sold';
    final viewerId = _authenticatedUserId;
    final isOwner = viewerId != null &&
        (car['user_id']?.toString() ?? car['seller_id']?.toString()) ==
            viewerId;
    final brand = car['brand']?.toString() ?? '';
    final model = car['model']?.toString() ?? '';
    final year = car['year']?.toString() ?? '';
    final city = car['city']?.toString() ?? '';
    final province = car['province']?.toString() ?? '';
    final price = car['price']?.toString() ?? '';
    final priceAmount = parseFormDecimal(price);
    final priceLines =
        (priceAmount == null ? price : formatCurrencyLines(priceAmount)).split(
      '\n',
    );
    final description = car['description']?.toString() ?? '';
    final mileage = (car['mileage_km'] ?? car['mileage'])?.toString() ?? '';
    final fuel = car['fuel']?.toString() ?? '';
    final transmission = car['transmission']?.toString() ?? '';
    final bodyType = car['body_type']?.toString() ?? '';
    final color = car['color']?.toString() ?? '';
    final createdAt = car['created_at']?.toString() ?? '';
    final sellerId = (car['user_id'] ?? car['seller_id'])?.toString() ?? '';
    final sellerName =
        car['seller_name']?.toString() ?? t('default_seller_name');
    final name =
        '$brand $model'.trim().isEmpty ? t('car_word') : '$brand $model'.trim();

    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            t('car_details'),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: t('ad_share'),
              icon: const Icon(AppIcons.share),
              onPressed: _sharing ? null : _shareCar,
            ),
            if (_isAdmin)
              IconButton(
                tooltip: t('admin_delete_ad'),
                icon: _adminDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.delete),
                onPressed: _adminDeleting ? null : _adminDeleteThisCar,
              ),
          ],
        ),
        body: ListView(
          controller: _detailsScrollController,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            if (images.isNotEmpty) ...[
              // صورة رئيسية تمتد لعرض الشاشة كاملاً — استخدام LayoutBuilder للحصول على العرض الكامل
              LayoutBuilder(
                builder: (context, constraints) {
                  final double screenWidth = MediaQuery.of(context).size.width;
                  return Center(
                    child: SizedBox(
                      width: screenWidth,
                      child: AspectRatio(
                        aspectRatio: carPhotoAspect,
                        child: Stack(
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: PageView.builder(
                                itemCount: images.length,
                                onPageChanged: _onPageChanged,
                                itemBuilder: (context, index) {
                                  final plateRegionsForIndex =
                                      (plateRegions != null &&
                                              plateRegions!.length > index)
                                          ? plateRegions![index]
                                          : null;
                                  return GestureDetector(
                                    onTap: () => openImage(index),
                                    child: CarPhoto(
                                      urls: [images[index]],
                                      fit: BoxFit.contain,
                                      plateRegions: plateRegionsForIndex,
                                    ),
                                  );
                                },
                              ),
                            ),
                            PositionedDirectional(
                              top: 8,
                              end: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: _CarDetailActions(car: car),
                              ),
                            ),
                            if (isSold)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B0D25),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        t('car_sold'),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
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
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 76,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final selected = index == current;
                      return GestureDetector(
                        onTap: () => openImage(index),
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: EdgeInsets.all(selected ? 2 : 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(imgRadius),
                            border: Border.all(
                              color: selected ? red : AppColors.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: CarPhoto(
                            urls: [images[index]],
                            radius: imgRadius - (selected ? 2 : 1),
                            iconScale: 0.34,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '${current + 1} / ${images.length}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ] else
              Container(
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(imgRadius),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.shadow,
                ),
                child: CarPhoto(
                  urls: const [],
                  aspectRatio: carPhotoAspect,
                  placeholderColor: card,
                  iconScale: 0.24,
                ),
              ),
            const SizedBox(height: 18),
            Text(
              name,
              textDirection: contentTextDirection(context, name),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            if (price.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priceLines.first,
                      key: const ValueKey('vehicle_primary_price'),
                      textDirection: TextDirection.ltr,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    if (priceLines.length > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        priceLines.last,
                        key: const ValueKey('vehicle_secondary_price'),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            if (createdAt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  t('ui_listing_date').replaceAll('{date}', createdAt),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            FutureBuilder<MarketPriceEstimate?>(
              key: const ValueKey('vehicle_market_estimate'),
              future: marketEstimate,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    margin: const EdgeInsets.only(top: 14, bottom: 14),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.shadow,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.insights_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer),
                        SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('compare_market_price'),
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              SizedBox(height: 4),
                              Text(
                                t('compare_comparing'),
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Container(
                    margin: const EdgeInsets.only(top: 14, bottom: 14),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.shadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('compare_market_price'),
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t('compare_price_loading'),
                          style: TextStyle(color: AppColors.textStrong),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            marketEstimate = loadMarketEstimate().catchError(
                              (Object error) => null,
                            );
                          }),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(t('common_retry')),
                        ),
                      ],
                    ),
                  );
                }
                final estimate = snapshot.data;
                if (estimate == null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.shadow,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insights_rounded,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            t('compare_need_more'),
                            style: TextStyle(color: AppColors.textStrong),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final askingPrice = double.tryParse(
                  price.replaceAll(',', '').trim(),
                );
                final difference = askingPrice == null
                    ? 0.0
                    : (askingPrice - estimate.medianPrice) /
                        estimate.medianPrice;
                final Color statusColor;
                final String statusLabel;
                if (askingPrice == null) {
                  statusColor = AppColors.textStrong;
                  statusLabel = t('compare_price_unknown');
                } else if (difference < -0.10) {
                  statusColor = const Color(0xFF66D19E);
                  statusLabel = t('compare_lower_ads');
                } else if (difference > 0.10) {
                  statusColor = Colors.amber;
                  statusLabel = t('compare_higher_ads');
                } else {
                  statusColor = const Color(0xFF66D19E);
                  statusLabel = t('compare_close_ads');
                }

                return Container(
                  margin: const EdgeInsets.only(top: 14, bottom: 14),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: statusColor.withValues(alpha: .4),
                    ),
                    boxShadow: AppColors.shadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.insights_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t('compare_market_price'),
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(estimate.medianPrice),
                        style: TextStyle(color: AppColors.textStrong),
                      ),
                      Text(
                        t(
                          estimate.local
                              ? 'ui_comparable_local'
                              : 'ui_comparable_all',
                        ).replaceAll('{count}', '${estimate.sampleCount}'),
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            if (isOwner && !isSold)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: markCarAsSold,
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(t('ui_mark_vehicle_sold')),
                ),
              ),
            if (isOwner && !isSold) const SizedBox(height: 12),
            if (isSold)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0D25).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF8B0D25).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t('ad_status_sold_check'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isSold)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('vehicle_offer_action'),
                  onPressed: () => submitOffer(sellerId, name, price),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(AppIcons.offer),
                  label: Text(t('offer_price_cta')),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('car_specs'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final largeText =
                          MediaQuery.textScalerOf(context).scale(14) > 19;
                      final columns = constraints.maxWidth >= 560
                          ? 3
                          : constraints.maxWidth >= 280 && !largeText
                              ? 2
                              : 1;
                      final tiles = <Widget>[
                        if (year.isNotEmpty)
                          _specChip(
                            Icons.calendar_month_rounded,
                            t('field_year'),
                            year,
                          ),
                        if (mileage.isNotEmpty)
                          _specChip(
                            Icons.speed_rounded,
                            t('field_mileage'),
                            '$mileage ${t('unit_km_short')}',
                          ),
                        if (fuel.isNotEmpty)
                          _specChip(
                            Icons.local_gas_station_outlined,
                            t('field_fuel'),
                            fuel,
                          ),
                        if (transmission.isNotEmpty)
                          _specChip(
                            Icons.settings_rounded,
                            t('field_transmission'),
                            transmission,
                          ),
                        if (bodyType.isNotEmpty)
                          _specChip(
                            AppIcons.cars,
                            t('field_body_type'),
                            bodyType,
                          ),
                        if (color.isNotEmpty)
                          _specChip(
                            Icons.palette_outlined,
                            t('field_color'),
                            color,
                          ),
                        if (city.isNotEmpty)
                          _specChip(
                            AppIcons.location,
                            t('field_city'),
                            city,
                          ),
                        if (province.isNotEmpty)
                          _specChip(
                            Icons.map_outlined,
                            t('field_province'),
                            province,
                          ),
                        _specChip(
                          Icons.photo_library_outlined,
                          t('common_images'),
                          '${images.length}',
                        ),
                      ];
                      return Column(children: [
                        for (var row = 0; row < tiles.length; row += columns)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: row + columns < tiles.length ? 12 : 0),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var column = 0;
                                      column < columns;
                                      column++) ...[
                                    if (column > 0) const SizedBox(width: 12),
                                    Expanded(
                                        child: row + column < tiles.length
                                            ? tiles[row + column]
                                            : const SizedBox.shrink()),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ]);
                    },
                  ),
                ],
              ),
            ),
            if (sellerId.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Material(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(AppIcons.account,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        SellerVerifiedTick(sellerId: sellerId),
                      ],
                    ),
                    subtitle: FutureBuilder<Map<String, dynamic>?>(
                      future: trustCache.reputationOfFuture(sellerId),
                      builder: (context, snapshot) {
                        final rep = snapshot.data;
                        final tier = rep?['badge_tier']?.toString() ?? 'none';
                        if (tier == 'none' || tier.isEmpty) {
                          return Text(t('misc_profile_view_desc'));
                        }
                        final avg =
                            (rep?['avg_rating'] as num?)?.toDouble() ?? 0;
                        final count =
                            (rep?['review_count'] as num?)?.toInt() ?? 0;
                        return SellerProfileSummary(
                          description: t('misc_profile_view_desc'),
                          tierLabel: badgeLabel(tier),
                          rating: avg,
                          reviewCount: count,
                          badgeColor: badgeColor(tier),
                          textColor: AppColors.textStrong,
                        );
                      },
                    ),
                    trailing: Icon(AppIcons.disclosure),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerProfilePage(
                          sellerId: sellerId,
                          sellerName: sellerName,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            _buildSellerContactButtons(),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => reportCar(sellerId),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(t('report_ad')),
              ),
            ),
            const SizedBox(height: 10),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                t('field_desc'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.shadow,
                ),
                child: Text(
                  description,
                  textDirection: contentTextDirection(context, description),
                  style: TextStyle(color: AppColors.textStrong, height: 1.6),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _SimilarCarsSection(key: _similarCarsKey, car: car),
          ],
        ),
      ),
    );
  }

  Widget _specChip(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: ValueKey('vehicle_spec:$label'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.onPrimaryContainer),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textDirection: contentTextDirection(context, value),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarCarsSection extends StatefulWidget {
  const _SimilarCarsSection({super.key, required this.car});

  final Map<String, dynamic> car;

  @override
  State<_SimilarCarsSection> createState() => _SimilarCarsSectionState();
}

class _SimilarCarsSectionState extends State<_SimilarCarsSection> {
  static const int _pageSize = 20;

  List<Map<String, dynamic>> _cars = const [];
  bool _loading = true;
  bool _failed = false;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _hasMore = true;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final params = <String, String>{'limit': '$_pageSize', 'offset': '0'};
    final brand = widget.car['brand']?.toString().trim() ?? '';
    if (brand.isNotEmpty) params['brand'] = brand;
    try {
      final response = await backendApi.get(
        'cars',
        query: params,
        anonymous: true,
      );
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! List) {
        throw StateError('Similar cars response is invalid');
      }
      final currentId = widget.car['id']?.toString();
      final rows = List<Map<String, dynamic>>.from(
        (response['data'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map)),
      ).where((item) => item['id']?.toString() != currentId).toList();
      await trustCache.preloadForRows(rows);
      if (!mounted) return;
      setState(() {
        _cars = rows;
        _offset = (response['data'] as List).length;
        _hasMore = (response['data'] as List).length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Similar cars load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> loadMore() async {
    if (!mounted || _loading || _loadingMore || !_hasMore || _failed) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final params = <String, String>{
      'limit': '$_pageSize',
      'offset': '$_offset',
    };
    final brand = widget.car['brand']?.toString().trim() ?? '';
    if (brand.isNotEmpty) params['brand'] = brand;
    try {
      final response = await backendApi.get(
        'cars',
        query: params,
        anonymous: true,
      );
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! List) {
        throw StateError('Similar cars page response is invalid');
      }
      final rawRows = response['data'] as List;
      final currentId = widget.car['id']?.toString();
      final rows = List<Map<String, dynamic>>.from(
        rawRows.map((item) => Map<String, dynamic>.from(item as Map)),
      ).where((item) => item['id']?.toString() != currentId).toList();
      await trustCache.preloadForRows(rows);
      if (!mounted) return;
      final knownIds =
          _cars.map((car) => car['id']?.toString()).whereType<String>().toSet();
      setState(() {
        _cars.addAll(rows.where((car) {
          final id = car['id']?.toString();
          return id == null || knownIds.add(id);
        }));
        _offset += rawRows.length;
        _hasMore = rawRows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      debugPrint('Similar cars next page failed: $error');
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('car_similar_ads'),
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      );
    }
    if (_failed) {
      return AppStatePanel(
        key: const ValueKey('similar_cars_error'),
        title: t('car_similar_ads'),
        message: t('ui_load_error_body'),
        icon: AppIcons.cloudOff,
        isError: true,
        actionLabel: t('ui_retry'),
        onAction: _load,
      );
    }
    if (_cars.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('car_similar_ads'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _buildHomeCarGrid(context, _cars),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_moreFailed)
          AppStatePanel(
            key: const ValueKey('similar_cars_more_error'),
            title: t('ui_load_error_title'),
            message: t('ui_load_error_body'),
            icon: AppIcons.cloudOff,
            isError: true,
            actionLabel: t('ui_retry'),
            onAction: loadMore,
          ),
      ],
    );
  }
}

class SectionPage extends StatefulWidget {
  final String title;
  final IconData icon;
  final String? brand;
  final bool showAddAction;
  const SectionPage(
      {super.key,
      required this.title,
      required this.icon,
      this.brand,
      this.showAddAction = true});

  @override
  State<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<SectionPage>
    with AutomaticKeepAliveClientMixin {
  /// حجم الصفحة الواحدة. زيد إلى 30 لتقليل عدد الطلبات وتحسين التمرير.
  static const int _pageSize = 30;

  /// مسافة التحميل المبكر من أسفل القائمة (بالبكسل).
  /// قلل إلى 500 لبدء التحميل مبكراً وتجنب التوقف عند التمرير السريع.
  static const double _loadMoreThreshold = 500;

  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false, _moreFailed = false;
  int _generation = 0, _nextOffset = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant SectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title || oldWidget.brand != widget.brand) {
      _items.clear();
      unawaited(_loadFirstPage());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// جدول القسم. `null` يعني قسماً بلا جدول (Jobs) — كما كان: يعرض حالة
  /// فارغة دون أي طلب.
  String? get _table {
    if (widget.title == kSectionCars) return 'cars_public';
    if (widget.title == kSectionMarket) return 'market_items';
    return null;
  }

  /// `_loadingMore` يمنع طلب الصفحة نفسها مرتين عند تتابع إيماءات التمرير.
  void _onScroll() {
    if (!_scroll.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _moreFailed ||
        _failed) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;
    _fetch(reset: false);
  }

  Future<void> refresh() => _loadFirstPage();

  Future<void> _loadFirstPage() => _fetch(reset: true);

  Future<void> _fetch({required bool reset}) async {
    if (!mounted || (!reset && (_loading || _loadingMore || !_hasMore))) return;
    final generation = reset ? ++_generation : _generation;
    final table = _table;
    final brand = widget.brand;
    final offset = reset ? 0 : _nextOffset;
    final isCars = table == 'cars_public';
    final isMarket = table == 'market_items';
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
      _failed = _moreFailed = false;
    });
    if (table == null) {
      setState(() {
        _items.clear();
        _loading = _loadingMore = _hasMore = false;
      });
      return;
    }
    try {
      final Map<String, dynamic> response;
      if (isCars) {
        final params = <String, String>{
          'limit': '$_pageSize',
          'offset': '$offset',
        };
        if (brand != null) params['brand'] = brand;
        final qs = params.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
        final raw = await backendApi.get('cars?$qs');
        response = raw is Map
            ? Map<String, dynamic>.from(raw)
            : const <String, dynamic>{};
      } else if (isMarket) {
        // Backend GET /api/market/items supports limit only ({success,data}); no offset/brand. Do not invent params.
        final raw = await backendApi.get('market/items?limit=$_pageSize');
        response = raw is Map
            ? Map<String, dynamic>.from(raw)
            : const <String, dynamic>{};
      } else {
        setState(() {
          _items.clear();
          _loading = _loadingMore = _hasMore = false;
        });
        return;
      }
      final data = response['data'];
      final rows = data is List
          ? List<Map<String, dynamic>>.from(
              data.map((e) => Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];
      await trustCache.preloadForRows(rows);
      if (!mounted || generation != _generation) return;
      if (isCars) _preloadImages(rows);
      final ids = <String>{};
      final combined = (reset || isMarket) ? rows : [..._items, ...rows];
      setState(() {
        _items
          ..clear()
          ..addAll(combined.where((row) {
            final id = row['id']?.toString();
            return id == null || ids.add(id);
          }));
        _nextOffset = isMarket ? rows.length : offset + rows.length;
        // Market backend has no offset pagination; prevent repeated/scroll fetches of same page.
        _hasMore = isMarket ? false : rows.length == _pageSize;
        _loading = _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = _loadingMore = false;
        if (reset) {
          _failed = true;
        } else {
          _moreFailed = true;
        }
      });
    }
  }

  /// Preload first image of visible cars only (first 4-6) to warm up Flutter's image cache
  /// for smoother scrolling. Fire-and-forget to not block UI.
  /// Avoids preloading images already in memory cache.
  void _preloadImages(List<Map<String, dynamic>> rows) {
    const int maxPreload = 6; // Only preload what's visible on first screen
    int preloaded = 0;
    for (final row in rows) {
      if (preloaded >= maxPreload) break;
      final urls = carImageUrls(row);
      if (urls.isNotEmpty && mounted) {
        smartPrecacheImage(urls.first, context);
        preloaded++;
      }
    }
  }

  Future<void> addCarAd() async {
    if (_authenticatedUserId == null) {
      _msg(t('misc_login_first_publish'));
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AddCarTab()));
    if (mounted) await _loadFirstPage();
  }

  Future<void> addGenericAd() async {
    // Market/jobs create flow must not touch guarded `supabase` getter in local test mode.
    final hasUser = kMotriLocalTest
        ? backendAuthSession.user != null
        : (backendAuthSession.user != null ||
            supabaseClientOrNull?.auth.currentUser != null);
    if (!hasUser) {
      _msg(t('misc_login_first_publish'));
      return;
    }

    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            GenericAdEditorDialog(isMarket: widget.title == kSectionMarket));
    if (saved == true && mounted) {
      _msg(t('ui_ad_submitted'));
      await _loadFirstPage();
    }
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message, textDirection: appLocale.direction)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    context.dependOnAppStrings();
    final canAdd = widget.showAddAction &&
        (widget.title == kSectionCars || widget.title == kSectionMarket);
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Icon(widget.icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 22),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
              '${sectionTitleOf(widget.title)}${widget.brand == null ? '' : ' · ${widget.brand}'}',
              maxLines: MediaQuery.textScalerOf(context).scale(18) > 24 ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            )),
          ]),
          centerTitle: true,
        ),
        floatingActionButton: canAdd
            ? FloatingActionButton.extended(
                backgroundColor: red,
                onPressed:
                    widget.title == kSectionCars ? addCarAd : addGenericAd,
                icon: const Icon(Icons.add, color: Color(0xFFFFFFFF)),
                label: Text(
                  widget.title == kSectionCars
                      ? t('car_add')
                      : t('market_add_product'),
                  style: const TextStyle(color: Color(0xFFFFFFFF)),
                ),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: refresh,
          child: Builder(
            builder: (context) {
              if (_loading && _items.isEmpty) {
                return AppLoadingView(label: t('ui_loading_title'));
              }
              if (_failed && _items.isEmpty) return _loadError(_loadFirstPage);
              final items = _items;
              if (items.isEmpty) {
                return LayoutBuilder(
                    builder: (context, constraints) => ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                                height: constraints.maxHeight,
                                child: AppStateView(
                                  title: t(widget.title == kSectionMarket
                                      ? 'market_no_ads'
                                      : 'misc_no_ads_now'),
                                  icon: widget.icon,
                                  message: widget.title == kSectionCars
                                      ? t('misc_cars_hub_empty')
                                      : t('misc_publish_ads_all'),
                                ))
                          ],
                        ));
              }
              return LayoutBuilder(builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final columns = ((constraints.maxWidth - 32) /
                        (scaler.scale(13) > 16 ? 260 : 160))
                    .floor()
                    .clamp(1, 3);
                final width =
                    (constraints.maxWidth - 32 - (columns - 1) * 12) / columns;
                return ValueListenableBuilder<bool>(
                  valueListenable: carGridLayoutNotifier,
                  builder: (context, isGrid, _) {
                    final useGrid = widget.title != kSectionCars || isGrid;
                    return CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_loading)
                          const SliverToBoxAdapter(
                              child: LinearProgressIndicator()),
                        if (_failed)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: AppStatePanel(
                                title: t('ui_load_error_title'),
                                message: t('ui_previous_list'),
                                icon: AppIcons.cloudOff,
                                isError: true,
                                actionLabel: t('ui_retry'),
                                onAction: _loadFirstPage,
                              ),
                            ),
                          ),
                        if (useGrid)
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent:
                                    width * .75 + scaler.scale(14) * 7.5 + 24,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  if (widget.title == kSectionCars) {
                                    return CarCard(
                                      key: ValueKey(items[i]['id']),
                                      car: items[i],
                                      square: true,
                                    );
                                  }
                                  return GenericAdCard(
                                    key: ValueKey(items[i]['id']),
                                    item: items[i],
                                    icon: widget.icon,
                                    square: true,
                                  );
                                },
                                childCount: items.length,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: CarCard(
                                    key: ValueKey(items[i]['id']),
                                    car: items[i],
                                  ),
                                ),
                                childCount: items.length,
                              ),
                            ),
                          ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                        if (_moreFailed)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: AppStatePanel(
                                key: const ValueKey('section_more_error'),
                                title: t('ui_load_error_title'),
                                message: t('ui_load_error_body'),
                                icon: AppIcons.cloudOff,
                                isError: true,
                                actionLabel: t('ui_retry'),
                                onAction: () => _fetch(reset: false),
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 90)),
                      ],
                    );
                  },
                );
              });
            },
          ),
        ),
      ),
    );
  }
}

class GenericAdCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final IconData icon;
  final bool square;
  const GenericAdCard(
      {super.key, required this.item, required this.icon, this.square = false});

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();

    final images = marketItemImageUrls(item);
    final title = (item['title'] ??
            item['name'] ??
            item['product_name'] ??
            item['job_title'] ??
            t('misc_default_ad'))
        .toString();
    final description = item['description']?.toString() ?? '';
    final city = (item['city'] ?? item['governorate'])?.toString() ?? '';
    final price = (item['price'] ?? item['salary'])?.toString() ?? '';

    final rawJobType = item['job_type']?.toString().trim() ?? '';
    final jobType =
        (rawJobType.isEmpty || rawJobType == 'null') ? '' : rawJobType;
    if (square) {
      final amount = parseFormDecimal(price);
      return CompactListingCard(
        photo: CarPhoto(urls: images, radius: 0, placeholderIcon: icon),
        title: title,
        titleDirection: contentTextDirection(context, title),
        primaryPrice: price.isEmpty
            ? ''
            : item['price'] != null && amount != null
                ? formatUsd(amount)
                : price,
        metadata: jobType,
        location: city,
        onTap: () => _openDetails(context),
      );
    }
    return GestureDetector(
      onTap: () => _openDetails(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(imgRadius),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.shadow),
        child: Row(
          children: [
            CarPhoto(
                urls: images, width: 82, height: 82, placeholderIcon: icon),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        textDirection: contentTextDirection(context, title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(description,
                          textDirection:
                              contentTextDirection(context, description),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                    if (city.isNotEmpty)
                      Text('📍 $city',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    if (price.isNotEmpty)
                      Text(
                          item['price'] == null ||
                                  parseFormDecimal(price) == null
                              ? price
                              : formatUsd(parseFormDecimal(price)!),
                          style: const TextStyle(
                              color: red, fontWeight: FontWeight.w900)),
                    if (jobType.isNotEmpty)
                      Text('🕐 $jobType',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketItemDetailsPage(item: item, icon: icon),
      ),
    );
  }
}

class _FavoritesBundle {
  final bool signedIn;
  final bool failed;
  final bool backendAuthRequired;
  final List<Map<String, dynamic>> cars;
  final List<Map<String, dynamic>> marketItems;

  const _FavoritesBundle(
    this.signedIn,
    this.cars,
    this.marketItems, {
    this.failed = false,
    this.backendAuthRequired = false,
  });

  bool get isEmpty => cars.isEmpty && marketItems.isEmpty;
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with AccountFeedState<FavoritesPage> {
  @override
  void reloadAccountFeed() {
    future = _startFavoritesLoad();
  }

  late Future<_FavoritesBundle> future;

  @override
  void initState() {
    super.initState();
    future = _startFavoritesLoad();
  }

  Future<_FavoritesBundle> _startFavoritesLoad() async {
    try {
      return await loadFavorites();
    } catch (_) {
      return const _FavoritesBundle(true, [], [], failed: true);
    }
  }

  Future<void> refresh() async {
    final next = _startFavoritesLoad();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder provides retry. */
    }
  }

  Future<_FavoritesBundle> loadFavorites() async {
    final epoch = accountEpoch;
    // Backend JWT is required for favorites (G10.17). Do NOT send Supabase token.
    // If backend session is missing/expired, try restore/refresh first.
    final token = await backendAuthSession.validAccessToken();
    if (!accountMatches(backendAuthSession.user?.id ?? '', epoch)) {
      return const _FavoritesBundle(false, [], []);
    }
    if (token == null || token.isEmpty) {
      // Supabase-only users must not have Supabase token sent and must not be shown "no favorites".
      if (backendAuthSession.user == null &&
          supabase.auth.currentUser != null) {
        return const _FavoritesBundle(false, [], [], backendAuthRequired: true);
      }
      return const _FavoritesBundle(false, [], []);
    }
    final user = backendAuthSession.user;
    if (user == null) {
      if (supabase.auth.currentUser != null) {
        return const _FavoritesBundle(false, [], [], backendAuthRequired: true);
      }
      return const _FavoritesBundle(false, [], []);
    }

    try {
      final response = await backendApi.get('favorites', backendOnly: true);
      if (!accountMatches(user.id, epoch)) {
        return const _FavoritesBundle(false, [], []);
      }
      if (response is! Map || response['data'] is! List) {
        throw StateError('Favorites response is invalid');
      }
      final favs = List<Map<String, dynamic>>.from(response['data'] as List);
      if (favs.isEmpty) return const _FavoritesBundle(true, [], []);

      final carIds = <String>[];
      final marketIds = <String>[];
      for (final row in favs) {
        final type =
            (row['item_type']?.toString() ?? 'car').trim().toLowerCase();
        final carId = row['car_id']?.toString() ?? '';
        final itemId = row['item_id']?.toString() ?? '';
        if (type == 'market' && itemId.isNotEmpty && itemId != 'null') {
          marketIds.add(itemId);
        } else if (carId.isNotEmpty && carId != 'null') {
          carIds.add(carId);
        } else if (itemId.isNotEmpty && itemId != 'null') {
          carIds.add(itemId);
        }
      }

      final carsResponse = carIds.isEmpty
          ? null
          : await backendApi.get(
              'cars/by-ids',
              query: {'ids': carIds.take(100).join(',')},
            );
      if (carsResponse != null &&
          (carsResponse is! Map || carsResponse['data'] is! List)) {
        throw StateError('Favorite cars response is invalid');
      }
      final cars = carsResponse == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              (carsResponse as Map)['data'] as List,
            );
      if (!accountMatches(user.id, epoch)) {
        return const _FavoritesBundle(false, [], []);
      }
      final marketItems = marketIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              (await backendApi.get(
                      'market/items/by-ids?ids=${marketIds.join(",")}'))['data']
                  as List,
            );

      // سمعة وتوثيق كل بائعي الصفحة في طلبين مجمّعين قبل بناء البطاقات،
      // بدل استعلامين لكل بطاقة. المفضلة نفسها محمّلة أصلاً في هذه الدالة.
      if (!accountMatches(user.id, epoch)) {
        return const _FavoritesBundle(false, [], []);
      }
      await trustCache.preloadForRows(cars, withFavorites: false);
      if (!accountMatches(user.id, epoch)) {
        return const _FavoritesBundle(false, [], []);
      }

      // Preload first image of visible cars only (first 6) for smoother scrolling
      int preloaded = 0;
      for (final row in cars) {
        if (preloaded >= 6) break;
        final urls = carImageUrls(row);
        if (urls.isNotEmpty && mounted) {
          smartPrecacheImage(urls.first, context);
          preloaded++;
        }
      }

      return _FavoritesBundle(true, cars, marketItems);
    } on BackendApiException catch (e) {
      if (e.statusCode == 401 ||
          e.statusCode == 403 ||
          e.message == 'Backend authentication required') {
        if (supabase.auth.currentUser != null) {
          return const _FavoritesBundle(false, [], [],
              backendAuthRequired: true);
        }
        return const _FavoritesBundle(false, [], []);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_favorites')), centerTitle: true),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: FutureBuilder<_FavoritesBundle>(
            future: future,
            builder: (context, snapshot) {
              if (backendAuthSession.user == null &&
                  supabase.auth.currentUser == null) {
                return AppStateView(
                  title: t('account_login_to_see_favs'),
                  icon: AppIcons.locked,
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return AppLoadingView(label: t('ui_loading_title'));
              }
              if (snapshot.hasError || snapshot.data?.failed == true) {
                return _loadError(refresh);
              }
              final bundle =
                  snapshot.data ?? const _FavoritesBundle(true, [], []);

              if (bundle.backendAuthRequired) {
                return AppStateView(
                  title: t('login_required_first'),
                  icon: AppIcons.locked,
                  actionLabel: t('alerts_update'),
                  onAction: refresh,
                );
              }
              if (!bundle.signedIn) {
                return AppStateView(
                  title: t('account_login_to_see_favs'),
                  icon: AppIcons.locked,
                );
              }

              if (bundle.isEmpty) {
                return AppStateView(
                  title: t('account_no_saved_ads'),
                  icon: AppIcons.favorite,
                  message: t('ui_favorites_hint'),
                  actionLabel: t('alerts_update'),
                  onAction: refresh,
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final columns = ((constraints.maxWidth - 32) /
                          (scaler.scale(13) > 16 ? 260 : 160))
                      .floor()
                      .clamp(1, 3);
                  final itemWidth =
                      (constraints.maxWidth - 32 - (columns - 1) * 12) /
                          columns;
                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent:
                          itemWidth * .75 + scaler.scale(14) * 7.5 + 24,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: bundle.cars.length + bundle.marketItems.length,
                    itemBuilder: (context, index) {
                      if (index < bundle.cars.length) {
                        return CarCard(
                          key: ValueKey(bundle.cars[index]['id']),
                          car: bundle.cars[index],
                          square: true,
                        );
                      }
                      final item =
                          bundle.marketItems[index - bundle.cars.length];
                      return GenericAdCard(
                        key: ValueKey(item['id']),
                        item: item,
                        icon: AppIcons.market,
                        square: true,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// قائمة الاقتراحات تحت مربع البحث.
///
/// تتبع شكل البطاقات في التطبيق: نفس `panel` ونفس `AppColors.border`، بلا
/// لون أو حجم جديد.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.title,
    required this.onPick,
  });

  final List<SearchSuggestion> suggestions;
  final String title;
  final ValueChanged<SearchSuggestion> onPick;

  IconData _iconFor(SearchFieldKind kind) {
    switch (kind) {
      case SearchFieldKind.brand:
        return AppIcons.cars;
      case SearchFieldKind.model:
        return Icons.car_rental_outlined;
      case SearchFieldKind.year:
        return Icons.calendar_month_outlined;
      case SearchFieldKind.city:
        return AppIcons.location;
      case SearchFieldKind.fuel:
        return Icons.local_gas_station_outlined;
      case SearchFieldKind.transmission:
        return AppIcons.settings;
      case SearchFieldKind.bodyType:
        return Icons.directions_car_filled_outlined;
      case SearchFieldKind.free:
        return AppIcons.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadowSoft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final SearchSuggestion suggestion in suggestions)
            InkWell(
              onTap: () => onPick(suggestion),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Icon(_iconFor(suggestion.kind), size: 19, color: red),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        suggestion.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.north_west_rounded,
                        size: 16, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// رقيمة تصف فلترًا نشطًا، بنمط `FilterChip` الموجود في التطبيق.
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onEdit});
  final String label;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => ActionChip(
        onPressed: onEdit,
        avatar: Icon(AppIcons.filters,
            size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _ClearFiltersButton extends StatelessWidget {
  const _ClearFiltersButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined,
                size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
                child: Text(
              t('search_clear_filters'),
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, this.initialQuery});

  final String? initialQuery;

  static final GlobalKey<SearchTabState> searchKey =
      GlobalKey<SearchTabState>();

  static void setQueryAndSearch(String query) {
    final state = searchKey.currentState;
    if (state != null) {
      state.setQueryAndSearch(query);
    }
  }

  @override
  State<SearchTab> createState() => SearchTabState();
}

class SearchTabState extends State<SearchTab> {
  /// عدد السيارات في كل جلب. زيد إلى 30 لتقليل عدد الطلبات.
  static const int _pageSize = 30;

  /// كم قبل نهاية القائمة يبدأ جلب الصفحة التالية.
  /// قلل إلى 500 لبدء التحميل مبكراً.
  static const double _loadMoreThreshold = 500;

  /// مهلة التوقّف عن الكتابة قبل تنفيذ البحث. ٣٠٠ms تكفي لتمييز الكلمة
  /// المتواصلة وتُبقي عدد الطلبات منخفضًا على شبكة ضعيفة.
  static const Duration _searchDebounce = Duration(milliseconds: 300);

  final controller = TextEditingController();
  final brandFilter = TextEditingController();
  final cityFilter = TextEditingController();
  final fromYear = TextEditingController();
  final toYear = TextEditingController();
  final minPrice = TextEditingController();
  final maxPrice = TextEditingController();
  final ScrollController scroll = ScrollController();
  bool loading = false;
  MarketPriceEstimate? formMarketEstimate;
  bool marketEstimateLoading = false;
  bool marketEstimateFailed = false;
  Timer? marketEstimateDebounce;
  int marketEstimateRequest = 0;
  String sortOrder = 'newest';
  String provinceFilter = '';
  String bodyTypeFilter = '';
  List<Map<String, dynamic>> results = [];

  /// فلاتر متقدمة تُختار من ورقة منبثقة، لا من نص البحث.
  CarSearchFilters advanced = CarSearchFilters();

  /// اقتراحات تحت مربع البحث — تُحسب محليًا بعد أول تحميل للمفردات.
  List<SearchSuggestion> suggestions = <SearchSuggestion>[];

  /// القيم الفعلية في القاعدة: ماركات وموديلات ومدن وأنواع وقود.
  SearchVocabulary? vocabulary;

  Timer? searchDebounce;

  /// يتزايد مع كل طلب: يُهمل ردّ الطلب الذي لم يعد الأحدث.
  int searchRequest = 0;
  bool loadingMore = false;
  bool hasMore = false;
  bool searchFailed = false, moreFailed = false;
  int _nextOffset = 0;
  bool savingAlert = false;

  @override
  void initState() {
    super.initState();
    scroll.addListener(_onScroll);
    final initial = widget.initialQuery;
    if (initial != null && initial.trim().isNotEmpty) {
      controller.text = initial.trim();
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _runSearch(reset: true);
        }
      });
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    scroll
      ..removeListener(_onScroll)
      ..dispose();
    controller.dispose();
    brandFilter.dispose();
    cityFilter.dispose();
    fromYear.dispose();
    toYear.dispose();
    minPrice.dispose();
    maxPrice.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scroll.hasClients ||
        loading ||
        loadingMore ||
        !hasMore ||
        moreFailed ||
        searchFailed) {
      return;
    }
    final position = scroll.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;
    _runSearch(reset: false);
  }

  /// يقرأ المفردات مرة واحدة ثم يعيدها فورًا في كل نداء بعدها.
  Future<SearchVocabulary> _ensureVocabulary() async {
    final SearchVocabulary? cached = vocabulary;
    if (cached != null) return cached;
    final SearchVocabulary loaded = await loadVocabulary(backendApi);
    if (!mounted) return loaded;
    setState(() => vocabulary = loaded);
    return loaded;
  }

  List<SearchSuggestion> _suggestFor(String text) {
    final SearchVocabulary? source = vocabulary;
    if (source == null) return const <SearchSuggestion>[];
    return source.suggest(text);
  }

  /// يحدّث الاقتراحات فورًا ويؤجّل البحث، فالاقتراح محلي والبحث يذهب للقاعدة.
  void _onQueryChanged(String value) {
    setState(() {
      suggestions = _suggestFor(value);
      hasMore = false;
    });
    if (vocabulary == null) {
      unawaited(_ensureVocabulary().then((SearchVocabulary loaded) {
        if (!mounted) return;
        setState(() => suggestions = _suggestFor(controller.text));
      }));
    }
    searchDebounce?.cancel();
    final int token = ++searchRequest;
    searchDebounce = Timer(_searchDebounce, () {
      _runSearch(reset: true, token: token);
    });
  }

  /// يملأ المربع بنص الاقتراح المختار.
  void _applySuggestion(SearchSuggestion suggestion) {
    controller.text = suggestion.replacement;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    setState(() => suggestions = const <SearchSuggestion>[]);
    _runSearch(reset: true);
  }

  Future<void> search() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => suggestions = const <SearchSuggestion>[]);
    _saveSearchQuery(controller.text);
    await _runSearch(reset: true);
  }

  void setQueryAndSearch(String query) {
    controller.text = query;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    _saveSearchQuery(query);
    if (mounted) {
      setState(() {});
    }
    _runSearch(reset: true);
  }

  Future<void> _saveSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_kSearchHistoryKey) ?? [];
    history.removeWhere((h) => h == q);
    history.insert(0, q);
    await prefs.setStringList(_kSearchHistoryKey, history);
  }

  static const String _kSearchHistoryKey = 'search_history';

  /// يبني الاستعلام كاملًا ويجلب صفحة واحدة.
  ///
  /// كل الفلاتر تُنفَّذ داخل PostgREST: لا يُجلب صف ثم يُفلتر في الجهاز.
  Future<void> _runSearch({required bool reset, int? token}) async {
    if (!mounted || (token != null && token != searchRequest)) return;
    if (!reset && (loading || loadingMore || !hasMore || searchFailed)) return;
    // Every replacement invalidates pending manual, debounced and paginated reads.
    final generation = reset ? ++searchRequest : searchRequest;
    if (reset) searchDebounce?.cancel();
    final q = controller.text.trim();
    final hasFilters = [
          brandFilter,
          cityFilter,
          fromYear,
          toYear,
          minPrice,
          maxPrice
        ].any((field) => field.text.trim().isNotEmpty) ||
        provinceFilter.isNotEmpty ||
        bodyTypeFilter.isNotEmpty ||
        advanced.isNotEmpty;
    if (q.isEmpty && !hasFilters) {
      setState(() {
        results = [];
        _nextOffset = 0;
        hasMore = loading = loadingMore = searchFailed = moreFailed = false;
      });
      return;
    }
    if (reset) {
      final quick = CarSearchFilters()
        ..fromYear = fromYear.text
        ..toYear = toYear.text
        ..minPrice = minPrice.text
        ..maxPrice = maxPrice.text;
      final error = quick.numericError ?? advanced.numericError;
      if (error != null) {
        setState(() {
          loading = loadingMore = hasMore = false;
        });
        _searchMessage(t(error));
        return;
      }
    }
    final offset = reset ? 0 : _nextOffset;
    setState(() {
      if (reset) {
        loading = true;
        loadingMore = false;
        results = [];
        _nextOffset = 0;
      } else {
        loadingMore = true;
      }
      searchFailed = moreFailed = false;
    });
    try {
      final rows = await _fetchPage(q, offset);
      if (!mounted || generation != searchRequest) return;
      final ids = <String>{};
      final merged = reset ? rows : [...results, ...rows];
      setState(() {
        results = merged.where((row) {
          final id = row['id']?.toString();
          return id == null || ids.add(id);
        }).toList();
        _nextOffset = offset + rows.length;
        hasMore = rows.length == _pageSize;
        loading = loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != searchRequest) return;
      setState(() {
        loading = loadingMore = false;
        if (reset) {
          searchFailed = true;
        } else {
          moreFailed = true;
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(String q, int offset) async {
    final filters = <Map<String, dynamic>>[];

    final String brand = brandFilter.text.trim();
    final String city = cityFilter.text.trim();
    final num? lowYear = parseFormInteger(fromYear.text);
    final num? highYear = parseFormInteger(toYear.text);
    final num? lowPrice = parseFormDecimal(minPrice.text);
    final num? highPrice = parseFormDecimal(maxPrice.text);

    if (brand.isNotEmpty) {
      filters
          .add({'column': 'brand', 'operator': 'ilike', 'value': '%$brand%'});
    }
    if (city.isNotEmpty) {
      filters.add({'column': 'city', 'operator': 'ilike', 'value': '%$city%'});
    }
    if (provinceFilter.isNotEmpty) {
      filters.add({
        'column': 'province',
        'operator': 'eq',
        'value': provinceFilter,
      });
    }
    if (bodyTypeFilter.isNotEmpty) {
      filters.add({
        'column': 'body_type',
        'operator': 'eq',
        'value': bodyTypeFilter,
      });
    }
    if (lowYear != null) {
      filters.add({'column': 'year', 'operator': 'gte', 'value': '$lowYear'});
    }
    if (highYear != null) {
      filters.add({'column': 'year', 'operator': 'lte', 'value': '$highYear'});
    }
    if (lowPrice != null) {
      filters.add({'column': 'price', 'operator': 'gte', 'value': '$lowPrice'});
    }
    if (highPrice != null) {
      filters
          .add({'column': 'price', 'operator': 'lte', 'value': '$highPrice'});
    }

    // البحث الذكي: «نيسان 2022» يصبح شرطين يُدمجان بـAND، لا `or` واحدًا كان
    // سيجعل «نيسان **أو** 2022» فيظهر كل نيسان.
    filters.addAll(SmartQuery.parse(q).steps.map(_searchStepPayload));

    // الفلاتر المتقدمة من ورقة الفلترة.
    final FilterPlan plan = advanced.plan;
    filters.addAll(plan.steps.map(_searchStepPayload));
    if (plan.lowYear != null) {
      filters.add({
        'column': kCarColYear,
        'operator': 'gte',
        'value': '${plan.lowYear}',
      });
    }
    if (plan.highYear != null) {
      filters.add({
        'column': kCarColYear,
        'operator': 'lte',
        'value': '${plan.highYear}',
      });
    }
    if (plan.lowPrice != null) {
      filters.add({
        'column': kCarColPrice,
        'operator': 'gte',
        'value': '${plan.lowPrice}',
      });
    }
    if (plan.highPrice != null) {
      filters.add({
        'column': kCarColPrice,
        'operator': 'lte',
        'value': '${plan.highPrice}',
      });
    }
    if (plan.maxMileage != null) {
      filters.add({
        'column': kCarColMileage,
        'operator': 'lte',
        'value': '${plan.maxMileage}',
      });
    }

    final response = await backendApi.get(
      'cars/search',
      query: {
        'filters': jsonEncode(filters),
        'sort': sortOrder == 'low'
            ? 'price_asc'
            : sortOrder == 'high'
                ? 'price_desc'
                : 'created_desc',
        'limit': '$_pageSize',
        'offset': '$offset',
      },
    );
    if (response is! Map || response['data'] is! List) {
      throw StateError('Car search response is invalid');
    }
    final rows = List<Map<String, dynamic>>.from(response['data'] as List);
    // بائعو نتائج البحث في طلبين مجمّعين قبل بناء البطاقات، بدل استعلامين لكل
    // بطاقة (والمفضلة معطّلة: البحث يجلبها TrustCache عند أول بطاقة تسأل عنها).
    await trustCache.preloadForRows(rows);

    // Preload first image of visible cars only (first 6) for smoother scrolling
    int preloaded = 0;
    for (final row in rows) {
      if (preloaded >= 6) break;
      final urls = carImageUrls(row);
      if (urls.isNotEmpty && mounted) {
        smartPrecacheImage(urls.first, context);
        preloaded++;
      }
    }

    return rows;
  }

  static Map<String, dynamic> _searchStepPayload(QueryStep step) {
    Map<String, dynamic> parseClause(String clause) {
      final firstDot = clause.indexOf('.');
      final secondDot = clause.indexOf('.', firstDot + 1);
      if (firstDot <= 0 || secondDot <= firstDot + 1) {
        throw const FormatException('Invalid search clause');
      }
      return {
        'column': clause.substring(0, firstDot),
        'operator': clause.substring(firstDot + 1, secondDot),
        'value': clause.substring(secondDot + 1),
      };
    }

    return step.isGroup
        ? {'clauses': step.clauses!.map(parseClause).toList()}
        : {
            'column': step.column,
            'operator': step.operator,
            'value': step.value,
          };
  }

  /// يمسح نص البحث وكل الفلاتر — زر «إزالة الفلاتر» في حالة لا نتائج.
  void _resetEverything() {
    controller.clear();
    brandFilter.clear();
    cityFilter.clear();
    fromYear.clear();
    toYear.clear();
    minPrice.clear();
    maxPrice.clear();
    advanced.clear();
    setState(() {
      provinceFilter = '';
      bodyTypeFilter = '';
      suggestions = const <SearchSuggestion>[];
    });
    _runSearch(reset: true);
  }

  Future<void> saveSearchAlert() async {
    if (savingAlert) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      _searchMessage(t('alerts_login_first'));
      return;
    }
    final criteria = savedSearchCriteria(
      query: controller.text,
      quick: CarSearchFilters()
        ..brand = brandFilter.text
        ..city = cityFilter.text
        ..province = provinceFilter
        ..bodyType = bodyTypeFilter
        ..fromYear = fromYear.text
        ..toYear = toYear.text
        ..minPrice = minPrice.text
        ..maxPrice = maxPrice.text,
      advanced: advanced,
    );
    if (criteria.error != null) {
      _searchMessage(t(criteria.error!));
      return;
    }
    final payload = <String, dynamic>{'user_id': user.id, ...criteria.payload!};
    setState(() {
      savingAlert = true;
    });
    try {
      final response = await backendApi.post(
        'activity/saved-searches',
        body: payload,
      );
      final created = response is Map ? response['data'] : null;
      if (created is! Map || (created['id']?.toString().isEmpty ?? true)) {
        throw StateError('Alert was not acknowledged');
      }
      _searchMessage(t('alerts_saved'));
    } catch (_) {
      _searchMessage(t('ui_alert_save_failed'));
    } finally {
      if (mounted) {
        setState(() {
          savingAlert = false;
        });
      }
    }
  }

  void _searchMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message, textDirection: appLocale.direction)));
  }

  /// ورقة الفلاتر المتقدمة.
  ///
  /// تعمل على **مسوّدة** من الفلاتر ولا تلمس الفلاتر النشطة إلا عند «تطبيق»،
  /// فالإلغاء لا يترك التطبيق في حالة نصف معدَّلة. الورقة ترث اتجاه الواجهة
  /// ولا تفرض اتجاهًا — لأن الإنجليزية LTR.
  bool _filterSheetOpen = false;

  Future<void> _openFilterSheet() async {
    if (_filterSheetOpen) return;
    _filterSheetOpen = true;
    try {
      // Open immediately using fallbacks; vocabulary can load in the background.
      final source = vocabulary;
      final result = await showModalBottomSheet<CarSearchFilters>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SearchFiltersSheet(
          initial: advanced,
          provinces: iraqiProvinces,
          bodyTypes: vehicleBodyTypes,
          fuels: mergedOptions(source?.fuels, searchFuelFallbacks),
          transmissions:
              mergedOptions(source?.transmissions, searchTransmissionFallbacks),
        ),
      );
      if (!mounted || result == null) return;
      setState(() => advanced = result);
      unawaited(_runSearch(reset: true));
    } finally {
      _filterSheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final searchHasInput = controller.text.trim().isNotEmpty ||
        [brandFilter, cityFilter, fromYear, toYear, minPrice, maxPrice]
            .any((field) => field.text.trim().isNotEmpty) ||
        provinceFilter.isNotEmpty ||
        bodyTypeFilter.isNotEmpty ||
        advanced.isNotEmpty;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
      children: [
        Row(key: const ValueKey('search_discovery_header'), children: [
          Expanded(
              child: Text(t('search'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800))),
          IconButton(
              tooltip: t('alerts_save'),
              onPressed: savingAlert ? null : saveSearchAlert,
              icon: const Icon(AppIcons.notifications)),
        ]),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                textDirection: appLocale.direction,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  hintText: t('search_hint_example'),
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: IconButton(
                      onPressed: loading ? null : search,
                      tooltip: t('search'),
                      icon: Icon(Icons.arrow_forward_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer)),
                  filled: true,
                  fillColor: panel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              height: 56,
              child: IconButton.filledTonal(
                tooltip: t('search_filters_title'),
                onPressed: _openFilterSheet,
                icon: Badge(
                    isLabelVisible: advanced.isNotEmpty,
                    child: const Icon(AppIcons.filters)),
              ),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SuggestionPanel(
            suggestions: suggestions,
            title: t('search_suggestions'),
            onPick: _applySuggestion,
          ),
        ],
        if (advanced.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String label in advanced.activeLabels)
                _ActiveFilterChip(label: label, onEdit: _openFilterSheet),
              _ClearFiltersButton(onTap: _resetEverything),
            ],
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('search-sort:$sortOrder'),
          initialValue: sortOrder,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: t('search_order'),
            filled: true,
            fillColor: panel,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
          ),
          items: [
            DropdownMenuItem(value: 'newest', child: Text(t('search_newest'))),
            DropdownMenuItem(value: 'low', child: Text(t('search_price_asc'))),
            DropdownMenuItem(
                value: 'high', child: Text(t('search_price_desc'))),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => sortOrder = value);
            if (searchHasInput || results.isNotEmpty) {
              search();
            }
          },
        ),
        const SizedBox(height: 20),
        if (!searchHasInput && results.isEmpty)
          AppStatePanel(
              icon: AppIcons.cars,
              title: t('ui_search_start'),
              message: t('search_hint'),
              actionLabel: t('search_filters_title'),
              onAction: _openFilterSheet),
        if (loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator())),
        if (!loading && searchFailed)
          AppStatePanel(
            key: const ValueKey('search_error'),
            icon: AppIcons.cloudOff,
            title: t('search_failed'),
            message: t('ui_load_error_body'),
            isError: true,
            actionLabel: t('ui_retry'),
            onAction: search,
          ),
        if (!loading && !searchFailed && results.isEmpty && searchHasInput)
          Column(
            children: [
              AppStatePanel(
                  icon: Icons.search_off_rounded,
                  title: t('search_no_matches'),
                  message: t('search_try_other')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _resetEverything,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text(t('search_clear_filters')),
              ),
            ],
          ),
        if (results.isNotEmpty) ...[
          Text('${t('search_results')} (${results.length})',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            itemBuilder: (context, i) {
              return CarCard(key: ValueKey(results[i]['id']), car: results[i]);
            },
          ),
          if (moreFailed)
            AppStatePanel(
              key: const ValueKey('search_more_error'),
              icon: AppIcons.cloudOff,
              title: t('ui_search_more_failed'),
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: () => _runSearch(reset: false),
            ),
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                  child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5))),
            ),
        ],
      ],
    );
  }
}

class AddCarTab extends StatefulWidget {
  const AddCarTab({super.key, this.imagePicker});
  final Future<List<XFile>> Function()? imagePicker;
  @override
  State<AddCarTab> createState() => _AddCarTabState();
}

class _AddCarTabState extends State<AddCarTab> {
  final _formKey = GlobalKey<FormState>();
  final _formScroll = ScrollController();
  final brand = TextEditingController();
  final model = TextEditingController();
  final year = TextEditingController();
  final price = TextEditingController();
  final city = TextEditingController();
  final sellerPhone = TextEditingController();
  final description = TextEditingController();
  String province = '';
  String bodyType = '';
  final picker = ImagePicker();
  final List<XFile> selectedImages = [];
  final List<Uint8List> selectedImageBytes = [];
  bool loading = false;
  bool _attemptedSubmit = false;
  bool _picking = false;
  String _submissionId = newSubmissionId();
  String? _submissionOwner, _submitError, _submitErrorCode;
  int _uploadedCount = 0, _uploadTotal = 0;
  final _uploadedUrls = <XFile, String>{};
  final _photoIds = <XFile, String>{};
  final _plateRegions = <XFile, List<Map<String, dynamic>>?>{};
  bool get _busy => loading || _picking;

  MarketPriceEstimate? formMarketEstimate;
  bool marketEstimateLoading = false;
  bool marketEstimateFailed = false;
  Timer? marketEstimateDebounce;
  int marketEstimateRequest = 0;

  void _scheduleMarketEstimate() {
    marketEstimateDebounce?.cancel();
    final request = ++marketEstimateRequest;
    final brandValue = brand.text.trim();
    final modelValue = model.text.trim();
    final yearValue = parseFormInteger(year.text);
    if (brandValue.isEmpty || modelValue.isEmpty || yearValue == null) {
      setState(() {
        formMarketEstimate = null;
        marketEstimateLoading = false;
        marketEstimateFailed = false;
      });
      return;
    }
    setState(() {
      marketEstimateLoading = true;
      marketEstimateFailed = false;
    });
    marketEstimateDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final estimate = await _loadFormMarketEstimate(
          brandValue,
          modelValue,
          yearValue,
          province,
        );
        if (!mounted || request != marketEstimateRequest) return;
        setState(() {
          formMarketEstimate = estimate;
          marketEstimateLoading = false;
        });
      } catch (_) {
        if (!mounted || request != marketEstimateRequest) return;
        setState(() {
          marketEstimateFailed = true;
          marketEstimateLoading = false;
        });
      }
    });
  }

  Future<MarketPriceEstimate?> _loadFormMarketEstimate(
    String brandValue,
    String modelValue,
    int yearValue,
    String provinceValue,
  ) async {
    final response = await backendApi.get(
      'cars/search',
      query: {
        'filters': jsonEncode([
          {'column': 'brand', 'operator': 'eq', 'value': brandValue},
          {'column': 'model', 'operator': 'eq', 'value': modelValue},
          {'column': 'year', 'operator': 'eq', 'value': '$yearValue'},
        ]),
        'limit': '100',
      },
    );
    if (response is! Map || response['data'] is! List) {
      throw StateError('Comparable cars response is invalid');
    }
    final rows = List<Map<String, dynamic>>.from(response['data'] as List);
    final comparable = List<Map<String, dynamic>>.from(rows)
        .map(
          (row) => MapEntry(
            row,
            double.tryParse(
              (row['price'] ?? '').toString().replaceAll(',', ''),
            ),
          ),
        )
        .where((entry) => entry.value != null && entry.value! > 0)
        .toList();
    final localCars = provinceValue.isEmpty
        ? <MapEntry<Map<String, dynamic>, double>>[]
        : comparable
            .where(
              (entry) =>
                  entry.key['province']?.toString().trim() == provinceValue,
            )
            .toList();
    final useLocal = localCars.length >= 3;
    final sample = useLocal ? localCars : comparable;
    if (sample.length < 3) return null;
    final prices = sample.map((entry) => entry.value!).toList()..sort();
    final middle = prices.length ~/ 2;
    final median = prices.length.isOdd
        ? prices[middle]
        : (prices[middle - 1] + prices[middle]) / 2;
    return MarketPriceEstimate(
      medianPrice: median,
      sampleCount: sample.length,
      local: useLocal,
    );
  }

  Widget _buildMarketPriceGuide() {
    final estimate = formMarketEstimate;
    final askingPrice = parseFormDecimal(price.text);
    final difference = estimate == null || askingPrice == null
        ? 0.0
        : (askingPrice - estimate.medianPrice) / estimate.medianPrice;
    final Color statusColor;
    final String status;
    if (estimate == null || askingPrice == null) {
      statusColor = AppColors.textStrong;
      status = t('compare_price_input');
    } else if (difference < -0.10) {
      statusColor = const Color(0xFF66D19E);
      status = t('compare_price_lower');
    } else if (difference > 0.10) {
      statusColor = Colors.amber;
      status = t('compare_price_higher');
    } else {
      statusColor = const Color(0xFF66D19E);
      status = t('compare_price_similar');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('compare_market_price'),
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                if (marketEstimateLoading)
                  Text(
                    t('compare_comparing'),
                    style: TextStyle(color: AppColors.textMuted),
                  )
                else if (marketEstimateFailed)
                  Text(
                    t('compare_loading'),
                    style: TextStyle(color: Colors.amber),
                  )
                else if (estimate == null &&
                    brand.text.trim().isNotEmpty &&
                    model.text.trim().isNotEmpty &&
                    parseFormInteger(year.text) != null)
                  Text(
                    t('compare_need_3'),
                    style: TextStyle(color: AppColors.textMuted),
                  )
                else
                  Text(status, style: TextStyle(color: statusColor)),
                if (!marketEstimateLoading && estimate != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'السعر الوسطي التقريبي: ${estimate.medianPrice.toStringAsFixed(0)} دولار · ${estimate.sampleCount} إعلانات${estimate.local ? ' من نفس المحافظة' : ''}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (marketEstimateFailed)
            IconButton(
              tooltip: t('common_retry'),
              onPressed: _scheduleMarketEstimate,
              icon: const Icon(Icons.refresh_rounded),
            )
          else if (marketEstimateLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _formScroll.dispose();
    brand.dispose();
    model.dispose();
    year.dispose();
    price.dispose();
    city.dispose();
    sellerPhone.dispose();
    description.dispose();
    marketEstimateDebounce?.cancel();
    super.dispose();
  }

  Future<void> pickImages() async {
    if (_busy) return;
    if (selectedImages.length >= 15) {
      _msg(t('img_reached_max_15'));
      return;
    }
    setState(() => _picking = true);
    try {
      final picked = await (widget.imagePicker?.call() ??
          picker.pickMultiImage(
            imageQuality: 82,
            maxWidth: 1600,
            maxHeight: 1600,
          ));
      if (!mounted || picked.isEmpty) return;
      final remaining = 15 - selectedImages.length;
      final chosen = picked.take(remaining).toList();
      // Read the whole selection before adding it: a failed file cannot leave
      // the photo and byte lists out of sync.
      final bytes = <Uint8List>[];
      for (final image in chosen) {
        final data = await image.readAsBytes();
        final codec = await ui.instantiateImageCodec(data, targetWidth: 32);
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
        bytes.add(data);
      }
      if (!mounted) return;
      setState(() {
        selectedImages.addAll(chosen);
        selectedImageBytes.addAll(bytes);
      });
      if (picked.length > remaining) _msg(t('img_only_15_added'));
    } catch (_) {
      _msg(t('ui_pick_images_failed'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void removeImage(int index) {
    if (_busy || index < 0 || index >= selectedImages.length) return;
    final image = selectedImages[index];
    setState(() {
      selectedImages.removeAt(index);
      selectedImageBytes.removeAt(index);
      _uploadedUrls.remove(image);
      _photoIds.remove(image);
      _plateRegions.remove(image);
    });
  }

  Future<void> detectCity() async {
    if (_busy) return;
    try {
      setState(() => loading = true);
      _msg(t('settings_locating'));
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) throw Exception('location');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('permission');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&zoom=10&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'Accept-Language': 'ar', 'User-Agent': 'MOTRI-IQ/1.0'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('reverse');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};
      final detected = (address['city'] ??
              address['town'] ??
              address['municipality'] ??
              address['county'] ??
              address['state'])
          ?.toString();
      if (detected == null || detected.trim().isEmpty) throw Exception('city');
      if (!mounted) return;
      city.text = detected.trim();
      _msg(t('ui_car_city_found').replaceAll('{city}', city.text));
    } catch (_) {
      _msg(t('settings_location_denied'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _clearDraft() {
    _formKey.currentState?.reset();
    for (final controller in [
      brand,
      model,
      year,
      price,
      city,
      sellerPhone,
      description,
    ]) {
      controller.clear();
    }
    province = '';
    bodyType = '';
    selectedImages.clear();
    selectedImageBytes.clear();
    _uploadedUrls.clear();
    _photoIds.clear();
    _plateRegions.clear();
    _submissionId = newSubmissionId();
    _attemptedSubmit = false;
    _submissionOwner = null;
    _submitError = null;
    _submitErrorCode = null;
    _uploadedCount = _uploadTotal = 0;
    marketEstimateDebounce?.cancel();
    ++marketEstimateRequest;
    formMarketEstimate = null;
    marketEstimateLoading = marketEstimateFailed = false;
  }

  void _revealSubmitFeedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _formScroll.hasClients) {
        _formScroll.jumpTo(_formScroll.position.maxScrollExtent);
      }
    });
  }

  void _showSubmitError(String key) {
    setState(() {
      _submitError = key;
      _submitErrorCode = null;
    });
    _revealSubmitFeedback();
  }

  Future<void> saveCar() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final userId = _authenticatedUserId;
    if (userId == null) {
      _showSubmitError('login_required_first');
      return;
    }
    if (_submissionOwner != null && _submissionOwner != userId) {
      _showSubmitError('ui_car_session_changed');
      return;
    }
    final yearValue = parseFormInteger(year.text);
    final priceValue = parseFormDecimal(price.text);
    setState(() => _attemptedSubmit = true);
    final visibleFieldsValid = _formKey.currentState?.validate() ?? false;
    final draftValid = brand.text.trim().isNotEmpty &&
        model.text.trim().isNotEmpty &&
        (year.text.trim().isEmpty ||
            yearValue != null &&
                yearValue >= 1900 &&
                yearValue <= DateTime.now().year + 1) &&
        (price.text.trim().isEmpty || priceValue != null && priceValue >= 0) &&
        sellerPhone.text.trim().isNotEmpty;
    if (!visibleFieldsValid || !draftValid) {
      _showSubmitError('ui_car_check_fields');
      return;
    }
    if (selectedImages.isEmpty ||
        selectedImages.length != selectedImageBytes.length) {
      _showSubmitError('car_min_image');
      return;
    }
    final images = List<XFile>.of(selectedImages);
    final bytes = selectedImageBytes.map(Uint8List.fromList).toList();
    final payload = <String, dynamic>{
      'id': _submissionId,
      'user_id': userId,
      'is_approved': true,
      'title': '${brand.text.trim()} ${model.text.trim()}',
      'brand': brand.text.trim(),
      'model': model.text.trim(),
      'year': yearValue,
      'price': priceValue,
      'city': city.text.trim().isEmpty ? null : city.text.trim(),
      'governorate': province.isNotEmpty
          ? province
          : city.text.trim().isEmpty
              ? null
              : city.text.trim(),
      'province': province.isEmpty ? null : province,
      'body_type': bodyType.isEmpty ? null : bodyType,
      'phone': sellerPhone.text.trim(),
      'seller_phone': sellerPhone.text.trim(),
      'description':
          description.text.trim().isEmpty ? null : description.text.trim(),
    };
    _submissionOwner = userId;
    setState(() {
      loading = true;
      _submitError = null;
      _submitErrorCode = null;
      _uploadTotal = images.length;
      _uploadedCount = 0;
    });
    var uploadingMedia = true;
    void checkSession() {
      if (!mounted || _authenticatedUserId != userId) {
        throw StateError('Draft session changed');
      }
    }

    try {
      final urls = <String>[];
      final regions = <List<Map<String, dynamic>>?>[];
      for (var i = 0; i < images.length; i++) {
        checkSession();
        final image = images[i];
        if (!_uploadedUrls.containsKey(image)) {
          final ext = image.name.split('.').last.toLowerCase();
          final safeExt =
              ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
          final photoId = _photoIds.putIfAbsent(image, newSubmissionId);
          final reserveResponse = await backendApi.post(
            'cars/uploads/reserve',
            body: {
              'submission_id': _submissionId,
              'photo_id': photoId,
              'extension': safeExt,
            },
            backendOnly: true,
          );
          final reserved =
              reserveResponse is Map ? reserveResponse['data'] : null;
          final objectKey =
              reserved is Map ? reserved['object_key']?.toString() : null;
          if (objectKey == null || objectKey.isEmpty) {
            throw StateError('Reservation response missing object key');
          }
          final contentType = safeExt == 'jpg' || safeExt == 'jpeg'
              ? 'image/jpeg'
              : 'image/$safeExt';
          final uploadResponse = await backendApi.putBytes(
            'storage/object',
            body: bytes[i],
            contentType: contentType,
            query: {'bucket': 'cars', 'path': objectKey},
            backendOnly: true,
          );
          final uploaded =
              uploadResponse is Map ? uploadResponse['data'] : null;
          if (uploaded is! Map) {
            throw StateError('Upload response missing data');
          }
          // Canonical persistence: store object key (reserve/upload key). Never bind arbitrary public URLs.
          _uploadedUrls[image] = objectKey;
          _plateRegions[image] = await _detectAndCachePlates(bytes[i]);
        }
        checkSession();
        urls.add(_uploadedUrls[image]!);
        regions.add(_plateRegions[image]);
        setState(() => _uploadedCount = i + 1);
      }
      checkSession();
      setState(() => _uploadTotal = 0);
      payload['image_url'] = jsonEncode(urls);
      payload['plate_regions'] = jsonEncode(regions);
      uploadingMedia = false;
      final response = await backendApi.post('cars', body: payload);
      checkSession();
      final created = response is Map ? response['data'] : null;
      if (created is! Map || created['id']?.toString() != payload['id']) {
        throw StateError('Listing acknowledgement missing');
      }
      setState(_clearDraft);
      _msg(t('ui_ad_submitted'));
    } on StorageException catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'ui_car_upload_failed';
          _submitErrorCode = null;
        });
      }
    } on BackendApiException catch (error) {
      debugPrint(
        'saveCar insert failed: ${error.statusCode ?? 'unknown status'}',
      );
      if (mounted) {
        setState(() {
          final sessionChanged = _authenticatedUserId != userId;
          _submitErrorCode =
              uploadingMedia ? null : error.statusCode?.toString();
          _submitError = sessionChanged
              ? 'ui_car_session_changed'
              : uploadingMedia
                  ? 'ui_car_upload_failed'
                  : 'ui_ad_publish_failed';
        });
      }
    } catch (error) {
      debugPrint('saveCar submission failed: ${error.runtimeType}');
      if (mounted) {
        setState(
          () {
            _submitErrorCode = null;
            _submitError = _authenticatedUserId != userId
                ? 'ui_car_session_changed'
                : 'ui_ad_publish_failed';
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (_submitError != null) {
          _revealSubmitFeedback();
        }
      }
    }
  }

  /// يكتشف لوحة السيارة في بكسلات الصورة ويخزن النتيجة مؤقتاً.
  Future<List<Map<String, dynamic>>?> _detectAndCachePlates(
    Uint8List bytes,
  ) async {
    try {
      final regions = detectLicensePlates(bytes);
      if (regions.isEmpty) return null;
      return regions.map((r) => r.toJson()).toList();
    } catch (_) {
      return null;
    }
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: appLocale.direction),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            t('car_add'),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
        ),
        body: PopScope(
          canPop: !loading,
          child: Form(
            key: _formKey,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  controller: _formScroll,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
                  children: [
                    Text(
                      t('car_images'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      t('car_add_1_15'),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedImages.isEmpty)
                      Semantics(
                        button: true,
                        enabled: !_busy,
                        label: t('car_add_images'),
                        onTap: _busy ? null : pickImages,
                        excludeSemantics: true,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          onTap: _busy ? null : pickImages,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 160),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                              boxShadow: AppColors.shadow,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 42,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                                SizedBox(height: 9),
                                Text(t('car_add_images')),
                                SizedBox(height: 4),
                                Text(
                                  t('car_pick_15'),
                                  style: TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      GestureDetector(
                        onTap: _busy ? null : () => _showPreview(0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(imgRadius),
                          child: Stack(
                            children: [
                              AspectRatio(
                                aspectRatio: carPhotoAspect,
                                child: Image.memory(
                                  selectedImageBytes[0],
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    t('common_main_image'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '1 / ${selectedImages.length}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 82,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedImages.length +
                              (selectedImages.length < 15 ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            if (i == selectedImages.length) {
                              return Semantics(
                                button: true,
                                enabled: !_busy,
                                label: t('ui_add_photos'),
                                onTap: _busy ? null : pickImages,
                                excludeSemantics: true,
                                child: GestureDetector(
                                  excludeFromSemantics: true,
                                  onTap: _busy ? null : pickImages,
                                  child: Container(
                                    width: 82,
                                    decoration: BoxDecoration(
                                      color: panel,
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                      ),
                                      boxShadow: AppColors.shadowSoft,
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return GestureDetector(
                              onTap: _busy ? null : () => _showPreview(i),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      imgRadius,
                                    ),
                                    child: Image.memory(
                                      selectedImageBytes[i],
                                      width: 82,
                                      height: 82,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: IconButton(
                                      tooltip: t('common_delete'),
                                      onPressed:
                                          _busy ? null : () => removeImage(i),
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(44, 44),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                      icon: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _carSectionHeading(
                      title: t('ui_vehicle_details'),
                      icon: AppIcons.cars,
                    ),
                    _field(
                      brand,
                      t('field_brand'),
                      onChanged: (_) => _scheduleMarketEstimate(),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      model,
                      t('field_model'),
                      onChanged: (_) => _scheduleMarketEstimate(),
                    ),
                    const SizedBox(height: 12),
                    ResponsiveFormPair(
                      first: _field(
                        year,
                        t('field_year'),
                        keyboard: TextInputType.number,
                        onChanged: (_) => _scheduleMarketEstimate(),
                      ),
                      second: _field(
                        price,
                        t('req_price_in_usd'),
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildMarketPriceGuide(),
                    _carSectionHeading(
                      title: t('ui_location_contact'),
                      icon: AppIcons.location,
                    ),
                    _field(
                      city,
                      t('field_city'),
                      trailingAction: IconButton(
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(48),
                        ),
                        onPressed: _busy ? null : detectCity,
                        icon: Icon(
                          Icons.my_location_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        tooltip: t('settings_location'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ResponsiveFormPair(
                      first: _publishDropdown(
                        t('field_province'),
                        province,
                        iraqiProvinces,
                        (value) {
                          setState(() => province = value);
                          _scheduleMarketEstimate();
                        },
                      ),
                      second: _publishDropdown(
                        t('car_type'),
                        bodyType,
                        vehicleBodyTypes,
                        (value) => setState(() => bodyType = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      sellerPhone,
                      t('field_phone_or_wa'),
                      keyboard: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    _carSectionHeading(
                      title: t('field_extra_details'),
                      icon: Icons.notes_rounded,
                    ),
                    _field(description, t('field_desc'), maxLines: 4),
                    const SizedBox(height: 20),
                    if (_submitError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            '${t(_submitError!)}'
                            '${_submitErrorCode == null ? '' : '\n${t('ui_backend_error_code')}: $_submitErrorCode'}',
                            key: const ValueKey('car_submit_error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (_submitError == 'ui_car_session_changed')
                      TextButton(
                        onPressed: _busy ? null : () => setState(_clearDraft),
                        child: Text(t('ui_car_start_new')),
                      ),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _uploadTotal > 0
                                ? t('ui_car_upload_progress')
                                    .replaceAll('{count}', '$_uploadedCount')
                                    .replaceAll('{total}', '$_uploadTotal')
                                : t('misc_send_ad'),
                            key: const ValueKey('car_submission_progress'),
                          ),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 54),
                      child: FilledButton(
                        onPressed: _busy ? null : saveCar,
                        style: FilledButton.styleFrom(
                          backgroundColor: red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: loading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                t('misc_publish_ad'),
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPreview(int start) {
    final photos = List<Uint8List>.of(selectedImageBytes);
    if (_busy || photos.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: appLocale.direction,
        child: PhotoGallery(
          count: photos.length,
          initialIndex: start,
          hint: t('car_swipe'),
          resetZoomLabel: t('ui_reset_zoom'),
          itemBuilder: (_, index) =>
              Image.memory(photos[index], fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _carFieldLabel(String label, Widget field, {Widget? action}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .72),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          if (action == null)
            Semantics(label: label, child: field)
          else
            Row(
              children: [
                Expanded(
                  child: Semantics(label: label, child: field),
                ),
                const SizedBox(width: 4),
                action,
              ],
            ),
        ],
      );

  InputDecoration _carFieldDecoration() {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: scheme.onSurface.withValues(alpha: .045),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  Widget _carSectionHeading({required String title, required IconData icon}) =>
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 16),
        child: Semantics(
          header: true,
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .65),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    Widget? trailingAction,
  }) {
    Widget input(TextDirection direction) => _carFieldLabel(
          label,
          TextFormField(
            controller: controller,
            enabled: !_busy,
            key: ValueKey(
              controller == brand
                  ? 'car_brand'
                  : controller == model
                      ? 'car_model'
                      : controller == year
                          ? 'car_year'
                          : controller == price
                              ? 'car_price'
                              : controller == city
                                  ? 'car_city'
                                  : controller == sellerPhone
                                      ? 'car_phone'
                                      : 'car_description',
            ),
            keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
            maxLines: maxLines,
            onChanged: onChanged,
            textDirection: direction,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
            textInputAction:
                maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            autovalidateMode: _attemptedSubmit
                ? AutovalidateMode.always
                : AutovalidateMode.onUserInteraction,
            validator: (value) {
              final raw = value?.trim() ?? '';
              if ((controller == brand ||
                      controller == model ||
                      controller == sellerPhone) &&
                  raw.isEmpty) {
                return t('wanted');
              }
              if (controller == year && raw.isNotEmpty) {
                final parsed = parseFormInteger(raw);
                if (parsed == null ||
                    parsed < 1900 ||
                    parsed > DateTime.now().year + 1) {
                  return t('ui_invalid_year')
                      .replaceAll('{year}', '${DateTime.now().year + 1}');
                }
              }
              if (controller == price && raw.isNotEmpty) {
                final parsed = parseFormDecimal(raw);
                if (parsed == null || parsed < 0) return t('ui_invalid_price');
              }
              return null;
            },
            decoration: _carFieldDecoration(),
          ),
          action: trailingAction,
        );
    if (keyboard.index == TextInputType.number.index ||
        keyboard.index == TextInputType.phone.index) {
      return input(TextDirection.ltr);
    }
    return ContentDirectionBuilder(
      controller: controller,
      builder: (context, direction) => input(direction),
    );
  }

  Widget _publishDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return _carFieldLabel(
      label,
      DropdownButtonFormField<String>(
        key: ValueKey('publish:$label:$value'),
        initialValue: value,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        decoration: _carFieldDecoration(),
        items: [
          DropdownMenuItem(value: '', child: Text(t('common_optional'))),
          ...{
            ...options.where((v) => v.isNotEmpty),
            if (value.isNotEmpty) value,
          }.map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: _busy ? null : (selected) => onChanged(selected ?? ''),
      ),
    );
  }
}

class MyAdsPage extends StatefulWidget {
  const MyAdsPage({super.key});

  @override
  State<MyAdsPage> createState() => _MyAdsPageState();
}

class _MyAdsPageState extends State<MyAdsPage>
    with AccountFeedState<MyAdsPage> {
  late Future<List<Map<String, dynamic>>> ads;

  @override
  void initState() {
    super.initState();
    ads = loadAds();
  }

  @override
  void reloadAccountFeed() {
    _mutating = false;
    ads = loadAds();
  }

  Future<List<Map<String, dynamic>>> loadAds() async {
    final user = backendAuthSession.user;
    if (user == null) return [];
    final epoch = accountEpoch;
    try {
      final response = await backendApi.get('cars/my');
      if (!accountMatches(user.id, epoch)) return [];
      if (response is! Map || response['data'] is! List) {
        throw StateError('My cars response is invalid');
      }
      return List<Map<String, dynamic>>.from(response['data'] as List);
    } on BackendApiException catch (e) {
      if (mounted && accountMatches(user.id, epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل الإعلانات: ${e.message}')),
        );
      }
      rethrow;
    } catch (e) {
      if (mounted && accountMatches(user.id, epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر الاتصال بخادم التطبيق')),
        );
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final next = loadAds();
    setState(() {
      ads = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder owns the localized error. */
    }
  }

  bool _mutating = false;

  Future<void> editAd(Map<String, dynamic> car) =>
      _mutateAd(car, delete: false);
  Future<void> deleteAd(Map<String, dynamic> car) =>
      _mutateAd(car, delete: true);

  Future<void> _mutateAd(
    Map<String, dynamic> car, {
    required bool delete,
  }) async {
    final actor = backendAuthSession.user?.id, epoch = accountEpoch;
    if (_mutating ||
        !accountMatches(actor, epoch) ||
        car['user_id']?.toString() != actor) {
      return;
    }
    _mutating = true;
    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AccountScopedView(
            accountId: actor!,
            child: OwnedVehicleDialog(car: Map.of(car), delete: delete)),
      );
      if (changed == true && accountMatches(actor, epoch)) {
        setState(() {
          ads = loadAds();
        });
      }
    } finally {
      if (accountMatches(actor, epoch)) _mutating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_my_ads')),
          actions: [
            IconButton(
              icon: const Icon(AppIcons.offer),
              tooltip: t('account_received_offers'),
              onPressed: () {
                final id = _authenticatedUserId;
                if (id == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerProfilePage(
                      sellerId: id,
                      sellerName: _backendDisplayName(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: ads,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppLoadingView(label: t('ui_loading_title'));
            }
            if (snapshot.hasError) {
              return _loadError(
                () => setState(() {
                  ads = loadAds();
                }),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return AppStateView(
                title: t('account_no_published_ads'),
                icon: AppIcons.cars,
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final car = items[index];
                      final scheme = Theme.of(context).colorScheme;
                      final title =
                          '${car['brand'] ?? ''} ${car['model'] ?? ''}'.trim();
                      return Material(
                        color: scheme.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () async {
                                final actor = backendAuthSession.user?.id;
                                final epoch = accountEpoch;
                                if (!accountMatches(actor, epoch)) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AccountScopedView(
                                        accountId: actor!,
                                        child: CarDetailsPage(car: car)),
                                  ),
                                );
                                if (accountMatches(actor, epoch)) {
                                  await _refresh();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      title,
                                      textDirection: contentTextDirection(
                                        context,
                                        title,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${car['year'] ?? ''} • ${(parseFormDecimal(car['price']?.toString() ?? '') == null ? t('compare_price_unknown') : formatUsd(parseFormDecimal(car['price'].toString())!))}',
                                      textDirection: TextDirection.ltr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    if (car['status'] == 'sold') ...[
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Container(
                                          key: ValueKey(
                                              'owned_vehicle_sold:${car['id']}'),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: scheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          child: Text(t('car_sold'),
                                              style: TextStyle(
                                                  color:
                                                      scheme.onPrimaryContainer,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => editAd(car),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: Text(t('account_edit_ads')),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => deleteAd(car),
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(t('common_delete')),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ManageShowroomPage extends StatefulWidget {
  const ManageShowroomPage({super.key});

  @override
  State<ManageShowroomPage> createState() => _ManageShowroomPageState();
}

class _ManageShowroomPageState extends State<ManageShowroomPage> {
  final name = TextEditingController();
  final city = TextEditingController();
  final province = TextEditingController();
  final phone = TextEditingController();
  final description = TextEditingController();
  bool loading = true;
  bool saving = false;
  String? loadError, saveError;
  late final String? ownerId;
  VoidCallback? authListener;
  bool get ownerActive =>
      ownerId != null && backendAuthSession.user?.id == ownerId;

  @override
  void initState() {
    super.initState();
    ownerId = backendAuthSession.user?.id;
    authListener = () {
      if (mounted) setState(() {});
    };
    backendAuthSession.addListener(authListener!);
    loadShowroom();
  }

  @override
  void dispose() {
    final l = authListener;
    if (l != null) backendAuthSession.removeListener(l);
    name.dispose();
    city.dispose();
    province.dispose();
    phone.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> loadShowroom() async {
    if (!ownerActive) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = 'ui_business_session_changed';
        });
      }
      return;
    }
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final response = await backendApi.get(
        'sellers/showrooms/$ownerId',
      );
      final row = response is Map ? response['data'] : null;
      if (!mounted) return;
      if (!ownerActive) {
        setState(() => loadError = 'ui_business_session_changed');
        return;
      }
      if (row != null) {
        name.text = row['showroom_name']?.toString() ?? '';
        city.text = row['city']?.toString() ?? '';
        province.text = row['province']?.toString() ?? '';
        phone.text = row['contact_phone']?.toString() ?? '';
        description.text = row['description']?.toString() ?? '';
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => loadError = ownerActive
              ? 'ui_showroom_load_failed'
              : 'ui_business_session_changed',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveShowroom() async {
    if (saving || loading || loadError != null) return;
    if (!ownerActive) {
      setState(() => saveError = 'ui_business_session_changed');
      return;
    }
    final showroomName = name.text.trim();
    if (showroomName.length < 2 || showroomName.length > 80) {
      setState(() => saveError = 'ui_showroom_name_length');
      return;
    }
    final payload = {
      'showroom_name': showroomName,
      'city': city.text.trim().isEmpty ? null : city.text.trim(),
      'province': province.text.trim().isEmpty ? null : province.text.trim(),
      'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
      'description':
          description.text.trim().isEmpty ? null : description.text.trim(),
    };
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      final response = await backendApi.put(
        'sellers/showroom',
        body: payload,
      );
      final row = response is Map ? response['data'] : null;
      if (!mounted) return;
      if (!ownerActive) {
        setState(() => saveError = 'ui_business_session_changed');
        return;
      }
      if (row?['seller_id'] != ownerId) {
        setState(() => saveError = 'ui_showroom_save_failed');
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('misc_showroom_saved'))));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError = ownerActive
              ? 'ui_showroom_save_failed'
              : 'ui_business_session_changed',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget input(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget field(TextDirection direction) => Semantics(
        label: label,
        child: TextField(
          controller: controller,
          enabled: !saving,
          maxLines: maxLines,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
          textDirection: direction,
          textInputAction:
              maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: scheme.onSurface.withValues(alpha: .04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: scheme.onSurface.withValues(alpha: .5)),
            ),
          ),
        ));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (keyboard == TextInputType.phone)
            field(TextDirection.ltr)
          else
            ContentDirectionBuilder(
                controller: controller,
                builder: (context, direction) => field(direction)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
            title: Text(t('account_showroom_setup'),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: (backendAuthSession.user == null &&
                supabase.auth.currentUser == null)
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : !ownerActive
                ? AppStateView(
                    title: t('ui_business_session_changed'),
                    icon: AppIcons.locked,
                  )
                : loading
                    ? AppLoadingView(label: t('ui_loading_title'))
                    : loadError != null
                        ? AppStateView(
                            title: t(loadError!),
                            icon: AppIcons.market,
                            actionLabel: ownerActive ? t('ui_retry') : null,
                            onAction: ownerActive ? loadShowroom : null,
                          )
                        : ListView(
                            padding: const EdgeInsets.all(18),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: AppColors.shadow,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .06),
                                      child: Icon(AppIcons.market,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        t('field_showroom_about'),
                                        style: TextStyle(
                                            color: AppColors.textStrong),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              BusinessFormSection(
                                title: t('ui_business_details'),
                                icon: AppIcons.market,
                                children: [
                                  input(name, t('field_showroom_name')),
                                  input(description, t('field_about'),
                                      maxLines: 4),
                                ],
                              ),
                              BusinessFormSection(
                                title: t('ui_location_contact'),
                                icon: AppIcons.location,
                                children: [
                                  input(province, t('field_province')),
                                  input(city, t('field_city')),
                                  input(phone, t('field_phone_or_wa'),
                                      keyboard: TextInputType.phone),
                                ],
                              ),
                              if (saveError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    t(saveError!),
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 52),
                                child: FilledButton.icon(
                                  onPressed: saving ? null : saveShowroom,
                                  icon: const Icon(Icons.save_rounded),
                                  label: Text(
                                    saving
                                        ? t('common_loading_dots')
                                        : t('misc_save_showroom'),
                                  ),
                                ),
                              ),
                            ],
                          ),
      ),
    );
  }
}

class SellerProfilePage extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  const SellerProfilePage(
      {super.key, required this.sellerId, required this.sellerName});

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfileResult {
  const _SellerProfileResult(this.data, {this.failed = false});
  final Map<String, dynamic> data;
  final bool failed;
}

class _SellerProfilePageState extends State<SellerProfilePage>
    with AccountFeedState<SellerProfilePage> {
  @override
  void reloadAccountFeed() {
    _reviewDraft = null;
    _ratingOpen = false;
    _savingReview = false;
    _updatingOffers.clear();
    profile = _startProfileLoad();
  }

  late Future<_SellerProfileResult> profile;
  final _updatingOffers = <String>{};
  bool _ratingOpen = false, _savingReview = false;
  SellerRatingDraft? _reviewDraft;

  void _reloadProfile() {
    setState(() {
      profile = _startProfileLoad();
    });
  }

  Future<void> _refreshProfile() async {
    final next = _startProfileLoad();
    setState(() {
      profile = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder presents the retry state. */
    }
  }

  @override
  void initState() {
    super.initState();
    profile = _startProfileLoad();
  }

  Future<_SellerProfileResult> _startProfileLoad() async {
    try {
      return _SellerProfileResult(await loadProfile());
    } catch (_) {
      return const _SellerProfileResult({}, failed: true);
    }
  }

  Future<Map<String, dynamic>> loadProfile() async {
    final viewer = backendAuthSession.user;
    final epoch = accountEpoch;
    final carsResponse = await backendApi.get(
      'cars/seller/${widget.sellerId}',
    );
    if (carsResponse is! Map || carsResponse['data'] is! List) {
      throw StateError('Seller cars response is invalid');
    }
    final cars = List<Map<String, dynamic>>.from(
      carsResponse['data'] as List,
    );
    final reviewsResponse = await backendApi.get(
      'sellers/reviews',
      query: {'seller_id': widget.sellerId},
    );
    final showroomResponse = await backendApi.get(
      'sellers/showrooms/${widget.sellerId}',
    );
    final verificationResponse = await backendApi.get(
      'sellers/verifications',
      query: {'ids': widget.sellerId},
    );
    if (reviewsResponse is! Map ||
        reviewsResponse['data'] is! List ||
        showroomResponse is! Map ||
        verificationResponse is! Map ||
        verificationResponse['data'] is! List) {
      throw StateError('Seller profile response is invalid');
    }
    final reviews = List<Map<String, dynamic>>.from(
      reviewsResponse['data'] as List,
    );
    final showroom = showroomResponse['data'];
    final verificationRows = verificationResponse['data'] as List;
    if (!mounted || epoch != accountEpoch) return {};
    final sellerOffersResponse = viewer?.id == widget.sellerId
        ? await backendApi.get('offers/seller')
        : null;
    final offers = sellerOffersResponse == null
        ? <Map<String, dynamic>>[]
        : sellerOffersResponse is Map && sellerOffersResponse['data'] is List
            ? List<Map<String, dynamic>>.from(
                sellerOffersResponse['data'] as List,
              )
            : throw StateError('Backend response is invalid');

    // بطاقات هذا الملف كلّها للبائع نفسه. من دون تحميل مسبق تجيب البطاقات
    // عن الاستعلام نفسه في نفس اللحظة، وأول بطاقة تربح الطلب والباقي
    // ينتظر ثم يقرأ الذاكرة — فيظهر توثيق البائع مرة واحدة فقط. التحميل
    // المسبق يضمن وجود الإجابة قبل بناء أي بطاقة.
    if (!mounted || epoch != accountEpoch) return {};
    final carRows = cars;
    await trustCache.preloadForRows(carRows);
    if (!mounted || epoch != accountEpoch) return {};

    // Preload first image of visible cars only (first 6) for smoother scrolling
    int preloaded = 0;
    for (final row in carRows) {
      if (preloaded >= 6) break;
      final urls = carImageUrls(row);
      if (urls.isNotEmpty && mounted) {
        smartPrecacheImage(urls.first, context);
        preloaded++;
      }
    }

    return {
      'cars': carRows,
      'reviews': reviews,
      'showroom': showroom ?? {},
      'verified': verificationRows.isNotEmpty,
      'offers': offers,
    };
  }

  Future<void> updateOfferStatus(
    String offerId,
    String status, {
    Map<String, dynamic>? offer,
  }) async {
    final user = backendAuthSession.user;
    final epoch = accountEpoch;
    if (user == null ||
        user.id != widget.sellerId ||
        !accountMatches(user.id, epoch) ||
        _updatingOffers.contains(offerId)) {
      return;
    }
    setState(() => _updatingOffers.add(offerId));
    try {
      final response = await backendApi.patch(
        'offers/$offerId/status',
        body: {'status': status},
      );
      final updated = response is Map ? response['data'] : null;
      if (!mounted || !accountMatches(user.id, epoch)) return;
      if (updated?['id']?.toString() != offerId) {
        throw StateError('Offer was not updated');
      }
      _reloadProfile();
      if (status == 'accepted' && offer != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CarOfferChatPage(offer: {...offer, 'status': status}),
          ),
        );
      }
    } catch (_) {
      if (mounted && accountMatches(user.id, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('offer_update_failed'))));
      }
    } finally {
      if (accountMatches(user.id, epoch)) {
        setState(() => _updatingOffers.remove(offerId));
      }
    }
  }

  Future<void> contactShowroom(String phone) async {
    final parsed = SellerPhone.parse(phone);
    await openExternalLink(
      context,
      parsed == null ? null : Uri.https('wa.me', '/${parsed.whatsappDigits}'),
      failureKey: 'misc_whatsapp_failed',
    );
  }

  Future<void> rateSeller() async {
    if (_ratingOpen || _savingReview) return;
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('misc_login_to_rate'))));
      return;
    }
    if (user.id == widget.sellerId) return;
    setState(() => _ratingOpen = true);
    final draft = await showDialog<SellerRatingDraft>(
      context: context,
      builder: (_) => Directionality(
        textDirection: appLocale.direction,
        child: SellerRatingDialog(
          initialDraft: _reviewDraft,
          title: t('rate_seller'),
          commentLabel: t('field_optional_comment'),
          cancelLabel: t('common_cancel'),
          sendLabel: t('common_send'),
          ratingLabel: (rating) =>
              t('ui_rating_choice').replaceAll('{rating}', '$rating'),
        ),
      ),
    );
    if (!mounted || !accountMatches(user.id, epoch)) return;
    setState(() => _ratingOpen = false);
    if (draft == null) return;
    setState(() => _savingReview = true);
    try {
      final response = await backendApi.post('sellers/reviews', body: {
        'seller_id': widget.sellerId,
        'rating': draft.rating,
        'comment': draft.comment.isEmpty ? null : draft.comment,
      });
      if (response is! Map || response['data'] is! Map) {
        throw StateError('Review was not acknowledged');
      }
      if (mounted && accountMatches(user.id, epoch)) {
        _reviewDraft = null;
        trustCache.invalidateSeller(widget.sellerId);
        _reloadProfile();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('ui_review_saved'))));
      }
    } catch (_) {
      if (mounted && accountMatches(user.id, epoch)) {
        _reviewDraft = draft;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('review_save_failed')),
            action: SnackBarAction(label: t('ui_retry'), onPressed: rateSeller),
          ),
        );
      }
    } finally {
      if (accountMatches(user.id, epoch)) setState(() => _savingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final bu = backendAuthSession.user;
    final viewerId =
        bu?.id ?? backendAuthSession.user?.id ?? supabase.auth.currentUser?.id;
    final isOwner = viewerId == widget.sellerId;
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_seller_profile')),
          actions: [
            if (viewerId != null && !isOwner)
              IconButton(
                tooltip: t('account_received_offers'),
                icon: const Icon(AppIcons.offer),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerProfilePage(
                      sellerId: viewerId,
                      sellerName: _backendDisplayName(),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: FutureBuilder<_SellerProfileResult>(
          future: profile,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppLoadingView(label: t('ui_loading_title'));
            }
            if (snapshot.hasError || snapshot.data?.failed == true) {
              return _loadError(_reloadProfile);
            }
            final data = snapshot.data?.data ?? {};
            final cars = (data['cars'] as List<Map<String, dynamic>>?) ?? [];
            final reviews =
                (data['reviews'] as List<Map<String, dynamic>>?) ?? [];
            final offers =
                (data['offers'] as List<Map<String, dynamic>>?) ?? [];
            final showroom = Map<String, dynamic>.from(
              (data['showroom'] as Map?) ?? const {},
            );
            final showroomName =
                showroom['showroom_name']?.toString().trim() ?? '';
            final location = [showroom['city'], showroom['province']]
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .join(' · ');
            final average = reviews.isEmpty
                ? 0.0
                : reviews.fold<double>(
                      0,
                      (sum, review) =>
                          sum + ((review['rating'] as num?)?.toDouble() ?? 0),
                    ) /
                    reviews.length;
            final tier = _badgeFromRatingAndCount(average, reviews.length);
            final phone = SellerPhone.parse(
              showroom['contact_phone']?.toString() ?? '',
            );
            return RefreshIndicator(
              onRefresh: _refreshProfile,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: SellerProfileHeader(
                      name: showroomName.isEmpty
                          ? widget.sellerName
                          : showroomName,
                      location: location,
                      description:
                          showroom['description']?.toString().trim() ?? '',
                      rating: average,
                      reviewCountLabel: reviews.length == 1
                          ? t('ui_profile_one_review')
                          : t('ui_profile_review_count').replaceAll(
                              '{count}',
                              '${reviews.length}',
                            ),
                      listingCountLabel: cars.length == 1
                          ? t('ui_profile_one_listing')
                          : t(
                              'ui_profile_listing_count',
                            ).replaceAll('{count}', '${cars.length}'),
                      verifiedLabel: data['verified'] == true
                          ? t('seller_verified')
                          : null,
                      tierLabel: tier == 'none' ? null : badgeLabel(tier),
                      tierColor: badgeColor(tier),
                      actions: [
                        if (phone != null)
                          OutlinedButton.icon(
                            onPressed: () => contactShowroom(
                              showroom['contact_phone'].toString(),
                            ),
                            icon: const Icon(AppIcons.chat),
                            label: Text(t('support_whatsapp')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        if (!isOwner)
                          OutlinedButton.icon(
                            onPressed: _ratingOpen || _savingReview
                                ? null
                                : rateSeller,
                            icon: const Icon(AppIcons.reviews),
                            label: Text(
                              _savingReview
                                  ? t('common_loading_dots')
                                  : t('review_add'),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: FormSectionHeading(
                      title: t('account_seller_badges'),
                      icon: AppIcons.cars,
                    ),
                  ),
                  if (cars.isEmpty)
                    SliverToBoxAdapter(
                      child: AppStatePanel(
                        title: t('misc_no_ads_now'),
                        icon: AppIcons.cars,
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: cars.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CarCard(
                        key: ValueKey(cars[i]['id']),
                        car: cars[i],
                      ),
                    ),
                  if (isOwner) ...[
                    SliverToBoxAdapter(
                      child: FormSectionHeading(
                        title: t('account_received_offers'),
                        icon: AppIcons.offer,
                      ),
                    ),
                    if (offers.isEmpty)
                      SliverToBoxAdapter(
                        child: AppStatePanel(
                          title: t('account_no_received_offers'),
                          icon: AppIcons.offer,
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: offers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _offerCard(offers[i]),
                      ),
                  ],
                  SliverToBoxAdapter(
                    child: FormSectionHeading(
                      title: t('buyer_reviews'),
                      icon: AppIcons.reviews,
                    ),
                  ),
                  if (reviews.isEmpty)
                    SliverToBoxAdapter(
                      child: AppStatePanel(
                        title: t('account_no_reviews_now'),
                        icon: AppIcons.reviews,
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _reviewCard(reviews[i]),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ]
                    .map(
                      (sliver) => SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: sliver,
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) => _profileCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  '${review['rating']}/5',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if ((review['comment']?.toString().trim() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review['comment'].toString(),
                textDirection: contentTextDirection(
                  context,
                  review['comment'].toString(),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _offerCard(Map<String, dynamic> offer) {
    final id = offer['id']?.toString() ?? '';
    final status = offer['status']?.toString() ?? 'pending';
    final busy = _updatingOffers.contains(id);
    final statusLabel = status == 'pending'
        ? t('account_waiting_reply')
        : status == 'accepted'
            ? t('offer_accepted')
            : t('offer_rejected');
    return _profileCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer['car_title']?.toString() ?? t('car_title'),
            textDirection: contentTextDirection(
              context,
              offer['car_title']?.toString() ?? t('car_title'),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t('ui_buyer_offer_amount').replaceAll(
              '{amount}',
              formatIqdOnly(
                parseFormDecimal('${offer['offer_price'] ?? ''}') ?? 0,
              ),
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
          if ((offer['message']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              offer['message'].toString(),
              textDirection: contentTextDirection(
                context,
                offer['message'].toString(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${t('offer_status')}: $statusLabel',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (status == 'pending' && id.isNotEmpty) ...[
            const SizedBox(height: 12),
            ResponsiveFormPair(
              first: OutlinedButton(
                onPressed:
                    busy ? null : () => updateOfferStatus(id, 'rejected'),
                child: Text(t('offer_reject')),
              ),
              second: FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () => updateOfferStatus(id, 'accepted', offer: offer),
                child: Text(
                  busy ? t('common_loading_dots') : t('offer_accept'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileCard(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: child,
      );
}

class _ActivityRowsResult {
  const _ActivityRowsResult.ready(this.rows)
      : failed = false,
        errorCode = null;
  const _ActivityRowsResult.failed({this.errorCode})
      : rows = const [],
        failed = true;
  final List<Map<String, dynamic>> rows;
  final bool failed;
  final String? errorCode;
}

class MySentOffersPage extends StatefulWidget {
  const MySentOffersPage({super.key});

  @override
  State<MySentOffersPage> createState() => _MySentOffersPageState();
}

class _MySentOffersPageState extends State<MySentOffersPage>
    with AccountFeedState<MySentOffersPage> {
  late Future<_ActivityRowsResult> offers;

  @override
  void reloadAccountFeed() {
    offers = loadOffers();
  }

  @override
  void initState() {
    super.initState();
    offers = loadOffers();
  }

  Future<_ActivityRowsResult> loadOffers() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get('offers/buyer');
      if (!accountMatches(userId, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_my_car_offers'))),
        body: _authenticatedUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: offers,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(
                      () => setState(() {
                        offers = loadOffers();
                      }),
                    );
                  }
                  final items = snapshot.data?.rows ?? [];
                  if (items.isEmpty) {
                    return AppStateView(
                      title: t('account_no_sent_offers'),
                      actionLabel: t('alerts_update'),
                      onAction: () => setState(() {
                        offers = loadOffers();
                      }),
                      icon: AppIcons.offer,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final pending = loadOffers();
                      setState(() {
                        offers = pending;
                      });
                      try {
                        await pending;
                      } catch (_) {}
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final offer = items[index];
                        final accepted = offer['status'] == 'accepted';
                        return Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: accepted
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                offer['car_title']?.toString() ??
                                    t('car_title'),
                                textDirection: contentTextDirection(
                                  context,
                                  offer['car_title']?.toString() ?? '',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                t('ui_sent_offer_amount').replaceAll(
                                  '{amount}',
                                  parseFormDecimal(
                                            offer['offer_price']?.toString() ??
                                                '',
                                          ) ==
                                          null
                                      ? ''
                                      : formatIqdOnly(
                                          parseFormDecimal(
                                            offer['offer_price'].toString(),
                                          )!,
                                        ),
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                              ),
                              Text(
                                '${t('offer_status')}: ${accepted ? t('offer_accepted') : offer['status'] == 'rejected' ? t('offer_rejected') : t('ui_waiting_seller_reply')}',
                              ),
                              if (accepted) ...[
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: () {
                                    final actor = backendAuthSession.user?.id;
                                    if (!accountMatches(actor, accountEpoch)) {
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            CarOfferChatPage(offer: offer),
                                      ),
                                    );
                                  },
                                  icon: const Icon(AppIcons.chat),
                                  label: Text(t('chat_open')),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class CarOfferChatPage extends StatefulWidget {
  final Map<String, dynamic> offer;
  const CarOfferChatPage({super.key, required this.offer});

  @override
  State<CarOfferChatPage> createState() => _CarOfferChatPageState();
}

class _CarOfferChatPageState extends State<CarOfferChatPage>
    with AccountFeedState<CarOfferChatPage> {
  String? _routeActor;
  String? _targetUserId;
  bool _blocked = false;
  bool get _chatAvailable =>
      _routeActor != null && _authenticatedUserId == _routeActor;
  @override
  void reloadAccountFeed() {
    messageController.clear();
    sending = false;
    messages = Future.value([]);
    if (_chatAvailable) messages = loadMessages();
  }

  final TextEditingController messageController = TextEditingController();
  late Future<List<Map<String, dynamic>>> messages;
  bool sending = false;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    try {
      _routeActor = _authenticatedUserId;
    } catch (_) {
      _routeActor = null;
    }
    final offer = widget.offer;
    final currentId = _routeActor;
    final buyer = offer['buyer_id']?.toString();
    final seller = offer['seller_id']?.toString();
    _targetUserId = (buyer == currentId) ? seller : buyer;
    _loadBlockStatus();
    messages = loadMessages();
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _chatAvailable) {
        setState(() {
          messages = loadMessages();
        });
      }
    });
  }

  Future<void> _loadBlockStatus() async {
    final target = _targetUserId;
    if (target == null) return;
    try {
      final res = await backendApi.get('safety/blocks/$target');
      if (res is Map && res['blocked_by_me'] == true) {
        if (mounted) setState(() => _blocked = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    messageController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> loadMessages() async {
    final actor = _authenticatedUserId;
    final epoch = accountEpoch;
    if (!_chatAvailable) return [];
    final response = await backendApi.get(
      'offers/${widget.offer['id']}/messages',
      query: {
        'order': 'created_at.desc.nullslast',
        'limit': '200',
      },
    );
    if (!accountMatches(actor, epoch) || !_chatAvailable) return [];
    if (response is! Map || response['data'] is! List) return [];
    return List<Map<String, dynamic>>.from(response['data'] as List);
  }

  Future<void> sendMessage() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    final body = messageController.text.trim();
    if (userId == null ||
        !_chatAvailable ||
        _blocked ||
        body.isEmpty ||
        sending) {
      return;
    }
    setState(() => sending = true);
    try {
      await backendApi.post(
        'offers/${widget.offer['id']}/messages',
        body: {'body': body},
      );
      if (!accountMatches(userId, epoch) || !_chatAvailable) return;
      if (messageController.text.trim() == body) messageController.clear();
      if (mounted) {
        setState(() {
          messages = loadMessages();
        });
      }
    } catch (error) {
      if (mounted && accountMatches(userId, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('chat_send_failed'))));
      }
    } finally {
      if (accountMatches(userId, epoch)) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final currentUserId = _authenticatedUserId;
    final title = _chatAvailable
        ? (widget.offer['car_title']?.toString() ?? t('chat_offer_chat'))
        : t('chat_offer_chat');
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: contentTextDirection(context, title),
          ),
          actions: [
            IconButton(
              tooltip: t('chat_refresh'),
              onPressed: !_chatAvailable
                  ? null
                  : () => setState(() {
                        messages = loadMessages();
                      }),
              icon: const Icon(Icons.refresh_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: t('chat_safety_options'),
              onSelected: (value) async {
                final target = _targetUserId;
                if (target == null) return;
                if (value == 'report') {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => UserReportDialog(
                      offerId: widget.offer['id']?.toString() ?? '',
                      reportedUserId: target,
                    ),
                  );
                } else if (value == 'block') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t('chat_block_user')),
                      content: Text(t('chat_block_confirm')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(t('cancel'))),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(t('chat_block_user'))),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await backendApi.post('safety/blocks',
                        body: {'blocked_user_id': target});
                    if (mounted) setState(() => _blocked = true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم الحظر')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل الحظر: $e')));
                    }
                  }
                } else if (value == 'unblock') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t('chat_unblock_user')),
                      content: Text(t('chat_unblock_confirm')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(t('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(t('chat_unblock_user')),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await backendApi.delete('safety/blocks/$target');
                    if (mounted) setState(() => _blocked = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم إلغاء الحظر')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل إلغاء الحظر: $e')));
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _blocked ? 'unblock' : 'block',
                  child: Text(
                      _blocked ? t('chat_unblock_user') : t('chat_block_user')),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: Text(t('chat_report_user')),
                ),
              ],
            ),
          ],
        ),
        body: !_chatAvailable
            ? AppStateView(
                title: t(
                  (backendAuthSession.user == null &&
                          supabase.auth.currentUser == null)
                      ? 'login_required_first'
                      : 'ui_vehicle_session_changed',
                ),
                icon: AppIcons.locked,
              )
            : _blocked
                ? AppStateView(
                    title: t('chat_blocked_notice'),
                    icon: AppIcons.locked,
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: messages,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return AppLoadingView(label: t('ui_loading_title'));
                      }
                      if (snapshot.hasError) {
                        return AppStateView(
                          title: t('chat_load_failed'),
                          icon: AppIcons.cloudOff,
                          isError: true,
                          actionLabel: t('ui_retry'),
                          onAction: () => setState(() {
                            messages = loadMessages();
                          }),
                        );
                      }
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) {
                        return AppStateView(
                          title: t('chat_start'),
                          icon: AppIcons.chat,
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(14),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final mine = item['sender_id'] == currentUserId;
                          return Align(
                            alignment: mine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 310),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : card,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SelectableText(
                                item['body']?.toString() ?? '',
                                textDirection: contentTextDirection(
                                  context,
                                  item['body']?.toString() ?? '',
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: mine
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
        bottomNavigationBar: !_chatAvailable || _blocked
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: ContentDirectionBuilder(
                            controller: messageController,
                            builder: (context, direction) => TextField(
                              controller: messageController,
                              minLines: 1,
                              maxLines: 4,
                              textDirection: direction,
                              decoration: InputDecoration(
                                hintText: t('chat_input_hint'),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: messageController,
                          builder: (context, value, _) {
                            final enabled = !_blocked &&
                                !sending &&
                                value.text.trim().isNotEmpty;
                            final scheme = Theme.of(context).colorScheme;
                            return IconButton.filled(
                              tooltip: t('chat_send'),
                              onPressed: enabled ? sendMessage : null,
                              icon: sending
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onSurface,
                                      ),
                                    )
                                  : Icon(
                                      Icons.send_rounded,
                                      color: enabled
                                          ? scheme.onPrimary
                                          : scheme.onSurface.withValues(
                                              alpha: .38,
                                            ),
                                    ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// هل المستخدم الحالي مُسجَّل في `public.app_admins`؟ (مصدر الحقيقة: Backend/Neon)
///
/// الهوية الإدارية تُشتق من جلسة Backend المستقلة ومن استجابة الخادم فقط.
/// الخادم يتحقق دائماً من `public.app_admins` باستخدام UUID المصادق عليه؛
/// لا نثق بأي علم `isAdmin`/دور/معرّف يرسله العميل. عند غياب الجلسة أو
/// انتهائها أو فشل الشبكة أو سحب صلاحية المشرف نُعيد `false` (إغلاق آمن).
Future<bool> currentUserIsAdmin() async {
  try {
    // يتطلب جلسة Backend صالحة (يجدد عند الحاجة). لا fallback لـ Supabase.
    final token = await backendAuthSession.validAccessToken();
    if (token == null || token.isEmpty) return false;
    final response =
        await backendApi.get('sellers/admin/status', backendOnly: true);
    if (response is! Map || response['data'] is! Map) {
      backendAuthSession.applyProfile({'is_admin': false});
      return false;
    }
    final isAdmin = response['data']['is_admin'] == true;
    // مزامنة حالة UI من استجابة الخادم الموثوقة فقط.
    backendAuthSession.applyProfile({'is_admin': isAdmin});
    return isAdmin;
  } catch (_) {
    return false;
  }
}

/// حذف إعلان واحد عن طريق دالة RPC إدارية في Supabase.
///
/// الحماية كلها في القاعدة وليست في الواجهة:
///   * `admin_delete_ad` تعمل بـSECURITY DEFINER، فتتجاوز RLS عمداً.
///   * مُعرّف الجدول يُقارَن داخل الدالة بقائمة بيضاء
///     (cars / market_items / jobs) فلا يمكن تمرير `profiles` أو غيره.
///   * الدالة ترفض كل من ليس في `app_admins`، وترفض `anon` تماماً.
///   * الدالة تُسجّل العملية في `admin_ad_deletions` للتدقيق.
///
/// إرجاع `true` يعني أن صفاً واحداً حُذف فعلاً.
///
/// لا فحص صلاحيات في هذه الدالة عمداً: القاعدة هي المرجع الوحيد.
/// `currentUserIsAdmin()` تُستخدم لإظهار الزر فقط، أما التنفيذ فيحكمه
/// `app_admins` داخل Supabase. أي فحص مسبق هنا كان سيعطي انطباعاً زائفاً
/// بأن الحماية في العميل، ويزيد رحلة شبكية زائدة بلا فائدة.
///
/// [lastAdminDeleteError] يحمل آخر خطأ حقيقي من Supabase. السبب:
/// النسخة الأولى كانت تلتقط الاستثناء بـ`catch (_)` وتُرجع false،
/// فيظهر للمستخدم رسالة عامة واحدة بينما السبب الحقيقي ضاع تماماً.
/// تبقى التفاصيل للتشخيص، وتعرض الواجهة رسالة محلية عامة دون تفاصيل القاعدة.
String? lastAdminDeleteError;

/// نُفسّر أشهر الأخطاء القادمة من الخادم بالعربية.
String _explainAdminDeleteError(String? code, String message) {
  if (message.contains('admin_delete_ad')) {
    if (message.contains('table') && message.contains('not deletable')) {
      return t('admin_delete_ad_table_not_allowed');
    }
    if (message.contains('admin privileges required')) {
      return t('admin_delete_ad_not_admin');
    }
    if (message.contains('sign-in required')) {
      return t('admin_delete_ad_not_authenticated');
    }
  }
  if (code == 'PGRST202' || message.contains('Could not find the function')) {
    return t('admin_delete_ad_setup_required');
  }
  if (code == '42501' || message.contains('permission denied')) {
    return t('admin_delete_ad_permission_error');
  }
  return '${t('admin_delete_ad_db_error')}${code == null ? '' : ' ($code)'}';
}

/// نُفسّر أسباب الرفض القادمة من الدالة بالعربية.
String _adminDeleteReasonText(String reason) {
  switch (reason) {
    case 'not_authenticated':
      return t('admin_delete_ad_not_authenticated');
    case 'not_admin':
      return t('admin_delete_ad_not_admin');
    case 'table_not_allowed':
      return t('admin_delete_ad_table_not_allowed');
    case 'bad_id':
      return t('admin_delete_ad_bad_id');
    case 'not_found':
      return t('admin_delete_ad_not_found');
    default:
      return t('admin_delete_ad_db_error');
  }
}

Future<bool> adminDeleteAd(String table, String id) async {
  final user = backendAuthSession.user;
  if (user == null) {
    lastAdminDeleteError = t('admin_delete_ad_not_authenticated');
    return false;
  }
  lastAdminDeleteError = null;
  try {
    // الدالة تُرجع jsonb: {"ok":bool,"deleted":int,"reason":string?}
    final result = await backendApi.delete('market/admin/ads/$table/$id');
    if (result is Map) {
      final ok = backendAuthSession.user?.id == user.id &&
          result['ok'] == true &&
          result['deleted'] == 1;
      if (!ok) {
        lastAdminDeleteError =
            _adminDeleteReasonText('${result['reason'] ?? 'unknown'}');
      }
      return ok;
    }
    lastAdminDeleteError = t('admin_delete_ad_db_error');
    return false;
  } on BackendApiException catch (error) {
    if (error.statusCode == 403) {
      lastAdminDeleteError = t('admin_delete_ad_not_admin');
    } else if (error.statusCode == 401) {
      lastAdminDeleteError = t('admin_delete_ad_not_authenticated');
    } else if (error.statusCode == 404) {
      lastAdminDeleteError = t('admin_delete_ad_not_found');
    } else if (error.statusCode == 400) {
      lastAdminDeleteError = _adminDeleteReasonText(
          error.message.contains('table') ? 'table_not_allowed' : 'bad_id');
    } else {
      lastAdminDeleteError = t('admin_delete_ad_db_error');
    }
    debugPrint('adminDeleteAd failed: ${error.statusCode} / ${error.message}');
    return false;
  } on PostgrestException catch (error) {
    // يبقى هذا المسار للأخطاء التي ترد كاستثناء من PostgREST نفسه،
    // أهمّها PGRST202 أي أن الدالة غير موجودة في القاعدة بعد.
    lastAdminDeleteError = _explainAdminDeleteError(error.code, error.message);
    debugPrint('adminDeleteAd failed: ${error.code} / ${error.message}');
    return false;
  } catch (error) {
    lastAdminDeleteError = t('admin_delete_ad_db_error');
    debugPrint('adminDeleteAd failed: $error');
    return false;
  }
}

/// نافذة تأكيد الحذف الإداري: «هل أنت متأكد من حذف هذا الإعلان؟»
Future<bool> confirmAdminDeleteAd(
  BuildContext context, {
  String? itemTitle,
  String? sectionKey,
}) async {
  final account = backendAuthSession.user?.id;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      context.dependOnAppStrings();
      return AlertDialog(
        scrollable: true,
        title: Text(t('admin_delete_ad')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (itemTitle != null && itemTitle.trim().isNotEmpty) ...[
              Text(
                itemTitle,
                textDirection: contentTextDirection(context, itemTitle),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (sectionKey != null)
                Text(
                  t(sectionKey),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              const SizedBox(height: 16),
            ],
            Text(t('admin_delete_ad_confirm')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('common_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('common_delete')),
          ),
        ],
      );
    },
  );
  return account != null &&
      backendAuthSession.user?.id == account &&
      confirmed == true;
}

void adminDeleteMessage(BuildContext context, bool ok) {
  final error = ok ? null : lastAdminDeleteError;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t(ok ? 'admin_delete_ad_done' : 'admin_delete_ad_failed')),
        if (error != null && error.isNotEmpty) Text(error),
      ],
    ),
  ));
}

/// صفحة «إدارة الإعلانات» — متاحة للأدمن فقط، وتعرض إعلانات
/// cars وmarket_items وjobs مع زر حذف لكل إعلان.
class AdminAdsManagementPage extends StatefulWidget {
  const AdminAdsManagementPage({super.key});

  @override
  State<AdminAdsManagementPage> createState() => _AdminAdsManagementPageState();
}

class _AdminAdsManagementPageState extends State<AdminAdsManagementPage> {
  static const _tables = <String>['cars', 'market_items', 'jobs'];
  final Map<String, List<Map<String, dynamic>>> _items = {};
  final _ownerId = backendAuthSession.user?.id;
  bool get _sameSession =>
      _ownerId != null && backendAuthSession.user?.id == _ownerId;
  VoidCallback? _authListener;
  bool _loading = true;
  bool _admin = false;
  bool _accessFailed = false;
  bool _bootstrapping = false;
  bool _refreshing = false;
  final Set<String> _failedTables = {};
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _authListener = () {
      if (!mounted) return;
      if (!_sameSession) {
        setState(() {
          _items.clear();
          _failedTables.clear();
          _admin = false;
          _loading = false;
        });
      } else if (!_admin && !_bootstrapping) {
        _bootstrap();
      }
    };
    backendAuthSession.addListener(_authListener!);
    _bootstrap();
  }

  @override
  void dispose() {
    final l = _authListener;
    if (l != null) backendAuthSession.removeListener(l);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping || !_sameSession) {
      if (mounted && !_sameSession) setState(() => _loading = false);
      return;
    }
    _bootstrapping = true;
    setState(() {
      _loading = true;
      _accessFailed = false;
    });
    try {
      final user = supabase.auth.currentUser;
      final admin = user == null
          ? null
          : await supabase
              .from('app_admins')
              .select('user_id')
              .eq('user_id', user.id)
              .maybeSingle();
      if (!mounted || !_sameSession) return;
      if (admin == null) {
        setState(() {
          _admin = false;
          _loading = false;
        });
        return;
      }
      for (final table in _tables) {
        await _load(table);
      }
      if (!mounted || !_sameSession) return;
      setState(() {
        _admin = true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _accessFailed = true;
        });
      }
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> _load(String table) async {
    if (!mounted || !_sameSession) return;
    try {
      final data = await supabase
          .from(table)
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted || !_sameSession) return;
      _items[table] = List<Map<String, dynamic>>.from(data);
      _failedTables.remove(table);
    } catch (_) {
      if (mounted && _sameSession) _failedTables.add(table);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !_sameSession || !_admin) return;
    setState(() {
      _refreshing = true;
    });
    for (final table in _tables) {
      await _load(table);
    }
    if (mounted) {
      setState(() {
        _refreshing = false;
      });
    }
  }

  Future<void> _delete(String table, Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    final key = '$table:$id';
    if (!_sameSession ||
        !_admin ||
        id == null ||
        id.isEmpty ||
        _deleting.isNotEmpty ||
        _refreshing) {
      return;
    }
    setState(() {
      _deleting.add(key);
    });
    try {
      final confirmed = await confirmAdminDeleteAd(
        context,
        itemTitle: _label(row, table),
        sectionKey: table == 'cars'
            ? 'section_cars'
            : table == 'market_items'
                ? 'section_market'
                : 'section_jobs',
      );
      if (!mounted || !_sameSession || !confirmed) return;
      final ok = await adminDeleteAd(table, id);
      if (!mounted || !_sameSession) return;
      if (ok) {
        setState(() {
          _items[table]?.removeWhere((e) => e['id'].toString() == id);
        });
      }
      adminDeleteMessage(context, ok);
    } finally {
      if (mounted) {
        setState(() {
          _deleting.remove(key);
        });
      }
    }
  }

  String _label(Map<String, dynamic> row, String table) {
    final raw =
        (row['title'] ?? row['brand'] ?? row['company'] ?? '').toString();
    if (raw.trim().isNotEmpty) return raw;
    return t('misc_default_ad');
  }

  String _sub(Map<String, dynamic> row) {
    final gov = (row['governorate'] ?? row['city'] ?? '').toString();
    final price = (row['price'] ?? row['salary'] ?? '').toString();
    final parts = <String>[
      if (gov.isNotEmpty && gov != 'null') gov,
      if (price.isNotEmpty && price != 'null')
        parseFormDecimal(price) == null
            ? price
            : formatUsd(parseFormDecimal(price)!),
    ];
    return parts.join(' - ');
  }

  String _tableTitle(String table) {
    if (table == 'cars') return t('section_cars');
    if (table == 'market_items') return t('section_market');
    return t('section_jobs');
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            t('admin_ads_manage'),
          ),
          centerTitle: true,
        ),
        body: !_sameSession
            ? AppStateView(
                title: t('ui_business_session_changed'),
                icon: AppIcons.locked,
              )
            : _loading
                ? AppLoadingView(label: t('ui_loading_title'))
                : _accessFailed
                    ? _loadError(_bootstrap)
                    : !_admin
                        ? AppStateView(
                            title: t('admin_only_notice'),
                            icon: AppIcons.locked)
                        : RefreshIndicator(
                            onRefresh:
                                _deleting.isEmpty ? _refresh : () async {},
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 30),
                              children: [
                                for (final table in _tables) ...[
                                  Text(
                                    _tableTitle(table),
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  if (_failedTables.contains(table))
                                    AppStatePanel(
                                      title: t('ui_load_error_title'),
                                      message: t('ui_load_error_body'),
                                      icon: AppIcons.cloudOff,
                                      isError: true,
                                      actionLabel: t('ui_retry'),
                                      onAction:
                                          _refreshing || _deleting.isNotEmpty
                                              ? null
                                              : _refresh,
                                    )
                                  else if ((_items[table] ?? const []).isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      child: Text(
                                        t('admin_ads_none'),
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  else
                                    for (final row in _items[table] ?? const [])
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: card,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: AppColors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _label(row, table),
                                                    textDirection:
                                                        contentTextDirection(
                                                            context,
                                                            _label(row, table)),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  if (_sub(row).isNotEmpty)
                                                    Text(
                                                      _sub(row),
                                                      textDirection:
                                                          contentTextDirection(
                                                              context,
                                                              _sub(row)),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: t('admin_delete_ad'),
                                              onPressed: _deleting.isNotEmpty ||
                                                      _refreshing
                                                  ? null
                                                  : () => _delete(table, row),
                                              icon: _deleting.contains(
                                                      '$table:${row['id']}')
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  const SizedBox(height: 18),
                                ],
                              ],
                            ),
                          ),
      ),
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _ReportsResult {
  const _ReportsResult.ready(this.rows)
      : denied = false,
        failed = false;
  const _ReportsResult.denied()
      : rows = const [],
        denied = true,
        failed = false;
  const _ReportsResult.failed()
      : rows = const [],
        denied = false,
        failed = true;
  final List<Map<String, dynamic>> rows;
  final bool denied, failed;
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with AccountFeedState<AdminDashboardPage> {
  late Future<_ReportsResult> reports;
  final Set<String> _busy = {}, _verifyingSellers = {};
  @override
  void reloadAccountFeed() {
    _busy.clear();
    _verifyingSellers.clear();
    reports = loadReports();
  }

  @override
  void initState() {
    super.initState();
    reports = loadReports();
  }

  Future<_ReportsResult> loadReports() async {
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (user == null) return const _ReportsResult.denied();
    try {
      final response = await backendApi.get('safety/admin/car-reports');
      if (!accountMatches(user.id, epoch)) return const _ReportsResult.denied();
      if (response is! Map || response['data'] is! List) {
        return const _ReportsResult.failed();
      }
      return _ReportsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } on BackendApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const _ReportsResult.denied();
      }
      return accountMatches(user.id, epoch)
          ? const _ReportsResult.failed()
          : const _ReportsResult.denied();
    } catch (_) {
      return accountMatches(user.id, epoch)
          ? const _ReportsResult.failed()
          : const _ReportsResult.denied();
    }
  }

  Future<void> _refresh() async {
    final next = loadReports();
    setState(() {
      reports = next;
    });
    await next;
  }

  void _notice(String key) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(key))));
    }
  }

  Future<bool> _confirm(
    Map<String, dynamic> report,
    String title, {
    bool seller = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    seller
                        ? 'ui_report_verify_confirm'
                        : 'ui_report_change_confirm',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(seller ? 'ui_report_seller_id' : 'ui_report_listing_id'),
                ),
                SelectableText(
                  (report[seller ? 'seller_id' : 'car_id'] ??
                          t('common_unspecified'))
                      .toString(),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t('common_cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t('ui_business_confirm')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> setReportStatus(
    Map<String, dynamic> report,
    String status,
  ) async {
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    final id = report['id']?.toString() ?? '';
    if (user == null || id.isEmpty || _busy.contains(id)) return;
    setState(() {
      _busy.add(id);
    });
    try {
      if (!await _confirm(
            report,
            t(status == 'open' ? 'ad_reopen' : 'ad_status_reviewed'),
          ) ||
          !mounted ||
          !accountMatches(user.id, epoch)) {
        return;
      }
      final response = await backendApi.patch(
        'safety/admin/car-reports/$id',
        body: {
          'status': status,
          'expected_status': report['status'],
        },
      );
      final changed = response is Map ? response['data'] : null;
      if (changed is! Map ||
          changed['id']?.toString() != id ||
          changed['status'] != status) {
        throw StateError('Decision not acknowledged');
      }
      if (!mounted || !accountMatches(user.id, epoch)) return;
      _notice('ui_report_updated');
      await _refresh();
    } catch (_) {
      if (!accountMatches(user.id, epoch)) return;
      _notice('ui_report_update_failed');
    } finally {
      if (mounted && accountMatches(user.id, epoch)) {
        setState(() {
          _busy.remove(id);
        });
      }
    }
  }

  Future<void> verifySeller(Map<String, dynamic> report) async {
    final sellerId = report['seller_id']?.toString().trim() ?? '';
    final id = report['id']?.toString() ?? '';
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (sellerId.isEmpty ||
        id.isEmpty ||
        user == null ||
        _busy.contains(id) ||
        _verifyingSellers.contains(sellerId)) {
      return;
    }
    setState(() {
      _busy.add(id);
      _verifyingSellers.add(sellerId);
    });
    try {
      if (!await _confirm(report, t('seller_verify'), seller: true) ||
          !mounted ||
          !accountMatches(user.id, epoch)) {
        return;
      }
      final response = await backendApi.post(
        'sellers/verify',
        body: {
          'seller_id': sellerId,
          'note': t('misc_admin_verified'),
        },
      );
      final changed = response is Map ? response['data'] : null;
      if (!accountMatches(user.id, epoch)) return;
      if (changed is! Map || changed['seller_id'] != sellerId) {
        throw StateError('Verification not acknowledged');
      }
      _notice('seller_verified_ok');
    } on BackendApiException catch (error) {
      if (!accountMatches(user.id, epoch)) return;
      _notice(
        error.statusCode == 409
            ? 'seller_already_verified'
            : 'misc_seller_verify_failed',
      );
    } catch (_) {
      if (!accountMatches(user.id, epoch)) return;
      _notice('misc_seller_verify_failed');
    } finally {
      if (mounted && accountMatches(user.id, epoch)) {
        setState(() {
          _busy.remove(id);
          _verifyingSellers.remove(sellerId);
        });
      }
    }
  }

  Future<void> openReportedCar(Map<String, dynamic> report) async {
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (user == null || !accountMatches(user.id, epoch)) return;
    final id = report['id']?.toString() ?? '';
    final carId = report['car_id']?.toString().trim() ?? '';
    if (id.isEmpty || carId.isEmpty || _busy.contains(id)) return;
    setState(() {
      _busy.add(id);
    });
    try {
      final response = await backendApi.get(
        'safety/admin/car-reports/$carId/car',
      );
      final car = response is Map ? response['data'] : null;
      if (!mounted || !accountMatches(user.id, epoch)) return;
      if (car == null) {
        _notice('ad_not_found');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountScopedView(
            accountId: user.id,
            child: CarDetailsPage(car: Map<String, dynamic>.from(car)),
          ),
        ),
      );
      if (mounted && accountMatches(user.id, epoch)) await _refresh();
    } catch (_) {
      if (!accountMatches(user.id, epoch)) return;
      _notice('ui_report_listing_failed');
    } finally {
      if (mounted && accountMatches(user.id, epoch)) {
        setState(() {
          _busy.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            t('ui_reports_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: t('admin_ads_manage'),
              icon: const Icon(AppIcons.campaign),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAdsManagementPage(),
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (target) {
                final Widget page;
                if (target == 'business') {
                  page = const AdminBusinessAdsPage();
                } else if (target == 'wallet') {
                  page = const WalletAdminReviewPage();
                } else {
                  final id = _authenticatedUserId;
                  if (id == null) return;
                  page = SellerProfilePage(
                    sellerId: id,
                    sellerName: _backendDisplayName(),
                  );
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                );
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'business',
                  child: Text(t('account_business_ads_all')),
                ),
                PopupMenuItem(
                  value: 'wallet',
                  child: Text(t('admin_wallet_title')),
                ),
                PopupMenuItem(
                  value: 'offers',
                  child: Text(t('account_received_offers')),
                ),
              ],
            ),
          ],
        ),
        body: FutureBuilder<_ReportsResult>(
          future: reports,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppLoadingView(label: t('ui_loading_title'));
            }
            if (snapshot.hasError || snapshot.data?.failed == true) {
              return _loadError(_refresh);
            }
            if (snapshot.data?.denied == true) {
              return AppStateView(
                title: t('admin_only_notice'),
                icon: AppIcons.locked,
              );
            }
            final items = snapshot.data?.rows ?? [];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: items.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: constraints.maxHeight,
                            child: AppStateView(
                              title: t('report_no_reports'),
                              icon: AppIcons.inbox,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final report = items[index];
                        final status = report['status']?.toString() ?? '';
                        final sellerId =
                            report['seller_id']?.toString().trim() ?? '';
                        final carId = report['car_id']?.toString().trim() ?? '';
                        final busy = _busy.contains(report['id']?.toString());
                        final created = DateTime.tryParse(
                          report['created_at']?.toString() ?? '',
                        )?.toLocal();
                        final scheme = Theme.of(context).colorScheme;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('ui_report_listing_title'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                carId.isEmpty ? t('common_unspecified') : carId,
                                textDirection: TextDirection.ltr,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              Chip(
                                label: Text(
                                  t(
                                    status == 'open'
                                        ? 'ad_new'
                                        : status == 'resolved'
                                            ? 'ad_status_reviewed'
                                            : status == 'closed'
                                                ? 'ad_status_closed'
                                                : 'common_unspecified',
                                  ),
                                ),
                              ),
                              Text(
                                t('report_reason'),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                textDirection: contentTextDirection(context,
                                    report['reason']?.toString() ?? ''),
                                report['reason']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? report['reason'].toString()
                                    : t('common_unspecified'),
                              ),
                              if (created != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${t('report_status')}: ${MaterialLocalizations.of(context).formatFullDate(created)} • ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(created))}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              if (busy) const LinearProgressIndicator(),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: busy || carId.isEmpty
                                        ? null
                                        : () => openReportedCar(report),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: Text(t('ad_view')),
                                  ),
                                  if (sellerId.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: busy ||
                                              _verifyingSellers.contains(
                                                sellerId,
                                              )
                                          ? null
                                          : () => verifySeller(report),
                                      icon: const Icon(Icons.verified_outlined),
                                      label: Text(t('seller_verify')),
                                    ),
                                  if (status == 'open')
                                    FilledButton.tonalIcon(
                                      onPressed: busy
                                          ? null
                                          : () => setReportStatus(
                                                report,
                                                'resolved',
                                              ),
                                      icon: const Icon(Icons.done_rounded),
                                      label: Text(t('ad_status_reviewed')),
                                    ),
                                  if (status == 'resolved' ||
                                      status == 'closed')
                                    TextButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              setReportStatus(report, 'open'),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: Text(t('ad_reopen')),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

class AdminBusinessAdsPage extends StatefulWidget {
  const AdminBusinessAdsPage({super.key});

  @override
  State<AdminBusinessAdsPage> createState() => _AdminBusinessAdsPageState();
}

class _BusinessAdminResult {
  const _BusinessAdminResult.ready(this.rows)
      : denied = false,
        failed = false;
  const _BusinessAdminResult.denied()
      : rows = const [],
        denied = true,
        failed = false;
  const _BusinessAdminResult.failed()
      : rows = const [],
        denied = false,
        failed = true;
  final List<Map<String, dynamic>> rows;
  final bool denied, failed;
}

class _AdminBusinessAdsPageState extends State<AdminBusinessAdsPage>
    with AccountFeedState<AdminBusinessAdsPage> {
  String selectedFilter = 'pending';
  late Future<_BusinessAdminResult> _adsFuture;
  final Set<String> _busy = {};
  static const _filters = [
    'pending',
    'approved',
    'rejected',
    'active',
    'expired',
    'paused',
  ];
  static const _labelKeys = {
    'pending': 'ad_status_pending',
    'approved': 'ad_status_approved',
    'rejected': 'ad_status_rejected',
    'active': 'ad_status_active',
    'expired': 'ad_status_expired',
    'paused': 'ad_status_stopped',
  };
  String _label(String status) => t(_labelKeys[status] ?? 'common_unspecified');

  String _paymentLabel(String status) => t(
        {
              'paid': 'ui_business_paid',
              'unpaid': 'ui_business_unpaid',
              'pending': 'ui_business_payment_pending',
              'failed': 'ui_business_payment_failed',
              'refunded': 'ui_business_refunded',
            }[status] ??
            'common_unspecified',
      );

  String _businessName(Map<String, dynamic> ad) {
    final value = ad['business_name']?.toString().trim() ?? '';
    return value.isEmpty ? t('common_unspecified') : value;
  }

  @override
  void reloadAccountFeed() {
    _busy.clear();
    selectedFilter = 'pending';
    _adsFuture = loadAds();
  }

  @override
  void initState() {
    super.initState();
    _adsFuture = loadAds();
  }

  Future<_BusinessAdminResult> loadAds() async {
    final filter = selectedFilter;
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (user == null) return const _BusinessAdminResult.denied();
    try {
      final response = await backendApi.get(
        'business-ads/admin',
        query: {
          'statuses': (filter == 'all' ? _filters : [filter]).join(','),
        },
      );
      if (!accountMatches(user.id, epoch)) {
        return const _BusinessAdminResult.denied();
      }
      if (response is! Map || response['data'] is! List) {
        throw const BackendApiException('تعذر تحميل الإعلانات التجارية');
      }
      return _BusinessAdminResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } on BackendApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const _BusinessAdminResult.denied();
      }
      return accountMatches(user.id, epoch)
          ? const _BusinessAdminResult.failed()
          : const _BusinessAdminResult.denied();
    } catch (_) {
      return accountMatches(user.id, epoch)
          ? const _BusinessAdminResult.failed()
          : const _BusinessAdminResult.denied();
    }
  }

  Future<void> _refresh() async {
    final next = loadAds();
    setState(() {
      _adsFuture = next;
    });
    await next;
  }

  Future<void> _decide(
    Map<String, dynamic> ad,
    String status, {
    bool payment = false,
  }) async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!accountMatches(actor, epoch)) return;
    final id = ad['id']?.toString() ?? '';
    if (id.isEmpty || _busy.contains(id)) return;
    setState(() {
      _busy.add(id);
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(payment ? t('payment_confirm') : _label(status)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_businessName(ad),
                  textDirection:
                      contentTextDirection(context, _businessName(ad)),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SelectableText(id,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(
                status == 'approved' && !payment
                    ? t('ui_business_approve_confirm')
                    : t('ui_business_change_confirm'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('ui_business_confirm')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !accountMatches(actor, epoch)) {
        return;
      }
      if (!accountMatches(actor, epoch)) return;
      final response = await backendApi.patch(
        'business-ads/admin/$id/decision',
        body: {
          'payment': payment,
          'status': status,
          'expected_status': ad['status'],
          'expected_payment_status': ad['payment_status'],
        },
      );
      if (response is! Map ||
          response['data'] is! Map ||
          response['data']['id']?.toString() != id ||
          response['data'][payment ? 'payment_status' : 'status'] != status) {
        throw StateError('Decision not acknowledged');
      }
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('ui_business_updated'))));
      await _refresh();
    } catch (_) {
      if (mounted && accountMatches(actor, epoch)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('ui_business_update_failed'))));
      }
    } finally {
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _busy.remove(id);
        });
      }
    }
  }

  Future<void> _viewAdDetails(Map<String, dynamic> ad) async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (actor == null || !accountMatches(actor, epoch)) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScopedView(
          accountId: actor,
          child: BusinessAdDetailsPage(
            ad: BusinessAdData.fromJson(Map<String, dynamic>.from(ad)),
          ),
        ),
      ),
    );
    if (mounted && accountMatches(actor, epoch)) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_business_ads_all')),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('business_status_filter:$accountEpoch'),
                initialValue: selectedFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t('ui_business_status_filter'),
                ),
                items: ['all', ..._filters]
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(
                          status == 'all' ? t('common_all') : _label(status),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null && value != selectedFilter) {
                    setState(() {
                      selectedFilter = value;
                      _adsFuture = loadAds();
                    });
                  }
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<_BusinessAdminResult>(
                future: _adsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(_refresh);
                  }
                  if (snapshot.data?.denied == true) {
                    return AppStateView(
                      title: t('admin_only_notice'),
                      icon: AppIcons.locked,
                    );
                  }
                  final items = snapshot.data?.rows ?? [];
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: items.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: AppStateView(
                                    title: t('misc_no_ads_status'),
                                    icon: AppIcons.campaign,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final ad = items[index];
                              final status = ad['status']?.toString() ?? '';
                              final busy = _busy.contains(ad['id']?.toString());
                              final scheme = Theme.of(context).colorScheme;
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _businessName(ad),
                                      textDirection: contentTextDirection(
                                          context, _businessName(ad)),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Chip(label: Text(_label(status))),
                                        Chip(
                                          label: Text(
                                            _paymentLabel(
                                              ad['payment_status']
                                                      ?.toString() ??
                                                  '',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (ad['category'] != null)
                                      Text(
                                        '${t('ui_business_category')}: ${BusinessCategories.label(ad['category'].toString())}',
                                      ),
                                    if (ad['governorate'] != null)
                                      Text(
                                        '${t('ui_business_province')}: ${ad['governorate']}',
                                      ),
                                    const SizedBox(height: 10),
                                    if (busy) const LinearProgressIndicator(),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (status == 'pending') ...[
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _decide(ad, 'approved'),
                                            icon: const Icon(
                                              Icons.check_rounded,
                                            ),
                                            label: Text(t('offer_accept')),
                                          ),
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _decide(ad, 'rejected'),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                            label: Text(t('offer_reject')),
                                          ),
                                        ],
                                        if (status == 'approved' ||
                                            status == 'paused')
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _decide(ad, 'active'),
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                            label: Text(
                                              t('ui_business_activate'),
                                            ),
                                          ),
                                        if (status == 'approved' ||
                                            status == 'active')
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _decide(ad, 'paused'),
                                            icon: const Icon(
                                              Icons.pause_rounded,
                                            ),
                                            label: Text(t('common_stop')),
                                          ),
                                        if (ad['payment_status'] != 'paid')
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _decide(
                                                      ad,
                                                      'paid',
                                                      payment: true,
                                                    ),
                                            icon: const Icon(
                                              Icons.payment_rounded,
                                            ),
                                            label: Text(t('payment_confirm')),
                                          ),
                                        TextButton.icon(
                                          onPressed: busy
                                              ? null
                                              : () => _viewAdDetails(ad),
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                          ),
                                          label: Text(t('ad_view')),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityNotificationsPage extends StatefulWidget {
  const ActivityNotificationsPage({super.key});

  @override
  State<ActivityNotificationsPage> createState() =>
      _ActivityNotificationsPageState();
}

class _ActivityNotificationsPageState extends State<ActivityNotificationsPage>
    with AccountFeedState<ActivityNotificationsPage> {
  late Future<_ActivityRowsResult> notifications;
  String? _openingId;

  @override
  void reloadAccountFeed() {
    notifications = loadNotifications();
    _openingId = null;
  }

  @override
  void initState() {
    super.initState();
    notifications = loadNotifications();
  }

  Future<_ActivityRowsResult> loadNotifications() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get('activity/notifications');
      if (!accountMatches(userId, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  Future<void> openNotification(Map<String, dynamic> notification) async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null ||
        !accountMatches(userId, epoch) ||
        _openingId != null) {
      return;
    }
    setState(() {
      _openingId = notification['id'].toString();
    });
    try {
      if (notification['read_at'] == null) {
        await backendApi.patch(
          'activity/notifications/${notification['id']}/read',
        );
      }

      if (!mounted || !accountMatches(userId, epoch)) return;
      final type = notification['notification_type']?.toString();
      if (type == 'new_offer') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SellerProfilePage(
              sellerId: userId,
              sellerName: _backendDisplayName(),
            ),
          ),
        );
      } else {
        final offerId = notification['offer_id']?.toString().trim();
        final offerResponse = offerId == null || offerId.isEmpty
            ? null
            : await backendApi.get('offers/$offerId');
        final offer = offerResponse is Map ? offerResponse['data'] : null;
        if (!mounted || !accountMatches(userId, epoch)) return;
        if (offer != null && offer['status'] == 'accepted') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CarOfferChatPage(offer: Map<String, dynamic>.from(offer)),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('ui_conversation_unavailable'))),
          );
        }
      }
      if (mounted && accountMatches(userId, epoch)) {
        setState(() {
          notifications = loadNotifications();
        });
      }
    } catch (error) {
      if (mounted && accountMatches(userId, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('alerts_open_failed'))));
      }
    } finally {
      if (mounted && accountMatches(userId, epoch)) {
        setState(() {
          _openingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('chat_hub_desc')),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: () => setState(() {
                notifications = loadNotifications();
              }),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _authenticatedUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: notifications,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(
                      () => setState(() {
                        notifications = loadNotifications();
                      }),
                    );
                  }
                  final items = snapshot.data?.rows ?? [];
                  if (items.isEmpty) {
                    return AppStateView(
                      title: t('alerts_empty_now'),
                      icon: AppIcons.notifications,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final pending = loadNotifications();
                      setState(() {
                        notifications = pending;
                      });
                      try {
                        await pending;
                      } catch (_) {}
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isUnread = item['read_at'] == null;
                        return ActivityNotificationTile(
                          title: item['title']?.toString().trim().isNotEmpty ==
                                  true
                              ? item['title'].toString()
                              : t('alerts'),
                          body: item['body']?.toString() ?? '',
                          icon: item['notification_type'] == 'new_message'
                              ? AppIcons.chat
                              : AppIcons.notifications,
                          unread: isUnread,
                          unreadLabel: t('ui_notification_unread'),
                          busy: _openingId == item['id'].toString(),
                          onTap: _openingId == null
                              ? () => openNotification(item)
                              : null,
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage>
    with AccountFeedState<AlertsPage> {
  late Future<_ActivityRowsResult> alerts;
  String? _openingId;

  @override
  void reloadAccountFeed() {
    alerts = loadAlerts();
    _openingId = null;
  }

  @override
  void initState() {
    super.initState();
    alerts = loadAlerts();
  }

  Future<_ActivityRowsResult> loadAlerts() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get('activity/car-alerts');
      if (!accountMatches(userId, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } on BackendApiException catch (error) {
      debugPrint('loadAlerts failed: ${error.statusCode ?? 0}');
      return const _ActivityRowsResult.failed();
    } on PostgrestException catch (error) {
      debugPrint('loadAlerts failed: ${error.code ?? 'unknown code'}');
      return _ActivityRowsResult.failed(errorCode: error.code);
    } catch (error) {
      debugPrint('loadAlerts failed: ${error.runtimeType}');
      return const _ActivityRowsResult.failed();
    }
  }

  Future<void> _refresh() async {
    final next = loadAlerts();
    setState(() {
      alerts = next;
    });
    await next;
  }

  Future<void> openAlert(Map<String, dynamic> alert) async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null ||
        !accountMatches(userId, epoch) ||
        _openingId != null) {
      return;
    }
    setState(() {
      _openingId = alert['id'].toString();
    });
    try {
      final carId = alert['car_id']?.toString().trim() ?? '';
      final carResponse = carId.isEmpty
          ? null
          : await backendApi.get(
              'cars/by-ids',
              query: {'ids': carId},
            );
      final carRows = carResponse is Map && carResponse['data'] is List
          ? carResponse['data'] as List
          : const <dynamic>[];
      final car = carRows.isEmpty ? null : carRows.first;
      if (!mounted || !accountMatches(userId, epoch)) return;
      var readFailed = false;
      if (alert['read_at'] == null && alert['id'] != null) {
        try {
          final updated = await backendApi.patch(
            'activity/car-alerts/${alert['id']}/read',
          );
          readFailed = updated is! Map || updated['data'] is! Map;
        } catch (_) {
          readFailed = true;
        }
      }
      if (!mounted || !accountMatches(userId, epoch)) return;
      if (car != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CarDetailsPage(car: Map<String, dynamic>.from(car)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('ad_unavailable'))));
      }
      if (!mounted || !accountMatches(userId, epoch)) return;
      if (readFailed) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('ui_alert_read_failed'))));
      }
      await _refresh();
    } catch (_) {
      if (mounted && accountMatches(userId, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('alerts_open_failed'))));
      }
    } finally {
      if (mounted && accountMatches(userId, epoch)) {
        setState(() {
          _openingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_car_alerts')),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: t('account_received_offers'),
              icon: const Icon(AppIcons.offer),
              onPressed: () {
                final userId = _authenticatedUserId;
                if (userId == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerProfilePage(
                      sellerId: userId,
                      sellerName: _backendDisplayName(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: _authenticatedUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: alerts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    final code = snapshot.data?.errorCode;
                    return AppStateView(
                      title: t('ui_load_error_title'),
                      message: [
                        t('ui_load_error_body'),
                        if (code != null)
                          '${t('ui_backend_error_code')}: $code',
                      ].join('\n'),
                      icon: AppIcons.cloudOff,
                      isError: true,
                      actionLabel: t('ui_retry'),
                      onAction: _refresh,
                    );
                  }
                  final items = snapshot.data?.rows ?? [];
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: items.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: AppStateView(
                                    title: t('alerts_empty'),
                                    icon: AppIcons.notifications,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final alert = items[index];
                              final title = [alert['brand'], alert['model']]
                                  .where((value) => value != null)
                                  .map((value) => value.toString().trim())
                                  .where((value) => value.isNotEmpty)
                                  .join(' ');
                              final location = [
                                alert['province'],
                                alert['city']
                              ]
                                  .where((value) => value != null)
                                  .map((value) => value.toString().trim())
                                  .where((value) => value.isNotEmpty)
                                  .join(' • ');
                              return ActivityNotificationTile(
                                title: title.isEmpty
                                    ? t('alerts_new_match')
                                    : title,
                                body: location,
                                detail: alert['price'] == null
                                    ? null
                                    : formatPriceDisplay(
                                        alert['price'].toString(),
                                      ),
                                icon: AppIcons.notifications,
                                unread: alert['read_at'] == null,
                                unreadLabel: t('ui_notification_unread'),
                                busy: _openingId == alert['id'].toString(),
                                onTap: _openingId == null
                                    ? () => openAlert(alert)
                                    : null,
                              );
                            },
                          ),
                  );
                },
              ),
      ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfileResult {
  const _UserProfileResult(this.data, {this.failed = false});
  final Map<String, dynamic> data;
  final bool failed;
}

class _UserProfilePageState extends State<UserProfilePage>
    with AccountFeedState<UserProfilePage> {
  String? get _profileUserId =>
      backendAuthSession.user?.id ?? supabaseClientOrNull?.auth.currentUser?.id;

  String? get _profileUserEmail =>
      backendAuthSession.user?.email ??
      supabaseClientOrNull?.auth.currentUser?.email;

  @override
  void reloadAccountFeed() {
    profileData = loadProfile();
  }

  late Future<_UserProfileResult> profileData;
  bool _signingOut = false;
  @override
  void initState() {
    super.initState();
    profileData = loadProfile();
  }

  Future<_UserProfileResult> loadProfile() async {
    final userId = _profileUserId;
    final userEmail = _profileUserEmail;
    final epoch = accountEpoch;
    if (userId == null) return const _UserProfileResult({});
    try {
      final response = await backendApi.get('profile/me');
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! Map) {
        return _UserProfileResult({}, failed: true);
      }
      final row = Map<String, dynamic>.from(response['data'] as Map);
      if (row['id']?.toString() != userId) {
        return const _UserProfileResult({}, failed: true);
      }
      if (!accountMatches(userId, epoch)) {
        return const _UserProfileResult({});
      }
      final displayName =
          (row['display_name']?.toString().trim().isNotEmpty == true)
              ? row['display_name'].toString().trim()
              : (row['username']?.toString().trim().isNotEmpty == true)
                  ? row['username'].toString().trim()
                  : (row['email']?.toString().trim().isNotEmpty == true)
                      ? row['email'].toString().trim()
                      : t('default_member_name');
      return _UserProfileResult({
        'username': displayName,
        'email': row['email']?.toString() ?? userEmail ?? '',
        'avatar_url': row['avatar_url']?.toString(),
      });
    } catch (_) {
      return const _UserProfileResult({}, failed: true);
    }
  }

  Future<void> refresh() async {
    final next = loadProfile();
    setState(() {
      profileData = next;
    });
    await next;
  }

  Future<void> signOut() async {
    final actor = _profileUserId;
    final epoch = accountEpoch;
    if (_signingOut || actor == null) return;
    setState(() => _signingOut = true);
    try {
      try {
        if (backendAuthSession.user != null) {
          await backendAuthSession.logout();
        }
      } finally {
        if (supabaseClientOrNull?.auth.currentUser != null) {
          await supabase.auth.signOut();
        }
      }
      trustCache.reset();
      if (mounted && _profileUserId == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      if (mounted && accountMatches(actor, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('ui_signout_failed'))));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Widget option(IconData icon, String title, Widget page) =>
      AccountNavigationTile(
        icon: icon,
        title: title,
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_title'))),
        body: _profileUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_UserProfileResult>(
                future: profileData,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.data?.failed == true || snapshot.hasError) {
                    return _loadError(refresh);
                  }
                  final data = snapshot.data?.data ?? {};
                  final username =
                      data['username']?.toString() ?? t('default_member_name');
                  final email = data['email']?.toString() ?? '';
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(
                                  AppIcons.account,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Semantics(
                                header: true,
                                child: Text(
                                  t('ui_profile_greeting')
                                      .replaceAll('{name}', username),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (email.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  email,
                                  textDirection: TextDirection.ltr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        FormSectionHeading(
                          title: t('account_quick_actions'),
                          icon: AppIcons.account,
                        ),
                        option(
                          AppIcons.favorite,
                          t('account_favorites'),
                          const FavoritesPage(),
                        ),
                        option(
                          AppIcons.following,
                          t('account_follows'),
                          const MyFollowsPage(),
                        ),
                        option(
                          AppIcons.campaign,
                          t('account_my_ads'),
                          const MyAdsPage(),
                        ),
                        option(
                          AppIcons.chat,
                          t('account_messages'),
                          const MyMessagesPage(),
                        ),
                        option(
                          AppIcons.reviews,
                          t('account_reviews'),
                          const MyReviewsPage(),
                        ),
                        const SizedBox(height: 12),
                        option(
                          AppIcons.settings,
                          t('settings_title'),
                          const SettingsPage(),
                        ),
                        AccountNavigationTile(
                          icon: AppIcons.logout,
                          title: _signingOut
                              ? t('common_loading_dots')
                              : t('account_sign_out'),
                          danger: true,
                          onTap: _signingOut ? null : signOut,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class MyFollowsPage extends StatefulWidget {
  const MyFollowsPage({super.key});

  @override
  State<MyFollowsPage> createState() => _MyFollowsPageState();
}

class _MyFollowsPageState extends State<MyFollowsPage>
    with AccountFeedState<MyFollowsPage> {
  late Future<_ActivityRowsResult> follows;
  bool _opening = false;

  @override
  void reloadAccountFeed() {
    follows = loadFollows();
    _opening = false;
  }

  @override
  void initState() {
    super.initState();
    follows = loadFollows();
  }

  Future<_ActivityRowsResult> loadFollows() async {
    final user = supabase.auth.currentUser;
    final epoch = accountEpoch;
    if (user == null) return const _ActivityRowsResult.ready([]);
    try {
      final data = await supabase
          .from('user_follows')
          .select()
          .eq('follower_id', user.id)
          .order('created_at', ascending: false);
      if (!accountMatches(user.id, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      final rows = List<Map<String, dynamic>>.from(data);
      final ids = rows
          .map((row) => row['followed_id']?.toString().trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id,full_name')
              .inFilter('id', ids);
          final names = {
            for (final profile in profiles)
              profile['id']?.toString(): profile['full_name']?.toString(),
          };
          for (final row in rows) {
            row['seller_name'] = names[row['followed_id']?.toString().trim()];
          }
        } catch (_) {
          // A missing public name must not hide a followed seller.
        }
      }
      if (!accountMatches(user.id, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      return _ActivityRowsResult.ready(rows);
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  Future<void> _refresh() async {
    final next = loadFollows();
    setState(() {
      follows = next;
    });
    await next;
  }

  String _name(Map<String, dynamic> row) {
    final name = row['seller_name']?.toString().trim() ?? '';
    return name.isEmpty ? t('default_seller_name') : name;
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = row['followed_id']?.toString().trim() ?? '';
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (_opening || id.isEmpty || !accountMatches(actor, epoch)) return;
    _opening = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SellerProfilePage(sellerId: id, sellerName: _name(row)),
        ),
      );
      if (accountMatches(actor, epoch)) await _refresh();
    } finally {
      if (accountEpoch == epoch) _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_follows'))),
        body: supabase.auth.currentUser == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: follows,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(_refresh);
                  }
                  final list = snapshot.data?.rows ?? [];
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: list.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: AppStateView(
                                    title: t('account_not_following'),
                                    icon: AppIcons.following,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final row = list[index];
                              final date = DateTime.tryParse(
                                row['created_at']?.toString() ?? '',
                              );
                              final id =
                                  row['followed_id']?.toString().trim() ?? '';
                              final scheme = Theme.of(context).colorScheme;
                              return Material(
                                color: scheme.surface,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                  side: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsetsDirectional.fromSTEB(
                                    14,
                                    8,
                                    12,
                                    8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: scheme.primaryContainer,
                                    child: Icon(
                                      AppIcons.following,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  title: Text(
                                    _name(row),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: date == null
                                      ? null
                                      : Text(
                                          t('ui_followed_since').replaceAll(
                                            '{date}',
                                            MaterialLocalizations.of(
                                              context,
                                            ).formatMediumDate(date.toLocal()),
                                          ),
                                        ),
                                  trailing: id.isEmpty
                                      ? null
                                      : Icon(AppIcons.disclosure),
                                  onTap: id.isEmpty ? null : () => _open(row),
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
      ),
    );
  }
}

class MyMessagesPage extends StatefulWidget {
  const MyMessagesPage({super.key});

  @override
  State<MyMessagesPage> createState() => _MyMessagesPageState();
}

class _MyMessagesPageState extends State<MyMessagesPage>
    with AccountFeedState<MyMessagesPage> {
  late Future<_ActivityRowsResult> conversations;

  @override
  void reloadAccountFeed() {
    conversations = loadConversations();
  }

  @override
  void initState() {
    super.initState();
    conversations = loadConversations();
  }

  Future<_ActivityRowsResult> loadConversations() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get('offers/conversations');
      if (!accountMatches(userId, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_messages'))),
        body: _authenticatedUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: conversations,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(
                      () => setState(() {
                        conversations = loadConversations();
                      }),
                    );
                  }
                  final list = snapshot.data?.rows ?? [];
                  if (list.isEmpty) {
                    return AppStateView(
                      title: t('chat_empty'),
                      icon: AppIcons.chat,
                      actionLabel: t('alerts_update'),
                      onAction: () => setState(() {
                        conversations = loadConversations();
                      }),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final pending = loadConversations();
                      setState(() {
                        conversations = pending;
                      });
                      await pending;
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conv = list[index];
                        final embedded = conv['car_offer_messages'];
                        final latest = embedded is List &&
                                embedded.isNotEmpty &&
                                embedded.first is Map
                            ? embedded.first as Map
                            : null;
                        final amount = conv['offer_price']?.toString() ?? '';
                        return ActivityNotificationTile(
                          title:
                              conv['car_title']?.toString().trim().isNotEmpty ==
                                      true
                                  ? conv['car_title'].toString()
                                  : t('car_word'),
                          body: latest?['body']?.toString() ?? t('chat_start'),
                          bodyMaxLines: 3,
                          detail: amount.isEmpty
                              ? null
                              : t('ui_conversation_offer_amount').replaceAll(
                                  '{amount}',
                                  parseFormDecimal(amount) == null
                                      ? amount
                                      : formatIqdOnly(
                                          parseFormDecimal(amount)!,
                                        ),
                                ),
                          icon: AppIcons.chat,
                          unread: false,
                          unreadLabel: '',
                          onTap: () async {
                            final actor = _authenticatedUserId;
                            final epoch = accountEpoch;
                            if (!accountMatches(actor, epoch)) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CarOfferChatPage(offer: conv),
                              ),
                            );
                            if (mounted && accountMatches(actor, epoch)) {
                              setState(() {
                                conversations = loadConversations();
                              });
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class MyReviewsPage extends StatefulWidget {
  const MyReviewsPage({super.key});

  @override
  State<MyReviewsPage> createState() => _MyReviewsPageState();
}

class _MyReviewsPageState extends State<MyReviewsPage>
    with AccountFeedState<MyReviewsPage> {
  late Future<_ActivityRowsResult> reviews;

  @override
  void reloadAccountFeed() {
    reviews = loadReviews();
  }

  @override
  void initState() {
    super.initState();
    reviews = loadReviews();
  }

  Future<_ActivityRowsResult> loadReviews() async {
    final userId = _authenticatedUserId;
    final epoch = accountEpoch;
    if (userId == null) return const _ActivityRowsResult.ready([]);
    try {
      final response = await backendApi.get(
        'sellers/reviews',
        query: {'reviewer': 'me'},
      );
      if (!accountMatches(userId, epoch)) {
        return const _ActivityRowsResult.ready([]);
      }
      if (response is! Map || response['data'] is! List) {
        return const _ActivityRowsResult.failed();
      }
      return _ActivityRowsResult.ready(
        List<Map<String, dynamic>>.from(response['data'] as List),
      );
    } catch (_) {
      return const _ActivityRowsResult.failed();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_reviews'))),
        body: _authenticatedUserId == null
            ? AppStateView(
                title: t('login_required_first'),
                icon: AppIcons.locked,
              )
            : FutureBuilder<_ActivityRowsResult>(
                future: reviews,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return AppLoadingView(label: t('ui_loading_title'));
                  }
                  if (snapshot.hasError || snapshot.data?.failed == true) {
                    return _loadError(
                      () => setState(() {
                        reviews = loadReviews();
                      }),
                    );
                  }
                  final list = snapshot.data?.rows ?? [];
                  if (list.isEmpty) {
                    return AppStateView(
                      title: t('account_no_reviews'),
                      actionLabel: t('alerts_update'),
                      onAction: () => setState(() {
                        reviews = loadReviews();
                      }),
                      icon: AppIcons.reviews,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final pending = loadReviews();
                      setState(() {
                        reviews = pending;
                      });
                      await pending;
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final review = list[index];
                        final rating =
                            (review['rating'] as num?)?.toDouble() ?? 0.0;
                        final comment = review['comment']?.toString() ?? '';
                        final sellerName = review['seller_name']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true
                            ? review['seller_name'].toString()
                            : t('default_seller_name');
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sellerName,
                                textDirection: contentTextDirection(
                                  context,
                                  sellerName,
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$rating/5',
                                    textDirection: TextDirection.ltr,
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                ],
                              ),
                              if (comment.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  comment,
                                  textDirection: contentTextDirection(
                                    context,
                                    comment,
                                  ),
                                  style: TextStyle(color: AppColors.textStrong),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.preferencesLoader});
  final Future<SharedPreferences> Function()? preferencesLoader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool pushNotifications = true;
  bool emailNotifications = true;

  int _preferenceRevision = 0;
  bool _preferencesFailed = false;
  bool _preferencesLoading = false;
  final _savingPreferences = <String>{};

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    if (_preferencesLoading || _savingPreferences.isNotEmpty) return;
    setState(() {
      _preferencesLoading = true;
    });
    final revision = _preferenceRevision;
    try {
      final prefs =
          await (widget.preferencesLoader ?? SharedPreferences.getInstance)();
      if (!mounted || _preferenceRevision != revision) return;
      setState(() {
        _preferencesFailed = false;
        pushNotifications = prefs.getBool('motri.notifications.push') ?? true;
        emailNotifications = prefs.getBool('motri.notifications.email') ?? true;
      });
    } catch (_) {
      if (mounted && _preferenceRevision == revision) {
        setState(() {
          _preferencesFailed = true;
        });
      }
    } finally {
      if (mounted && _preferenceRevision == revision) {
        setState(() {
          _preferencesLoading = false;
        });
      }
    }
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    if (_preferencesLoading || _savingPreferences.contains(key)) return;
    final previous = key == 'push' ? pushNotifications : emailNotifications;
    _preferenceRevision++;
    setState(() {
      _savingPreferences.add(key);
      if (key == 'push') {
        pushNotifications = value;
      } else {
        emailNotifications = value;
      }
    });
    try {
      final prefs =
          await (widget.preferencesLoader ?? SharedPreferences.getInstance)();
      if (!await prefs.setBool('motri.notifications.$key', value)) {
        throw StateError('Preference save failed');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (key == 'push') {
            pushNotifications = previous;
          } else {
            emailNotifications = previous;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('ui_settings_save_failed'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingPreferences.remove(key);
        });
      }
    }
  }

  Widget _settingToggle(
    String title,
    IconData icon,
    bool value,
    void Function(bool)? onChanged,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 8, 12, 8),
          secondary: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
          ),
          title: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('settings_title'))),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_preferencesLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (_preferencesFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppStatePanel(
                  title: t('ui_load_error_title'),
                  icon: AppIcons.cloudOff,
                  isError: true,
                  actionLabel: t('ui_retry'),
                  onAction: _loadNotificationPreferences,
                ),
              ),
            _settingToggle(
              t('settings_push_notifications'),
              AppIcons.notifications,
              pushNotifications,
              (_preferencesLoading || _savingPreferences.contains('push'))
                  ? null
                  : (v) {
                      _saveNotificationPreference('push', v);
                    },
            ),
            _settingToggle(
              t('settings_email_notifications'),
              Icons.mail_outline_rounded,
              emailNotifications,
              (_preferencesLoading || _savingPreferences.contains('email'))
                  ? null
                  : (v) {
                      _saveNotificationPreference('email', v);
                    },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
              child: Text(
                t('ui_notification_preferences_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const AdPrivacyOptionsButton(),
            _settingToggle(
              t('settings_dark_mode'),
              Icons.dark_mode_rounded,
              AppColors.isDark,
              (v) {
                setDarkMode(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 20),
            AccountNavigationTile(
              icon: Icons.info_outline_rounded,
              title: t('settings_about'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة «عن التطبيق».
///
/// أرقام الإصدار ورقم البناء **لا تُكتب هنا إطلاقًا**: تُقرأ من إعدادات
/// البناء عبر [PackageInfo.fromPlatform]، التي يملؤها Flutter من
/// `version:` في `pubspec.yaml`. فأي تعديل على `pubspec.yaml` ينعكس على هذه
/// الصفحة وحده، ولا سبيل لأن يتفرّق رقمٌ عن المصدر.
///
/// [infoLoader] للاختبار فقط: `PackageInfo` يقرأ من قناة المنصّة، وهي غير
/// موجودة داخل `flutter test`، فمرّرنا مصدرًا بديلًا يُغلق الاختبار.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.infoLoader});

  final Future<PackageInfo> Function()? infoLoader;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    PackageInfo? info;
    try {
      info = await (widget.infoLoader ?? PackageInfo.fromPlatform)();
    } catch (_) {
      // لا قناة منصّة (اختبار، أو نظام لا يوفّرها): نعرض «غير متوفر»
      // بدل رقم مخترَع يوهم بتواجده.
      info = null;
    }
    if (!mounted) return;
    setState(() => _info = info);
  }

  /// القيمة المعروضة، أو نصّ صراحة بدل قيمة فارغة.
  ///
  /// بعض المنصّات ترجع `buildNumber` فارغًا؛ الفارغ يُعرض كـ«غير متوفر»
  /// حتى لا يقرأ المستخدم سطرًا ناقصًا كأنه رقم بناء.
  String _valueOf(String? raw) {
    final String value = raw?.trim() ?? '';
    return value.isEmpty ? t('about_version_unknown') : value;
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textStrong,
        ),
      );

  /// بطاقة بمظهر صفحات التطبيق: `card` وحدّ 17 وظلّ خفيف.
  ///
  /// `Material` حول `ListTile` ليس زينة: Flutter يطلق تأكيدًا إن لُفّ
  /// `ListTile` ملوّن بـ`Container` وحده، لأن الحبر لا يجد سطحًا يرسم عليه.
  Widget _card(Widget child, {EdgeInsetsGeometry? padding}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(15),
          child: child,
        ),
      ),
    );
  }

  /// صف رابط. `onTap == null` يُعرض معطّلًا بشفافية تميّزه عن الروابط
  /// الفعلية بدل أن يبدو قابلًا للضغط فيفشل عند اللمس.
  Widget _linkRow({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;
    final Color ink = enabled ? AppColors.textStrong : AppColors.textFaint;
    return _card(
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: Icon(
          AppIcons.disclosure,
          color: enabled ? AppColors.textFaint : Colors.transparent,
        ),
        onTap: onTap,
      ),
    );
  }

  /// سطر «تسمية: قيمة».
  ///
  /// `Expanded` على التسمية تحديدًا: أسماء اللغات قد تطول، والقيمة رقمية
  /// قصيرة، فبلاهما في صفّ واحد يفيض واحدٌ منهما على شاشة 320 بكسل.
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
          ),
          // القيمة داخل `Directionality` لاتيني: رقم البناء قد يأتي من
          // أداة Flutter بصيغة لا يصحّ عرضها RTL، ونصّه لاتيني أصلًا.
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                value,
                style: TextStyle(
                  color: AppColors.textStrong,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('settings_about'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            // رأس الصفحة: الشعار ثم الاسم. الشعار هو `BrandLogo` نفسه،
            // فلا صورة مستوردة ولا لون جديد.
            _card(
              Column(
                children: [
                  const BrandLogo(size: 78),
                  const SizedBox(height: 12),
                  Text(
                    'MOTRI IQ',
                    style: TextStyle(
                      color: AppColors.textStrong,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _sectionTitle(t('about_section_about')),
            const SizedBox(height: 10),
            _card(
              Text(
                t('about_short_description'),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 18),

            _sectionTitle(t('about_version_label')),
            const SizedBox(height: 10),
            _card(
              Column(
                children: [
                  _infoRow(t('about_version_label'), _valueOf(_info?.version)),
                  Divider(height: 1, thickness: 1, color: AppColors.border),
                  _infoRow(
                    t('about_build_label'),
                    _valueOf(_info?.buildNumber),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _sectionTitle(t('about_section_links')),
            const SizedBox(height: 10),
            _linkRow(
              icon: Icons.privacy_tip_outlined,
              title: t('about_privacy_policy'),
              subtitle: t('about_click_to_read'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                );
              },
            ),
            _linkRow(
              icon: Icons.gavel_outlined,
              title: t('about_terms_of_use'),
              subtitle: t('about_click_to_read'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsOfUsePage()),
                );
              },
            ),
            // التواصل قناة موجودة فعلًا في المشروع: مركز الدعم ومنها
            // «التواصل مع الدعم»، فلا رقم ولا بريد يُكتب هنا من عندي.
            _linkRow(
              icon: AppIcons.support,
              title: t('about_contact_us'),
              subtitle: t('support_center_title'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportCenterPage()),
                );
              },
            ),
            const SizedBox(height: 18),

            Center(
              child: Text(
                // اسم علامة تجارية: يُكتب مباشرةً ولا يُترجَم، كما «MOTRI IQ»
                // في رأس الصفحة.
                '© MOTRI IQ',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SupportCenterPage extends StatefulWidget {
  const SupportCenterPage({super.key});

  @override
  State<SupportCenterPage> createState() => _SupportCenterPageState();
}

class _SupportCenterPageState extends State<SupportCenterPage> {
  bool _reporting = false;
  Widget _sectionTitle(String title) => Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _supportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: AppColors.textStrong,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          trailing: Icon(AppIcons.disclosure, color: AppColors.textFaint),
          onTap: onTap,
        ),
      ),
    );
  }

  Future<void> _reportProblem() async {
    if (_reporting) return;
    _reporting = true;
    try {
      final List<(String, String)> categories = <(String, String)>[
        ('support_issue_seller', 'support_issue_content'),
        ('support_issue_ad', 'misc_ad_support_note'),
        ('support_issue_account', 'support_issue_login'),
        ('support_issue_suggestion', 'support_issue_idea'),
      ];

      String? chosen = categories.first.$1;
      final TextEditingController details = TextEditingController();

      final bool? send = await showSettledDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return AlertDialog(
                scrollable: true,
                title: Text(t('support_report_problem')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioGroup<String>(
                      groupValue: chosen,
                      onChanged: (value) =>
                          setDialogState(() => chosen = value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (name, hint) in categories)
                            RadioListTile<String>(
                              value: name,
                              title: Text(t(name)),
                              subtitle: Text(t(hint)),
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ContentDirectionBuilder(
                      controller: details,
                      builder: (context, direction) => TextField(
                        controller: details,
                        minLines: 3,
                        maxLines: 5,
                        textDirection: direction,
                        decoration: InputDecoration(
                          labelText: t('support_issue_details'),
                          filled: true,
                          fillColor: panel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t('common_cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t('misc_follow')),
                  ),
                ],
              );
            },
          );
        },
      );

      if (send != true) {
        details.dispose();
        return;
      }

      final String body = details.text.trim();
      details.dispose();
      final String report =
          "${t('report_body_prefix').replaceAll(r'\n', '\n')}${t('support_issue_type')}: ${t(chosen ?? categories.first.$1)}\n${body.isEmpty ? t('report_no_details') : body}";
      if (!mounted) return;
      try {
        await SharePlus.instance.share(
          ShareParams(text: report, sharePositionOrigin: shareOrigin(context)),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t('ui_support_share_failed'))));
        }
      }
    } finally {
      _reporting = false;
    }
  }

  Future<void> _openSupportWhatsApp() async {
    await _launchSupport(supportWhatsAppUri(), 'misc_whatsapp_failed');
  }

  Future<void> _callSupport() async {
    await _launchSupport(supportCallUri(), 'misc_call_app_failed');
  }

  /// يفتح الرابط، ويبلّغ بصمت إن رفض الجهاز أو المتصفّح فتحه.
  ///
  /// `try/catch` حول `launchUrl` ضروري: `url_launcher` يرمي استثناءً على
  /// بعض الأجهزة حين لا يوجد تطبيق مقابل للمخطّط، وبلا هذا يُسقط الصفحة
  /// وسط الطريق.
  Future<void> _launchSupport(Uri uri, String failureKey) async {
    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(failureKey))));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(failureKey))));
    }
  }

  /// Choose a support channel in a scrollable sheet with adaptive actions.
  Future<void> _contactSupport() async {
    final String? failure = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('support_contact'),
                    style: TextStyle(
                      color: AppColors.textStrong,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // الرقم معروض كما هو، لا محوَّلًا: المستخدم يريد أن يتأكّد
                  // أنه يتصل بالمكان الصحيح قبل أن يضغط.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      kSupportPhone,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ResponsiveFormPair(
                    first: _supportAction(
                      icon: AppIcons.call,
                      label: t('settings_call'),
                      onTap: () => Navigator.pop(sheetContext, 'call'),
                    ),
                    second: _supportAction(
                      icon: AppIcons.chat,
                      label: t('contact_whatsapp'),
                      onTap: () => Navigator.pop(sheetContext, 'whatsapp'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || failure == null) return;
    if (failure == 'whatsapp') {
      await _openSupportWhatsApp();
    } else {
      await _callSupport();
    }
  }

  /// Content-sized actions preserve long localized labels.
  Widget _supportAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('support_center_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            _sectionTitle(t('ui_support_heading')),
            const SizedBox(height: 12),
            Text(
              t('support_help_intro'),
              style: TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 22),
            _sectionTitle(t('support_get_help')),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.shadow,
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _helpLine(Icons.flag_outlined, t('support_step_report')),
                  _helpLine(
                    Icons.directions_car_filled_outlined,
                    t('support_step_myads'),
                  ),
                  _helpLine(
                    Icons.chat_bubble_outline_rounded,
                    t('support_step_contact'),
                  ),
                  _helpLine(
                    Icons.person_outline_rounded,
                    t('support_q_account_help'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _sectionTitle(t('support_faq')),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: card,
                borderRadius: BorderRadius.circular(17),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (int i = 0; i < _faq.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.border,
                        ),
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            15,
                            0,
                            15,
                            14,
                          ),
                          iconColor:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          collapsedIconColor: AppColors.textFaint,
                          title: Text(
                            _faq[i].$1,
                            style: TextStyle(
                              color: AppColors.textStrong,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                _faq[i].$2,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _sectionTitle(t('support_report_problem')),
            const SizedBox(height: 12),
            _supportOption(
              icon: Icons.report_problem_outlined,
              title: t('support_report_problem'),
              subtitle: t('support_contact_desc'),
              onTap: _reportProblem,
            ),
            const SizedBox(height: 14),
            _sectionTitle(t('support_contact')),
            const SizedBox(height: 12),
            _supportOption(
              icon: AppIcons.support,
              title: t('support_contact'),
              subtitle: t('support_a_messages'),
              onTap: _contactSupport,
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> get _faq => <(String, String)>[
        (t('support_q_publish'), t('support_a_publish')),
        (t('support_q_save'), t('support_a_save')),
        (t('support_q_contact'), t('support_tip_contact')),
        (t('support_q_report'), t('support_tip_report')),
        (t('support_q_my_ads'), t('support_a_my_ads')),
        (t('support_q_missing'), t('support_tip_missing')),
      ];
}

class AccountTab extends StatefulWidget {
  const AccountTab({super.key});
  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final email = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  bool login = true;
  bool loading = false;
  bool phoneLoading = false;
  final _authForm = GlobalKey<FormState>();
  final _phoneField = GlobalKey<FormFieldState<String>>();
  bool _attemptedAuth = false,
      _attemptedPhone = false,
      _signingOut = false,
      _usernameBusy = false;
  String? _authErrorKey, _authNoticeKey;
  AppLocale? _validatedLocale;
  AuthCapabilitiesResult? _capabilities;
  bool _capabilitiesRequested = false, _checkingCapabilities = false;
  bool _savingCarGridLayout = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_capabilitiesRequested) {
      _capabilitiesRequested = true;
      unawaited(_loadCapabilities());
    }
  }

  Future<void> _loadCapabilities() async {
    if (_checkingCapabilities) return;
    setState(() => _checkingCapabilities = true);
    AuthCapabilitiesResult result;
    try {
      if (kMotriLocalTest) {
        result = const AuthCapabilitiesResult.ready(
          AuthCapabilities(phoneOtpEnabled: false, emailEnabled: true),
        );
      } else {
        result = await (AuthCapabilitiesScope.maybeOf(context)?.call() ??
            fetchAuthCapabilities(
              baseUrl: supabaseUrl,
              publishableKey: supabaseAnonKey,
              client: _sharedHttpClient,
            ));
      }
    } catch (_) {
      result = const AuthCapabilitiesResult.failed();
    }
    if (mounted) {
      setState(() {
        _capabilities = result;
        _checkingCapabilities = false;
      });
    }
  }

  bool obscure = true;
  bool uploadingAvatar = false;

  late Future<bool> _isAdminFuture;
  String? _accountOwner;
  int _accountEpoch = 0;
  bool _chatHubOpen = false;
  VoidCallback? _backendAuthListener;

  @override
  void dispose() {
    final l = _backendAuthListener;
    if (l != null) backendAuthSession.removeListener(l);
    email.dispose();
    username.dispose();
    password.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _isAdminFuture = currentUserIsAdmin();
    _accountOwner = backendAuthSession.user?.id;
    void onAuthChange() {
      if (!mounted) return;
      setState(() {
        final next = backendAuthSession.user?.id;
        if (next != _accountOwner) {
          _accountOwner = next;
          _accountEpoch++;
          trustCache.reset();
        }
        _isAdminFuture = currentUserIsAdmin();
      });
    }

    backendAuthSession.addListener(onAuthChange);
    _backendAuthListener = onAuthChange;
  }

  Future<void> submit() async {
    if (loading || phoneLoading) return;
    setState(() {
      _attemptedAuth = true;
      _authErrorKey = null;
      _authNoticeKey = null;
    });
    if (_authForm.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() => loading = true);
    try {
      final loginIdentifier = email.text.trim();
      if (login) {
        await backendAuthSession.login(
          identifier: loginIdentifier,
          password: password.text,
        );
        trustCache.reset();
        password.clear();
        _msg(t('login_success'));
      } else {
        final data = await backendAuthSession.register(
          email: loginIdentifier,
          password: password.text,
          fullName: name.text.trim(),
          username: username.text.trim().toLowerCase(),
        );
        password.clear();
        if (data['requires_email_confirmation'] == true && mounted) {
          setState(() {
            login = true;
            _attemptedAuth = false;
            _authNoticeKey = 'login_account_created_mail';
          });
        } else {
          trustCache.reset();
          _msg(t('login_account_created'));
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(
          () => _authErrorKey = authFeedbackKey(
            error,
            fallback: login ? 'ui_auth_failed' : 'ui_auth_signup_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> chooseUsername() async {
    if (_usernameBusy) return;
    _usernameBusy = true;
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UsernameEditorDialog(onSave: (normalized) async {
          await backendApi.post('profile/username',
              body: {'username': normalized}, backendOnly: true);
        }),
      );
      if (saved == true && mounted) _msg(t('misc_username_saved'));
    } finally {
      _usernameBusy = false;
    }
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await backendAuthSession.logout();
      trustCache.reset();
      password.clear();
    } catch (_) {
      // Best-effort local cleanup; session state comes from backendAuthSession.
      trustCache.reset();
      password.clear();
      _msg(t('ui_signout_failed'));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _saveCarGridLayout(bool enabled) async {
    if (_savingCarGridLayout) return;
    setState(() => _savingCarGridLayout = true);
    try {
      await setCarGridLayout(enabled);
    } catch (error) {
      debugPrint('Could not save car layout preference: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('ui_settings_save_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCarGridLayout = false);
    }
  }

  Widget _carGridLayoutPreference() => ValueListenableBuilder<bool>(
        valueListenable: carGridLayoutNotifier,
        builder: (context, isGrid, _) => Card(
          key: const ValueKey('profile_car_grid_layout'),
          margin: const EdgeInsets.only(bottom: 12),
          child: SwitchListTile.adaptive(
            secondary: Icon(
              isGrid ? Icons.grid_view_rounded : Icons.view_list_rounded,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            title: Text(t('profile_grid_layout')),
            subtitle: Text(t('profile_grid_layout_hint')),
            value: isGrid,
            onChanged: _savingCarGridLayout
                ? null
                : (enabled) => _saveCarGridLayout(enabled),
          ),
        ),
      );

  Future<void> submitPhoneLogin() async {
    // Independent auth (Neon) does not provide SMS OTP; keep Supabase bridge only for this legacy flow.
    if (loading || phoneLoading) return;
    if (_capabilities?.value?.phoneOtpEnabled != true) {
      _msg(t('ui_phone_unavailable'));
      return;
    }
    setState(() => _attemptedPhone = true);
    if (_phoneField.currentState?.validate() != true) return;
    final normalized = iraqiMobileNumber(phone.text)!;
    FocusScope.of(context).unfocus();
    setState(() => phoneLoading = true);
    try {
      await supabase.auth.signInWithOtp(phone: normalized);
      if (!mounted) return;
      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Directionality(
          textDirection: appLocale.direction,
          child: OtpVerificationDialog(
            phoneNumber: normalized,
            title: t('login_otp_title'),
            message: t('login_otp_sent'),
            phoneLabel: t('login_phone_label'),
            codeLabel: t('ui_otp_code_label'),
            invalidCode: t('ui_otp_six_digits'),
            cancelLabel: t('common_cancel'),
            verifyLabel: t('login_verify'),
            errorLabel: (error) =>
                t(authFeedbackKey(error, fallback: 'login_otp_verify_failed')),
            onVerify: (code) async {
              final response = await supabase.auth.verifyOTP(
                phone: normalized,
                token: code,
                type: OtpType.sms,
              );
              if (response.session == null) throw const AuthException('');
            },
          ),
        ),
      );
      if (verified == true) {
        password.clear();
        _msg(t('login_success'));
      }
    } catch (error) {
      _msg(t(authFeedbackKey(error, fallback: 'login_otp_send_failed')));
    } finally {
      if (mounted) setState(() => phoneLoading = false);
    }
  }

  void _msg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: appLocale.direction),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    if (_validatedLocale != appLocale) {
      final hadLocale = _validatedLocale != null;
      _validatedLocale = appLocale;
      if (hadLocale) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_attemptedAuth) _authForm.currentState?.validate();
          if (_attemptedPhone) _phoneField.currentState?.validate();
        });
      }
    }
    final hasBackendSession = backendAuthSession.isAuthenticated;
    final supaUser = supabaseClientOrNull?.auth.currentUser;
    if (hasBackendSession || supaUser != null) {
      // Ensure profile data is loaded for display (best-effort, no loops).
      final bu = backendAuthSession.user;
      if (hasBackendSession &&
          bu != null &&
          bu.fullName == null &&
          bu.username == null) {
        unawaited(backendAuthSession.loadProfile().catchError((_) {}));
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          _profileHeader(supaUser),
          const SizedBox(height: 18),
          _sectionTitle(t('account_quick_actions')),
          const SizedBox(height: 12),
          _quickActionsGrid(),
          const SizedBox(height: 26),
          _sectionTitle(t('account_options')),
          const SizedBox(height: 12),
          _accountRow(
            AppIcons.notifications,
            t('settings_push_notifications'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          _carGridLayoutPreference(),
          _accountRow(
            AppIcons.receipt,
            t('account_fines'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FinesPage()),
              );
            },
          ),
          _accountRow(
            AppIcons.history,
            t('account_search_history'),
            onTap: () async {
              final query = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const SearchHistoryPage()),
              );
              if (!mounted || !context.mounted || query == null) return;
              final home = context.findAncestorStateOfType<_HomePageState>();
              if (home != null) {
                home._replaySavedSearch(query);
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(t('nav_search'))),
                      body: SearchTab(initialQuery: query),
                    ),
                  ),
                );
              }
            },
          ),
          _accountRow(
            AppIcons.support,
            t('account_support_center'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportCenterPage()),
              );
            },
          ),
          _accountRow(
            AppIcons.settings,
            t('account_settings'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          _accountRow(
            Icons.delete_forever,
            'حذف الحساب',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف الحساب'),
                  content: const Text(
                      'سيتم حذف حسابك وبياناتك نهائياً. هل أنت متأكد؟'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حذف')),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await backendApi.delete('account');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حذف الحساب')));
                  }
                } catch (_) {}
              }
            },
          ),
          _accountRow(
            AppIcons.language,
            t('account_language'),
            onTap: _openLanguagePicker,
          ),
          const SizedBox(height: 24),
          _sectionTitle(t('account_more_options')),
          const SizedBox(height: 12),
          _accountRow(
            Icons.alternate_email,
            t('account_username_login'),
            onTap: chooseUsername,
          ),
          _accountRow(
            AppIcons.account,
            t('account_seller_profile'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SellerProfilePage(
                    sellerId: backendAuthSession.user?.id ?? supaUser?.id ?? '',
                    sellerName: _backendDisplayName(),
                  ),
                ),
              );
            },
          ),
          _accountRow(
            Icons.storefront_rounded,
            t('account_showroom_setup'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageShowroomPage()),
              );
            },
          ),
          if (!restrictPaidFeatures)
            _accountRow(
              AppIcons.campaign,
              t('account_my_ads'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyAdsPage()),
                );
              },
            ),
          _accountRow(
            AppIcons.offer,
            t('account_received_offers'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SellerProfilePage(
                    sellerId: backendAuthSession.user?.id ?? supaUser?.id ?? '',
                    sellerName: _backendDisplayName(),
                  ),
                ),
              );
            },
          ),
          _accountRow(
            AppIcons.offer,
            t('account_my_car_offers'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MySentOffersPage()),
              );
            },
          ),
          _accountRow(
            AppIcons.notifications,
            t('account_car_alerts'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertsPage()),
              );
            },
          ),
          _accountRow(
            AppIcons.campaign,
            t('account_advertise_with_us'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateBusinessAdPage()),
              );
            },
          ),
          if (!restrictPaidFeatures)
            _accountRow(
              Icons.storefront_outlined,
              t('account_business_ads'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BusinessAdsPage()),
                );
              },
            ),
          FutureBuilder<bool>(
            future: _isAdminFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return _accountRow(
                Icons.admin_panel_settings_outlined,
                t('account_admin_panel'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardPage(),
                    ),
                  );
                },
              );
            },
          ),
          _accountRow(
            AppIcons.logout,
            _signingOut ? t('common_loading_dots') : t('account_sign_out'),
            danger: true,
            onTap: _signingOut ? null : signOut,
          ),
        ],
      );
    }
    return _guestForm();
  }

  Widget _guestForm() {
    final theme = Theme.of(context);
    final busy = loading || phoneLoading;
    return ListView(
      key: const ValueKey('account_guest'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: t('account_language'),
              onPressed: _openLanguagePicker,
              icon: const Icon(AppIcons.language),
            ),
            IconButton(
              tooltip: t('settings_title'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              icon: const Icon(AppIcons.settings),
            ),
            IconButton(
              tooltip: t('account_support_center'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportCenterPage()),
              ),
              icon: const Icon(AppIcons.support),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Center(child: BrandLogo(size: 72)),
        _carGridLayoutPreference(),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            login ? t('login_title') : t('register_title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          login ? t('login_subtitle') : t('register_subtitle'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
                  key: _authForm,
                  autovalidateMode: _attemptedAuth
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!login) ...[
                        _field(name, t('login_display_name'), AppIcons.account),
                        const SizedBox(height: 16),
                        _field(
                          username,
                          t('login_username'),
                          Icons.alternate_email_rounded,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _field(
                        email,
                        login ? t('ui_login_identifier') : t('login_email'),
                        Icons.mail_outline_rounded,
                        keyboard: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('auth_password'),
                        controller: password,
                        enabled: !busy,
                        obscureText: obscure,
                        textDirection: TextDirection.ltr,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: [
                          login
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        validator: (value) => (value ?? '').isEmpty
                            ? t('wanted')
                            : (value!.length < 6
                                ? t('login_password_too_short')
                                : null),
                        decoration: InputDecoration(
                          labelText: t('login_password'),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => obscure = !obscure),
                            tooltip: obscure
                                ? t('password_show')
                                : t('password_hide'),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_authErrorKey != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              t(_authErrorKey!),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ),
                      if (_authNoticeKey != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(t(_authNoticeKey!)),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('auth_submit'),
                        onPressed: busy ? null : submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                login ? t('login_title') : t('register_title'),
                                textAlign: TextAlign.center,
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  login = !login;
                                  obscure = true;
                                  _attemptedAuth = false;
                                  _authErrorKey = null;
                                  _authNoticeKey = null;
                                }),
                        child: Text(
                          login
                              ? t('login_no_account')
                              : t('login_have_account'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_capabilities?.value?.phoneOtpEnabled == true)
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: theme.colorScheme.outlineVariant),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          t('login_or'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: Divider(color: theme.colorScheme.outlineVariant),
                      ),
                    ],
                  )
                else
                  Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 20),
                _phoneOptions(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneOptions() {
    final theme = Theme.of(context);
    final busy = loading || phoneLoading;
    if (_checkingCapabilities) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(t('ui_auth_options_loading'))),
        ],
      );
    }
    final capabilities = _capabilities?.value;
    if (capabilities?.phoneOtpEnabled != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.call, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(
                    capabilities == null
                        ? 'ui_auth_options_failed'
                        : 'ui_phone_unavailable',
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t(
              capabilities?.emailEnabled == true
                  ? 'ui_phone_email_alternative'
                  : 'ui_auth_network',
            ),
            style: theme.textTheme.bodySmall,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _loadCapabilities,
              icon: const Icon(AppIcons.retry),
              label: Text(t('ui_retry')),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          phone,
          t('field_iraqi_phone'),
          AppIcons.call,
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const ValueKey('auth_phone_submit'),
          onPressed: busy ? null : submitPhoneLogin,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: phoneLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('login_otp_send'), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _accountRow(
    IconData icon,
    String title, {
    bool danger = false,
    Future<void> Function()? onTap,
  }) =>
      AccountNavigationTile(
        icon: icon,
        title: title,
        danger: danger,
        onTap: onTap,
      );

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.textStrong,
      ),
    );
  }

  String _avatarLetter(User? user) {
    final bu = backendAuthSession.user;
    final fullName = (bu?.fullName ?? bu?.username ?? '').trim().isNotEmpty
        ? (bu?.fullName ?? bu?.username ?? '').trim()
        : (user?.userMetadata?['full_name']?.toString().trim() ?? '');
    if (fullName.isNotEmpty) return fullName.characters.first;
    final mail = (bu?.email ?? user?.email ?? '').trim();
    if (mail.isNotEmpty) return mail.characters.first.toUpperCase();
    return t('login_question');
  }

  String _avatarUrl(User? user) {
    final value = user?.userMetadata?['avatar_url']?.toString().trim() ?? '';
    return value.isEmpty ? '' : value;
  }

  Future<void> _pickAndSaveAvatar(User? user) async {
    if (uploadingAvatar) return;
    final id = backendAuthSession.user?.id ?? user?.id;
    if (id == null) return;
    setState(() => uploadingAvatar = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final path = '$id/avatars/$fileName';
      await supabase.storage
          .from('cars')
          .uploadBinary(path, bytes, fileOptions: const FileOptions());
      final url = supabase.storage.from('cars').getPublicUrl(path);
      await supabase.auth.updateUser(UserAttributes(data: {'avatar_url': url}));
      if (mounted) {
        setState(() {});
        _msg(t('img_avatar_updated'));
      }
    } catch (e) {
      if (mounted) _msg(t('img_avatar_failed'));
    } finally {
      if (mounted) setState(() => uploadingAvatar = false);
    }
  }

  Widget _profileHeader(User? user) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final avatarUrl = _avatarUrl(user), letter = _avatarLetter(user);
    final bu = backendAuthSession.user;
    final fullName = (bu?.fullName ?? bu?.username ?? '').trim().isNotEmpty
        ? (bu?.fullName ?? bu?.username ?? '').trim()
        : (user?.userMetadata?['full_name']?.toString().trim() ?? '');
    final displayName = fullName.isEmpty ? t('default_member_name') : fullName;
    final phone = (bu?.phone ?? user?.phone ?? '').trim();
    final hasPhone = phone.isNotEmpty;
    final contact = hasPhone
        ? phone
        : ((bu?.email ?? user?.email ?? '').trim().isNotEmpty
            ? (bu?.email ?? user?.email ?? '').trim()
            : t('common_unavailable'));
    final avatar = Tooltip(
      message: t('ui_change_avatar'),
      child: Material(
        color: scheme.primaryContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: uploadingAvatar ? null : () => _pickAndSaveAvatar(user),
          child: Semantics(
            button: true,
            label: t('ui_change_avatar'),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(
                child: uploadingAvatar
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : avatarUrl.isNotEmpty
                        ? Image.network(
                            avatarUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              letter,
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        : Text(
                            letter,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
              ),
            ),
          ),
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            displayName,
            textDirection: contentTextDirection(context, displayName),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasPhone ? AppIcons.call : Icons.mail_outline_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                contact,
                textDirection: hasPhone ||
                        ((bu?.email ?? user?.email ?? '').trim().isNotEmpty)
                    ? TextDirection.ltr
                    : appLocale.direction,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 320 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [avatar, const SizedBox(height: 16), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 16),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openFavorites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesPage()),
    );
  }

  Future<void> _openLanguagePicker() async {
    final selected = await showModalBottomSheet<AppLocale>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LanguagePickerSheet(selected: appLocale),
    );
    if (!mounted || selected == null) return;
    await setAppLocale(selected);
  }

  Future<void> _openSellCar() async {
    final user = backendAuthSession.user ?? supabase.auth.currentUser;
    if (user == null) {
      _msg(t('misc_login_first_publish'));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCarTab()),
    );
  }

  Future<int> _loadUnreadOfferNotifications(String accountId) async {
    if (backendAuthSession.user?.id != accountId) return 0;
    final response = await backendApi.get(
      'activity/notifications',
      query: {'limit': '200'},
    );
    if (response is! Map || response['data'] is! List) {
      throw StateError('Notification count response is invalid');
    }
    return List<Map<String, dynamic>>.from(response['data'] as List)
        .where((row) => row['read_at'] == null)
        .length;
  }

  Future<void> _openChatHub() async {
    final account = backendAuthSession.user?.id;
    if (_chatHubOpen || account == null) return;
    _chatHubOpen = true;
    final epoch = _accountEpoch;
    try {
      final destination = await showModalBottomSheet<MessageHubDestination>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => MessageHubSheet(
            accountId: account,
            loadUnread: () => _loadUnreadOfferNotifications(account)),
      );
      if (!mounted ||
          destination == null ||
          epoch != _accountEpoch ||
          _accountOwner != account) {
        return;
      }
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => destination == MessageHubDestination.activity
                  ? const ActivityNotificationsPage()
                  : const MyMessagesPage()));
    } finally {
      _chatHubOpen = false;
    }
  }

  Widget _gridTile(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Color? backgroundColor,
    Color? iconBgColor,
    Color? iconColor,
    Color? textColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = textColor ?? scheme.onSurface;
    final glyph = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: iconBgColor ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 24,
        color: iconColor ?? scheme.onPrimaryContainer,
      ),
    );
    final text = Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontWeight: FontWeight.w700, color: foreground),
    );
    return Material(
      color: backgroundColor ?? scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: LayoutBuilder(
            builder: (context, size) => size.maxWidth >= 240
                ? Row(
                    children: [
                      glyph,
                      const SizedBox(width: 12),
                      Expanded(child: text),
                      const SizedBox(width: 8),
                      Icon(AppIcons.disclosure, size: 22, color: foreground),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      glyph,
                      const SizedBox(height: 10),
                      DefaultTextStyle.merge(
                        textAlign: TextAlign.center,
                        child: text,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionsGrid() {
    final tiles = <Widget>[
      _gridTile(
        AppIcons.add,
        t('account_sell_car'),
        onTap: _openSellCar,
        backgroundColor: red,
        iconBgColor: Colors.white.withValues(alpha: 0.16),
        iconColor: Colors.white,
        textColor: Colors.white,
      ),
      _gridTile(
        AppIcons.cars,
        t('account_watch'),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SectionPage(title: kSectionCars, icon: AppIcons.cars),
            ),
          );
        },
      ),
      _gridTile(
        AppIcons.favorite,
        t('account_favorites'),
        onTap: _openFavorites,
      ),
      _gridTile(AppIcons.chat, t('account_chat'), onTap: _openChatHub),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final columns = constraints.maxWidth >= 650
            ? 4
            : constraints.maxWidth < 300 || scaler.scale(14) > 18
                ? 1
                : 2;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tile in tiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: tile,
                ),
            ],
          );
        }
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 84 +
              scaler.scale(14) *
                  (Theme.of(context).textTheme.labelLarge?.height ?? 1.35) *
                  3,
          children: tiles,
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
  }) {
    final isPhone = controller == phone;
    Widget input(TextDirection direction) => TextFormField(
          key: isPhone
              ? _phoneField
              : ValueKey(
                  controller == email
                      ? 'auth_email'
                      : controller == name
                          ? 'auth_name'
                          : 'auth_username',
                ),
          controller: controller,
          enabled: !(loading || phoneLoading),
          keyboardType: keyboard,
          textDirection: direction,
          textInputAction:
              isPhone ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: (_) {
            if (isPhone) {
              submitPhoneLogin();
            } else {
              FocusScope.of(context).nextFocus();
            }
          },
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          autocorrect: controller == name,
          autofillHints: isPhone
              ? const [AutofillHints.telephoneNumber]
              : controller == name
                  ? const [AutofillHints.name]
                  : controller == username
                      ? const [AutofillHints.newUsername]
                      : [login ? AutofillHints.username : AutofillHints.email],
          autovalidateMode: isPhone && _attemptedPhone
              ? AutovalidateMode.onUserInteraction
              : null,
          validator: (value) {
            final text = (value ?? '').trim();
            if (isPhone) {
              return iraqiMobileNumber(text) == null
                  ? t(text.isEmpty ? 'login_otp_prompt' : 'login_otp_hint')
                  : null;
            }
            if (text.isEmpty) return t('wanted');
            if (controller == username && !_usernamePattern.hasMatch(text)) {
              return t('login_username_rule');
            }
            if (controller == email) {
              if ((!login || text.contains('@')) && !validAuthEmail(text)) {
                return t('ui_auth_invalid_email');
              }
              if (login &&
                  !text.contains('@') &&
                  !_usernamePattern.hasMatch(text)) {
                return t('login_username_rule');
              }
            }
            return null;
          },
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            helperText: controller == username
                ? t('login_username_rule')
                : controller == email && login
                    ? t('login_email_or_username')
                    : null,
            helperMaxLines: 4,
          ),
        );
    return controller == name
        ? ContentDirectionBuilder(
            controller: controller,
            builder: (context, direction) => input(direction),
          )
        : input(TextDirection.ltr);
  }
}

class FinesPage extends StatelessWidget {
  const FinesPage({super.key, this.linkLauncher});
  final Future<bool> Function(Uri)? linkLauncher;

  static const iraqFinesUrl = 'https://traffic.moi.gov.iq/';
  static const kurdistanFinesUrl = 'https://www.fineskrg.com/';

  Future<void> _open(BuildContext context, String url, String label) async {
    await openExternalLink(context, Uri.tryParse(url), launcher: linkLauncher);
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('fines_title'))),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FinesOptionTile(
                      flag: '🇮🇶',
                      title: t('fines_iraq'),
                      subtitle: t('fines_iraq_url'),
                      onTap: () =>
                          _open(context, iraqFinesUrl, t('fines_iraq')),
                    ),
                    const SizedBox(height: 14),
                    _FinesOptionTile(
                      flag: '🟩',
                      title: t('fines_kurdistan'),
                      subtitle: t('fines_kurdistan_url'),
                      onTap: () => _open(
                        context,
                        kurdistanFinesUrl,
                        t('fines_kurdistan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinesOptionTile extends StatelessWidget {
  final String flag;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FinesOptionTile({
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            radius: 22,
            child: Text(flag, style: const TextStyle(fontSize: 20)),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: AppColors.textStrong,
              fontWeight: FontWeight.w700,
            ),
            textDirection: appLocale.direction,
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textDirection: appLocale.direction,
          ),
          trailing: Icon(
            Icons.open_in_new_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class SearchHistoryPage extends StatefulWidget {
  const SearchHistoryPage({super.key, this.preferencesLoader});
  final Future<SharedPreferences> Function()? preferencesLoader;

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  static const String _kSearchHistoryKey = 'search_history';
  List<String> _history = [];
  bool _loading = true, _failed = false, _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final prefs =
          await (widget.preferencesLoader ?? SharedPreferences.getInstance)();
      final list = prefs.getStringList(_kSearchHistoryKey) ?? [];
      if (mounted) {
        setState(() {
          _history = list.where((q) => q.trim().isNotEmpty).toSet().toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(t('history_clear_confirm')),
          content: Text(t('history_clear_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('history_clear')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final prefs =
          await (widget.preferencesLoader ?? SharedPreferences.getInstance)();
      if (!await prefs.remove(_kSearchHistoryKey)) {
        throw StateError('History write failed');
      }
      if (!mounted) return;
      setState(() {
        _history = [];
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('ui_history_cleared'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('ui_history_clear_failed'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  void _replaySearch(String query) => Navigator.pop(context, query);

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_search_history')),
          actions: [
            if (_history.isNotEmpty)
              IconButton(
                tooltip: t('history_clear'),
                icon: Icon(
                  Icons.delete_sweep_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                onPressed: _clearing ? null : _clearHistory,
              ),
          ],
        ),
        body: _loading
            ? AppLoadingView(label: t('ui_loading_title'))
            : _failed
                ? _loadError(_loadHistory)
                : _history.isEmpty
                    ? AppStateView(
                        title: t('history_empty'), icon: AppIcons.history)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final query = _history[i];
                          return AccountNavigationTile(
                            icon: AppIcons.history,
                            title: query,
                            onTap:
                                _clearing ? null : () => _replaySearch(query),
                          );
                        },
                      ),
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: PolicyDocument(
        title: t('about_privacy_policy'),
        updatedLabel:
            '${t('terms_last_updated')}: ${t('about_last_updated_date')}',
        sections: [
          (t('privacy_title_account'), t('privacy_body_account')),
          (t('privacy_title_ads'), t('privacy_body_ads')),
          (t('privacy_title_images'), t('privacy_body_images')),
          (t('privacy_title_contact'), t('privacy_body_contact')),
          (t('privacy_title_wallet'), t('privacy_body_wallet')),
          (t('privacy_title_supabase'), t('privacy_body_supabase')),
          (t('privacy_title_permissions'), t('privacy_body_permissions')),
          (t('privacy_title_sale'), t('privacy_body_sale')),
          (t('privacy_title_deletion'), t('privacy_body_deletion')),
          (t('privacy_title_support'), t('privacy_body_support')),
        ],
      ),
    );
  }
}

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: PolicyDocument(
        title: t('about_terms_of_use'),
        updatedLabel:
            '${t('terms_last_updated')}: ${t('about_last_updated_date')}',
        sections: [
          (t('terms_title_acceptance'), t('terms_body_acceptance')),
          (t('terms_title_account'), t('terms_body_account')),
          (t('terms_title_posting'), t('terms_body_posting')),
          (t('terms_title_prohibited'), t('terms_body_prohibited')),
          (t('terms_title_content'), t('terms_body_content')),
          (t('terms_title_platform'), t('terms_body_platform')),
          (t('terms_title_communication'), t('terms_body_communication')),
          (t('terms_title_wallet'), t('terms_body_wallet')),
          (t('terms_title_admin'), t('terms_body_admin')),
          (t('terms_title_external'), t('terms_body_external')),
          (t('terms_title_updates'), t('terms_body_updates')),
        ],
      ),
    );
  }
}

Widget _loadError(VoidCallback onRetry) => AppStateView(
      title: t('ui_load_error_title'),
      message: t('ui_load_error_body'),
      icon: AppIcons.cloudOff,
      isError: true,
      actionLabel: t('ui_retry'),
      onAction: onRetry,
    );

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});
  @override
  Widget build(BuildContext context) =>
      AppStatePanel(title: text, icon: AppIcons.inbox);
}

List<String> get businessAdCategories => BusinessCategories.storedValues;

class BusinessAdPackage {
  final String id;
  final String name;
  final int durationDays;
  final double price;
  final List<String> placements;
  final List<String> features;
  final bool isActive;

  BusinessAdPackage({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.placements,
    required this.features,
    required this.isActive,
  });

  factory BusinessAdPackage.fromJson(Map<String, dynamic> json) {
    final placementsRaw = json['placements'];
    final List<String> placementsList;
    if (placementsRaw is List) {
      placementsList = placementsRaw.map((e) => e.toString()).toList();
    } else if (placementsRaw is String) {
      placementsList = [placementsRaw];
    } else {
      placementsList = [];
    }

    final featuresRaw = json['features'];
    final List<String> featuresList;
    if (featuresRaw is List) {
      featuresList = featuresRaw.map((e) => e.toString()).toList();
    } else {
      featuresList = [];
    }

    return BusinessAdPackage(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      placements: placementsList,
      features: featuresList,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  String get durationText {
    if (durationDays >= 30) {
      final months = (durationDays / 30).round();
      return months == 1
          ? t('ui_duration_one_month')
          : t('ui_duration_months').replaceAll('{count}', '$months');
    }
    return durationDays == 1
        ? t('ui_duration_one_day')
        : t('ui_duration_days').replaceAll('{count}', '$durationDays');
  }

  String get priceText => formatCurrency(price);
}

Future<List<BusinessAdPackage>> loadBusinessAdPackages() async {
  final response =
      await backendApi.get('business-ads/packages', anonymous: true);
  if (response is! Map ||
      response['success'] != true ||
      response['data'] is! List) {
    throw const BackendApiException('تعذر تحميل باقات الإعلانات التجارية');
  }
  return (response['data'] as List)
      .map((e) => BusinessAdPackage.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

class BusinessAdData {
  final String id;
  final String userId;
  final String? orderId;
  final String businessName;
  final String category;
  final String? description;
  final String? logoUrl;
  final List<String> imageUrls;
  final String? phone;
  final String? whatsapp;
  final String? governorate;
  final String? area;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? mapsUrl;
  final String? instagramUrl;
  final String? facebookUrl;
  final String? workingHours;
  final String status;
  final String? packageId;
  final DateTime? startAt;
  final DateTime? endAt;
  final double? price;
  final String paymentStatus;
  final int viewsCount;
  final int clicksCount;
  final int callsCount;
  final int whatsappClicks;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessAdData({
    required this.id,
    required this.userId,
    this.orderId,
    required this.businessName,
    required this.category,
    this.description,
    this.logoUrl,
    required this.imageUrls,
    this.phone,
    this.whatsapp,
    this.governorate,
    this.area,
    this.address,
    this.latitude,
    this.longitude,
    this.mapsUrl,
    this.instagramUrl,
    this.facebookUrl,
    this.workingHours,
    required this.status,
    this.packageId,
    this.startAt,
    this.endAt,
    this.price,
    required this.paymentStatus,
    required this.viewsCount,
    required this.clicksCount,
    required this.callsCount,
    required this.whatsappClicks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessAdData.fromJson(Map<String, dynamic> json) {
    final imageUrlsRaw = json['image_urls'];
    final List<String> imageUrlsList;
    if (imageUrlsRaw is List) {
      imageUrlsList = imageUrlsRaw.map((e) => e.toString()).toList();
    } else if (imageUrlsRaw is String) {
      imageUrlsList = [imageUrlsRaw];
    } else {
      imageUrlsList = [];
    }

    return BusinessAdData(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      orderId: json['order_id']?.toString(),
      businessName: json['business_name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      imageUrls: imageUrlsList,
      phone: json['phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      governorate: json['governorate']?.toString(),
      area: json['area']?.toString(),
      address: json['address']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      mapsUrl: json['maps_url']?.toString(),
      instagramUrl: json['instagram_url']?.toString(),
      facebookUrl: json['facebook_url']?.toString(),
      workingHours: json['working_hours']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      packageId: json['package_id']?.toString(),
      startAt: json['start_at'] != null
          ? DateTime.tryParse(json['start_at'].toString())
          : null,
      endAt: json['end_at'] != null
          ? DateTime.tryParse(json['end_at'].toString())
          : null,
      price: (json['price'] as num?)?.toDouble(),
      paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      clicksCount: (json['clicks_count'] as num?)?.toInt() ?? 0,
      callsCount: (json['calls_count'] as num?)?.toInt() ?? 0,
      whatsappClicks: (json['whatsapp_clicks'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isActive => status == 'active';
  bool get isApproved => status == 'approved' || status == 'active';
  String get locationText => [governorate, area]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .join(' · ');
}

Future<List<BusinessAdData>> loadActiveBusinessAds({
  String? category,
  int limit = 10,
  int offset = 0,
}) async {
  if (restrictPaidFeatures) return <BusinessAdData>[];
  final categoryValues = BusinessCategories.queryValues(category ?? '');
  final response = await backendApi.get(
    'business-ads/active',
    anonymous: true,
    query: {
      if (categoryValues.isNotEmpty) 'categories': categoryValues.join(','),
      'limit': '$limit',
      'offset': '$offset',
    },
  );
  if (response is! Map ||
      response['success'] != true ||
      response['data'] is! List) {
    throw const BackendApiException('تعذر تحميل الإعلانات التجارية');
  }
  return (response['data'] as List)
      .map((e) => BusinessAdData.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

Future<void> incrementAdCounter(String adId, String counter) async {
  try {
    await backendApi.post(
      'business-ads/events/counter',
      body: {'ad_id': adId, 'counter': counter},
    );
  } catch (e) {
    // عدّاد إحصائي ثانوي: الفشل هنا لا يجب أن يمنع عرض الإعلان.
  }
}

Future<void> logAdEvent(String adId, String eventType) async {
  try {
    await backendApi.post(
      'business-ads/events',
      body: {'ad_id': adId, 'event_type': eventType},
    );
  } catch (e) {
    // تسجيل حدث اختياري: الفشل هنا لا يجب أن يمنع أي إجراء للمستخدم.
  }
}

class BusinessAdCard extends StatelessWidget {
  const BusinessAdCard({super.key, required this.ad, this.onTap});
  final BusinessAdData ad;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () {
          unawaited(logAdEvent(ad.id, 'click'));
          unawaited(incrementAdCounter(ad.id, 'clicks_count'));
          if (onTap != null) {
            onTap!();
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BusinessAdDetailsPage(ad: ad)),
            );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ad.imageUrls.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  ad.imageUrls.first,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 44,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ad.logoUrl?.trim().isNotEmpty == true
                            ? Image.network(
                                ad.logoUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.storefront_rounded,
                                  color: scheme.onPrimaryContainer,
                                ),
                              )
                            : Icon(
                                Icons.storefront_rounded,
                                color: scheme.onPrimaryContainer,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ad.businessName.trim().isEmpty
                              ? t('common_unspecified')
                              : ad.businessName,
                          textDirection:
                              contentTextDirection(context, ad.businessName),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t('ui_business_ad_label'),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (ad.category.trim().isNotEmpty)
                    Text(
                      BusinessCategories.label(ad.category),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (ad.locationText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            AppIcons.location,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ad.locationText,
                              textDirection: contentTextDirection(
                                  context, ad.locationText),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (ad.description?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        ad.description!,
                        textDirection:
                            contentTextDirection(context, ad.description!),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('ad_view'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Icon(
                        AppIcons.disclosure,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessAdsPage extends StatefulWidget {
  const BusinessAdsPage({super.key});
  @override
  State<BusinessAdsPage> createState() => _BusinessAdsPageState();
}

class _BusinessAdsPageState extends State<BusinessAdsPage> {
  String selectedCategory = '';
  final ScrollController _scrollController = ScrollController();
  final Set<String> _recordedViews = {};
  List<BusinessAdData> _ads = [];
  int _generation = 0, _nextOffset = 0;
  bool _loading = false,
      _loadFailed = false,
      _loadingMore = false,
      _moreFailed = false,
      _hasMore = false;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    unawaited(_loadAds());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<BusinessAdData> _unique(Iterable<BusinessAdData> ads) {
    final seen = <String>{};
    return ads.where((ad) => seen.add(ad.id)).toList();
  }

  void _recordViews(Iterable<BusinessAdData> ads) {
    for (final ad in ads) {
      if (_recordedViews.add(ad.id)) {
        unawaited(incrementAdCounter(ad.id, 'views_count'));
      }
    }
  }

  Future<void> _loadAds({bool clear = false}) async {
    final generation = ++_generation, category = selectedCategory;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadingMore = false;
      _moreFailed = false;
      if (clear) _ads = [];
    });
    try {
      final ads = await loadActiveBusinessAds(
        category: category,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _ads = _unique(ads);
        _nextOffset = ads.length;
        _hasMore = ads.length >= _pageSize;
        _loading = false;
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _recordViews(_ads);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _loadFailed) return;
    final generation = _generation,
        category = selectedCategory,
        offset = _nextOffset;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final ads = await loadActiveBusinessAds(
        category: category,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _ads = _unique([..._ads, ...ads]);
        _nextOffset = offset + ads.length;
        _hasMore = ads.length >= _pageSize;
        _loadingMore = false;
      });
      _recordViews(ads);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loadingMore = false;
          _moreFailed = true;
        });
      }
    }
  }

  void _scrollListener() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 240 &&
        !_moreFailed) {
      unawaited(_loadMore());
    }
  }

  void _selectCategory(String? category) {
    if (category == null || category == selectedCategory) return;
    selectedCategory = category;
    unawaited(_loadAds(clear: true));
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('account_business_ads_all')),
          actions: [
            IconButton(
              tooltip: t('alerts_update'),
              onPressed: _loading ? null : _loadAds,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                isExpanded: true,
                isDense: false,
                itemHeight: null,
                decoration: InputDecoration(labelText: t('field_category')),
                items: ['', ...BusinessCategories.keys]
                    .map(
                      (key) => DropdownMenuItem(
                        value: key,
                        child: Text(key.isEmpty ? t('common_all') : t(key)),
                      ),
                    )
                    .toList(),
                onChanged: _selectCategory,
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_ads.isEmpty && _loading) {
      return AppLoadingView(label: t('ui_loading_title'));
    }
    if (_ads.isEmpty && _loadFailed) return _loadError(_loadAds);
    if (_ads.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAds,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: AppStateView(
                  title: t('misc_no_business_ads'),
                  icon: AppIcons.market,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAds,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _ads.length + 2,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_loading) return const LinearProgressIndicator();
            if (_loadFailed) {
              return AppStatePanel(
                title: t('ui_business_refresh_failed'),
                icon: AppIcons.cloudOff,
                isError: true,
                actionLabel: t('ui_retry'),
                onAction: _loadAds,
              );
            }
            return const SizedBox.shrink();
          }
          if (index <= _ads.length) {
            return BusinessAdCard(
              key: ValueKey('business_${_ads[index - 1].id}'),
              ad: _ads[index - 1],
            );
          }
          if (!_hasMore || _loadFailed) return const SizedBox.shrink();
          if (_moreFailed) {
            return AppStatePanel(
              key: const ValueKey('business_more_error'),
              title: t('ui_business_more_failed'),
              icon: AppIcons.cloudOff,
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: _loadMore,
            );
          }
          return SizedBox(
            height: 56,
            child: Center(
              child: _loadingMore
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: t('ui_loading_title'),
                      ),
                    )
                  : TextButton.icon(
                      key: const ValueKey('business_load_more'),
                      onPressed: _loading ? null : _loadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(t('ui_business_load_more')),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class BusinessAdDetailsPage extends StatefulWidget {
  final BusinessAdData ad;
  const BusinessAdDetailsPage({super.key, required this.ad, this.linkLauncher});
  final Future<bool> Function(Uri)? linkLauncher;

  @override
  State<BusinessAdDetailsPage> createState() => _BusinessAdDetailsPageState();
}

class _BusinessAdDetailsPageState extends State<BusinessAdDetailsPage> {
  bool _viewLogged = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _logViewOnce();
    });
  }

  void _logViewOnce() {
    if (_viewLogged) return;
    _viewLogged = true;
    incrementAdCounter(widget.ad.id, 'views_count');
    logAdEvent(widget.ad.id, 'view');
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final ad = widget.ad;
    final photos = marketItemImageUrls({'images': ad.imageUrls});
    final images = photos.isNotEmpty
        ? photos
        : marketItemImageUrls({'images': ad.logoUrl});

    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: card,
                  leading: IconButton(
                    icon: const BackButtonIcon(),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(AppIcons.share),
                      onPressed: _sharing ? null : _shareAd,
                      tooltip: t('ad_share'),
                    ),
                  ],
                  title: Text(
                    t('ui_business_ad_label'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (images.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, size) => MarketItemGallery(
                          urls: images,
                          height: (size.maxWidth * .75).clamp(180, 420),
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ad.businessName.trim().isEmpty
                                ? t('common_unspecified')
                                : ad.businessName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                            textDirection: contentTextDirection(
                              context,
                              ad.businessName,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (ad.category.trim().isNotEmpty)
                            _buildDetailRow(
                              AppIcons.category,
                              t('field_category'),
                              BusinessCategories.label(ad.category),
                            ),
                          if (ad.locationText.isNotEmpty)
                            _buildDetailRow(
                              AppIcons.location,
                              t('field_province_area'),
                              ad.locationText,
                            ),
                          if (ad.address != null && ad.address!.isNotEmpty)
                            _buildDetailRow(
                              AppIcons.location,
                              t('field_address'),
                              ad.address!,
                            ),
                          if (ad.workingHours != null &&
                              ad.workingHours!.isNotEmpty)
                            _buildDetailRow(
                              AppIcons.schedule,
                              t('field_hours'),
                              ad.workingHours!,
                              direction: contentTextDirection(
                                context,
                                ad.workingHours!,
                                fallback: TextDirection.ltr,
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (ad.description != null &&
                              ad.description!.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('field_establishment'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  textDirection: appLocale.direction,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  ad.description!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(height: 1.6),
                                  textDirection: contentTextDirection(
                                    context,
                                    ad.description!,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),
                          Column(
                            children: [
                              if (ad.phone != null && ad.phone!.isNotEmpty)
                                _contactButton(
                                  icon: AppIcons.call,
                                  label: t('settings_call_us'),
                                  onTap: () => _callNumber(ad.phone!),
                                ),
                              if (ad.whatsapp != null &&
                                  ad.whatsapp!.isNotEmpty)
                                _contactButton(
                                  icon: AppIcons.chat,
                                  label: 'WhatsApp',
                                  onTap: () => _openWhatsApp(ad.whatsapp!),
                                ),
                              if (ad.mapsUrl != null && ad.mapsUrl!.isNotEmpty)
                                _contactButton(
                                  icon: AppIcons.location,
                                  label: t('settings_show_on_map'),
                                  onTap: () =>
                                      _launchUrl(ad.mapsUrl!, map: true),
                                ),
                              if (ad.instagramUrl != null &&
                                  ad.instagramUrl!.isNotEmpty)
                                _contactButton(
                                  icon: AppIcons.camera,
                                  label: 'Instagram',
                                  onTap: () => _launchUrl(ad.instagramUrl!),
                                ),
                              if (ad.facebookUrl != null &&
                                  ad.facebookUrl!.isNotEmpty)
                                _contactButton(
                                  icon: Icons.facebook_rounded,
                                  label: 'Facebook',
                                  onTap: () => _launchUrl(ad.facebookUrl!),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _sharing ? null : _shareAd,
                            icon: const Icon(AppIcons.share),
                            label: Text(t('ad_share')),
                            style: FilledButton.styleFrom(
                              backgroundColor: panel,
                              foregroundColor: AppColors.textStrong,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    TextDirection? direction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  textDirection: appLocale.direction,
                ),
                Text(
                  value,
                  style: TextStyle(color: AppColors.textStrong, fontSize: 14),
                  textDirection:
                      direction ?? contentTextDirection(context, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            unawaited(incrementAdCounter(widget.ad.id, 'clicks_count'));
            unawaited(logAdEvent(widget.ad.id, 'click'));
            onTap();
          },
          icon: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          label: Text(
            label,
            style: TextStyle(color: AppColors.textStrong, fontSize: 14),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _callNumber(String phone) async {
    final parsed = SellerPhone.parse(phone);
    unawaited(incrementAdCounter(widget.ad.id, 'calls_count'));
    unawaited(logAdEvent(widget.ad.id, 'call'));
    await openExternalLink(
      context,
      parsed == null ? null : Uri(scheme: 'tel', path: parsed.telTarget),
      failureKey: 'misc_call_app_failed',
      launcher: widget.linkLauncher,
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final parsed = SellerPhone.parse(phone);
    unawaited(incrementAdCounter(widget.ad.id, 'whatsapp_clicks'));
    unawaited(logAdEvent(widget.ad.id, 'whatsapp'));
    await openExternalLink(
      context,
      parsed == null ? null : Uri.https('wa.me', '/${parsed.whatsappDigits}'),
      failureKey: 'misc_whatsapp_failed',
      launcher: widget.linkLauncher,
    );
  }

  Future<void> _launchUrl(String url, {bool map = false}) async {
    final uri = Uri.tryParse(url);
    if (map) {
      unawaited(logAdEvent(widget.ad.id, 'map'));
    }
    await openExternalLink(
      context,
      uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http') &&
              uri.host.isNotEmpty
          ? uri
          : null,
      launcher: widget.linkLauncher,
    );
  }

  Future<void> _shareAd() async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
    });
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: buildBusinessAdShareText(widget.ad),
          sharePositionOrigin: shareOrigin(context),
        ),
      );
      if (result.status != ShareResultStatus.dismissed) {
        // Successful platform handoff is engagement, not proof of delivery.
        unawaited(incrementAdCounter(widget.ad.id, 'clicks_count'));
        unawaited(logAdEvent(widget.ad.id, 'share'));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('ui_support_share_failed'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }
}

class CreateBusinessAdPage extends StatefulWidget {
  const CreateBusinessAdPage({super.key, this.logoPicker, this.imagePicker});
  final Future<XFile?> Function()? logoPicker;
  final Future<List<XFile>> Function()? imagePicker;

  @override
  // Select before paid-package loading and submission resources initialize.
  // ignore: no_logic_in_create_state
  State<CreateBusinessAdPage> createState() => restrictPaidFeatures
      ? PaidFeatureUnavailableState<CreateBusinessAdPage>()
      : _CreateBusinessAdPageState();
}

class _CreateBusinessAdPageState extends State<CreateBusinessAdPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _governorateController = TextEditingController();
  final _areaController = TextEditingController();
  final _addressController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  final _instagramUrlController = TextEditingController();
  final _facebookUrlController = TextEditingController();
  final _workingHoursController = TextEditingController();

  String? _selectedPackageId;
  BusinessDraftPhoto? _logoFile;
  final List<BusinessDraftPhoto> _imageFiles = [];
  final _scroll = ScrollController();
  late final _submission = BusinessSubmission(
    api: backendApi,
    currentUserId: () =>
        backendAuthSession.user?.id ?? supabase.auth.currentUser?.id,
  );
  BusinessAdPackage? _submittedPackage;
  BusinessSubmissionStage _stage = BusinessSubmissionStage.photos;
  bool _picking = false, _confirming = false, _attempted = false;
  String? _error;
  bool get _controlsBusy => _isSubmitting || _picking || _confirming;
  bool get _fieldsLocked => _controlsBusy || _submission.locked;
  bool _isSubmitting = false;

  late Future<List<BusinessAdPackage>> _packagesFuture;

  @override
  void initState() {
    super.initState();
    _packagesFuture = _startPackageLoad();
  }

  Future<List<BusinessAdPackage>> _startPackageLoad() {
    final future = loadBusinessAdPackages();
    // The package section is lazily mounted near the end of the form. Attach
    // an error listener immediately; FutureBuilder still receives the original
    // error and presents retry when the user scrolls to this section.
    unawaited(future.catchError((Object _) => <BusinessAdPackage>[]));
    return future;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _businessNameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _governorateController.dispose();
    _areaController.dispose();
    _addressController.dispose();
    _mapsUrlController.dispose();
    _instagramUrlController.dispose();
    _facebookUrlController.dispose();
    _workingHoursController.dispose();
    super.dispose();
  }

  Future<BusinessDraftPhoto> _readPhoto(XFile file, String folder) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw StateError('Image exceeds bucket limit');
    }
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    return BusinessDraftPhoto(
      id: newSubmissionId(),
      name: file.name,
      bytes: bytes,
      folder: folder,
    );
  }

  Future<void> _pickLogo() async {
    if (_fieldsLocked) return;
    setState(() => _picking = true);
    try {
      final file = await (widget.logoPicker?.call() ??
          ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
            maxWidth: 1600,
            maxHeight: 1600,
          ));
      if (!mounted || file == null) return;
      final photo = await _readPhoto(file, 'logos');
      if (mounted) setState(() => _logoFile = photo);
    } catch (_) {
      _showError('ui_business_photo_failed');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickImages() async {
    if (_fieldsLocked || _imageFiles.length >= 5) return;
    setState(() => _picking = true);
    try {
      final files = await (widget.imagePicker?.call() ??
          ImagePicker().pickMultiImage(
            imageQuality: 82,
            maxWidth: 1600,
            maxHeight: 1600,
          ));
      if (!mounted || files.isEmpty) return;
      final photos = <BusinessDraftPhoto>[];
      for (final file in files.take(5 - _imageFiles.length)) {
        photos.add(await _readPhoto(file, 'images'));
        if (!mounted) return;
      }
      setState(() => _imageFiles.addAll(photos));
    } catch (_) {
      _showError('ui_business_photo_failed');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showError(String key) {
    if (!mounted) return;
    setState(() => _error = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool _validUrl(String text) {
    if (text.trim().isEmpty) return true;
    final value = Uri.tryParse(text.trim());
    return value != null &&
        ['http', 'https'].contains(value.scheme.toLowerCase()) &&
        value.host.isNotEmpty;
  }

  bool _validateDraft() {
    setState(() => _attempted = true);
    final visible = _formKey.currentState?.validate() ?? false;
    final name = _businessNameController.text.trim();
    final valid = name.length >= 2 &&
        name.length <= 100 &&
        _categoryController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _descriptionController.text.length <= 2000 &&
        (_whatsappController.text.trim().isEmpty ||
            _whatsappController.text.trim().length >= 7) &&
        [
          _mapsUrlController,
          _instagramUrlController,
          _facebookUrlController,
        ].every((c) => _validUrl(c.text));
    if (!visible || !valid) {
      _showError('ui_business_check_fields');
      return false;
    }
    if (_selectedPackageId == null) {
      _showError('pkg_pick_first');
      return false;
    }
    if (_logoFile == null) {
      _showError('field_logo_first');
      return false;
    }
    return true;
  }

  Future<void> _submitBusiness() async {
    try {
      if (_controlsBusy) return;
      final user = backendAuthSession.user;
      if (user == null ||
          _submission.ownerId != null && _submission.ownerId != user.id) {
        _showError('ui_business_session_changed');
        return;
      }
      if (!_submission.locked && !_validateDraft()) return;
      FocusScope.of(context).unfocus();
      final fields = <String, dynamic>{
        'business_name': _businessNameController.text.trim(),
        'category': BusinessCategories.storedValue(
          _categoryController.text.trim(),
        ),
        'description': _descriptionController.text.trim(),
        'phone': _phoneController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'governorate': _governorateController.text.trim(),
        'area': _areaController.text.trim(),
        'address': _addressController.text.trim(),
        'maps_url': _mapsUrlController.text.trim(),
        'instagram_url': _instagramUrlController.text.trim(),
        'facebook_url': _facebookUrlController.text.trim(),
        'working_hours': _workingHoursController.text.trim(),
      };
      final logo = _logoFile!;
      final photos = List<BusinessDraftPhoto>.of(_imageFiles);
      final selectedId = _selectedPackageId;
      var navigated = false;
      setState(() {
        _isSubmitting = true;
        _error = null;
        _stage = BusinessSubmissionStage.photos;
      });
      try {
        BusinessAdPackage? package =
            _submission.locked ? _submittedPackage : null;
        if (package == null) {
          final packages = await _packagesFuture;
          if (!mounted) return;
          for (final candidate in packages) {
            if (candidate.id == selectedId) {
              package = candidate;
              break;
            }
          }
        }
        if (package == null ||
            !package.isActive ||
            !package.price.isFinite ||
            package.price < 0 ||
            package.durationDays < 1) {
          _showError('pkg_unavailable');
          return;
        }
        final currentUser = backendAuthSession.user;
        if (currentUser == null || currentUser.id != user.id) {
          throw StateError('Submission account changed');
        }
        try {
          if (!await ensureUgcPolicyAccepted(context, supabase, backendApi)) {
            return;
          }
        } on BackendApiException {
          _showError('ugc_policy_acceptance_failed');
          return;
        }
        _submittedPackage = package;
        await _submission.submit(
          fields: fields,
          logo: logo,
          photos: photos,
          packageId: package.id,
          price: package.price,
          durationDays: package.durationDays,
          active: () => mounted,
          progress: (stage) {
            if (mounted) setState(() => _stage = stage);
          },
        );
        if (!mounted) return;
        navigated = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const PaymentPageSubmitted(),
          ),
        );
      } catch (_) {
        final latestUser = backendAuthSession.user;
        _showError(
          latestUser == null || latestUser.id != user.id
              ? 'ui_business_session_changed'
              : _submission.locked
                  ? 'ui_business_submit_failed'
                  : 'ui_business_upload_failed',
        );
      } finally {
        if (mounted && !navigated) setState(() => _isSubmitting = false);
      }
    } catch (e) {
      final latestUser = backendAuthSession.user;
      if (latestUser == null) {
        _showError('ui_business_session_changed');
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_advertise_with_us'))),
        body: PopScope(
          canPop: !_isSubmitting,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _isSubmitting ? _buildSubmissionProgress() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmissionProgress() => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    _stage == BusinessSubmissionStage.photos
                        ? 'img_uploading'
                        : 'misc_send_ad',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BusinessFormSection(
              title: t('ui_business_details'),
              icon: AppIcons.market,
              children: [
                _buildTextField(
                  _businessNameController,
                  t('field_business_name'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return t('wanted');
                    if (v.trim().length < 2 || v.trim().length > 100) {
                      return t('ui_business_name_length');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildCategoryDropdown(),
                const SizedBox(height: 12),
                _buildTextField(
                  _descriptionController,
                  t('field_short_desc'),
                  maxLines: 3,
                  validator: (v) {
                    if (v != null && v.length > 2000) {
                      return t('field_desc_too_long');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
            BusinessFormSection(
              title: t('ui_location_contact'),
              icon: AppIcons.call,
              children: [
                _buildTextField(
                  _phoneController,
                  t('field_phone'),
                  keyboard: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return t('wanted');
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _whatsappController,
                  'WhatsApp',
                  keyboard: TextInputType.phone,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.trim().length < 7) {
                      return t('field_invalid_number');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildProvinceDropdown(),
                const SizedBox(height: 12),
                _buildTextField(
                  _areaController,
                  t('field_area'),
                  validator: (v) => null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _addressController,
                  t('field_title_detail'),
                  validator: (v) => null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _mapsUrlController,
                  t('field_link_maps'),
                  keyboard: TextInputType.url,
                  validator: (v) {
                    if (v != null && !_validUrl(v)) {
                      return t('field_invalid_url');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _instagramUrlController,
                  t('field_link_instagram'),
                  keyboard: TextInputType.url,
                  validator: (v) {
                    if (v != null && !_validUrl(v)) {
                      return t('field_invalid_url');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _facebookUrlController,
                  t('field_link_facebook'),
                  keyboard: TextInputType.url,
                  validator: (v) {
                    if (v != null && !_validUrl(v)) {
                      return t('field_invalid_url');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  _workingHoursController,
                  t('field_hours'),
                  validator: (v) => null,
                ),
                const SizedBox(height: 12),
              ],
            ),
            BusinessFormSection(
              title: t('ui_photos_branding'),
              icon: Icons.photo_library_outlined,
              children: [
                _buildLogoPicker(),
                const SizedBox(height: 12),
                _buildImagePicker(),
                const SizedBox(height: 16),
              ],
            ),
            BusinessFormSection(
              title: t('ui_ad_package'),
              icon: AppIcons.campaign,
              children: [_buildPackageSelector()],
            ),
          ],
        ),
      ),
    );
  }

  Widget _businessFieldLabel(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .72),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(label: label, child: field),
        ],
      );

  InputDecoration _businessDecoration() {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: scheme.onSurface.withValues(alpha: .045),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    Widget input(TextDirection direction) => _businessFieldLabel(
          label,
          TextFormField(
            controller: controller,
            key: ValueKey(
              controller == _businessNameController
                  ? 'business_name'
                  : controller == _phoneController
                      ? 'business_phone'
                      : controller == _descriptionController
                          ? 'business_description'
                          : controller == _whatsappController
                              ? 'business_whatsapp'
                              : controller == _mapsUrlController
                                  ? 'business_maps'
                                  : controller == _instagramUrlController
                                      ? 'business_instagram'
                                      : controller == _facebookUrlController
                                          ? 'business_facebook'
                                          : controller == _areaController
                                              ? 'business_area'
                                              : controller == _addressController
                                                  ? 'business_address'
                                                  : controller ==
                                                          _workingHoursController
                                                      ? 'business_hours'
                                                      : label,
            ),
            enabled: !_fieldsLocked,
            autovalidateMode: _attempted
                ? AutovalidateMode.always
                : AutovalidateMode.onUserInteraction,
            keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
            maxLines: maxLines,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
            textDirection: direction,
            textInputAction:
                maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            validator: validator,
            decoration: _businessDecoration(),
          ),
        );
    if (keyboard.index == TextInputType.phone.index ||
        keyboard.index == TextInputType.url.index) {
      return input(TextDirection.ltr);
    }
    return ContentDirectionBuilder(
      controller: controller,
      builder: (context, direction) => input(
        controller == _workingHoursController
            ? contentTextDirection(
                context,
                controller.text,
                fallback: TextDirection.ltr,
              )
            : direction,
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    final value = BusinessCategories.storedValue(_categoryController.text);
    final options = <String>{
      ...businessAdCategories,
      if (value.isNotEmpty) value,
    };
    return _businessFieldLabel(
      t('field_category'),
      DropdownButtonFormField<String>(
        key: ValueKey('business-category:$value'),
        initialValue: value.isEmpty ? null : value,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        items: options
            .map(
              (cat) => DropdownMenuItem(
                value: cat,
                child: Text(
                  BusinessCategories.label(cat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _fieldsLocked
            ? null
            : (val) => setState(() {
                  _categoryController.text = val ?? '';
                }),
        decoration: _businessDecoration(),
        validator: (v) {
          if (v == null || v.isEmpty) return t('biz_pick_category');
          return null;
        },
      ),
    );
  }

  Widget _buildProvinceDropdown() {
    return _businessFieldLabel(
      t('field_province'),
      DropdownButtonFormField<String>(
        initialValue: _governorateController.text.isEmpty
            ? null
            : _governorateController.text,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        items: iraqiProvinces
            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
            .toList(),
        onChanged: _fieldsLocked
            ? null
            : (val) => setState(() {
                  _governorateController.text = val ?? '';
                }),
        decoration: _businessDecoration(),
      ),
    );
  }

  Widget _buildLogoPicker() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('field_logo'), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: t('field_logo'),
          child: Material(
            color: scheme.surfaceContainerHighest,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              key: const ValueKey('business_logo_picker'),
              onTap: _fieldsLocked ? null : _pickLogo,
              child: SizedBox(
                width: 100,
                height: 100,
                child: _logoFile == null
                    ? Icon(
                        AppIcons.camera,
                        size: 32,
                        color: scheme.onSurfaceVariant,
                      )
                    : Image.memory(_logoFile!.bytes, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('img_ad_max5'), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < _imageFiles.length; index++)
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _imageFiles[index].bytes,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: t('common_delete'),
                        onPressed: _fieldsLocked
                            ? null
                            : () => setState(() => _imageFiles.removeAt(index)),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.all(8),
                        ),
                        icon: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _fieldsLocked
                                ? scheme.surfaceContainerHighest
                                : Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            AppIcons.close,
                            size: 16,
                            color: _fieldsLocked
                                ? scheme.onSurface.withValues(alpha: .38)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_imageFiles.length < 5)
              Semantics(
                button: true,
                label: t('ui_add_photos'),
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: InkWell(
                    key: const ValueKey('business_images_picker'),
                    onTap: _fieldsLocked ? null : _pickImages,
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: Icon(
                        AppIcons.addPhoto,
                        size: 28,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _submissionFeedback() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  t(_error!),
                  key: const ValueKey('business_submit_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (_submission.locked)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(t('ui_business_resume_note')),
            ),
        ],
      );

  Widget _buildPackageSelector() {
    return FutureBuilder<List<BusinessAdPackage>>(
      future: _packagesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              _submissionFeedback(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 280),
                child: AppLoadingView(label: t('ui_loading_title')),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return Column(
            children: [
              _submissionFeedback(),
              AppStatePanel(
                title: t('ui_load_error_title'),
                message: t('ui_load_error_body'),
                icon: AppIcons.cloudOff,
                isError: true,
                actionLabel: t('ui_retry'),
                onAction: () => setState(() {
                  _packagesFuture = _startPackageLoad();
                }),
              ),
            ],
          );
        }
        final packages = snapshot.data ?? [];
        if (packages.isEmpty) {
          return Column(
            children: [
              _submissionFeedback(),
              Text(
                t('pkg_none_available'),
                style: TextStyle(color: AppColors.textStrong),
              ),
            ],
          );
        }
        return RadioGroup<String>(
          groupValue: _selectedPackageId,
          onChanged: (value) {
            if (!_fieldsLocked) setState(() => _selectedPackageId = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('pkg_pick'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...packages.map((pkg) => _buildPackageOption(pkg)),
              const SizedBox(height: 20),
              _submissionFeedback(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _controlsBusy ? null : _confirmAndSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.textStrong,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          t(_submission.locked ? 'ui_retry' : 'confirm_review'),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndSubmit() async {
    if (_controlsBusy) return;
    if (_submission.locked) {
      await _submitBusiness();
      return;
    }
    if (!_validateDraft()) return;
    FocusScope.of(context).unfocus();
    if (mounted) setState(() => _confirming = true);
    bool? confirmed;
    try {
      final packages = await _packagesFuture;
      if (!mounted) return;
      BusinessAdPackage? selected;
      for (final package in packages) {
        if (package.id == _selectedPackageId) {
          selected = package;
          break;
        }
      }
      if (selected == null ||
          !selected.isActive ||
          !selected.price.isFinite ||
          selected.price < 0 ||
          selected.durationDays < 1) {
        _showError('pkg_unavailable');
        return;
      }
      final reviewPackage = selected;
      confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          dialogContext.dependOnAppStrings();
          return AlertDialog(
            scrollable: true,
            title: Text(t('confirm_submit')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _businessNameController.text.trim(),
                  textDirection: contentTextDirection(
                    context,
                    _businessNameController.text,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  reviewPackage.name,
                  textDirection: contentTextDirection(
                    context,
                    reviewPackage.name,
                  ),
                ),
                Text(reviewPackage.durationText),
                const SizedBox(height: 8),
                Text(
                  formatCurrencyLines(reviewPackage.price),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 12),
                Text(t('confirm_review_body')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t('common_cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t('common_send')),
              ),
            ],
          );
        },
      );
    } catch (_) {
      _showError('pkg_unavailable');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (mounted && confirmed == true) await _submitBusiness();
  }

  Widget _buildPackageOption(BusinessAdPackage pkg) {
    final isSelected = _selectedPackageId == pkg.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.onSurface
              : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: AppColors.shadow,
      ),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: RadioListTile<String>(
          enabled: !_fieldsLocked,
          selected: isSelected,
          value: pkg.id,
          activeColor: Theme.of(context).colorScheme.onSurface,
          title: Text(
            pkg.name,
            textDirection: contentTextDirection(context, pkg.name),
            style: TextStyle(
              color: AppColors.textStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pkg.durationText,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                pkg.priceText,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: AppColors.textStrong),
              ),
              const SizedBox(height: 4),
              if (pkg.placements.isNotEmpty) ...[
                Text(
                  t('ui_ad_placements'),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                for (final placement in pkg.placements)
                  Text(
                    placement,
                    textDirection: contentTextDirection(context, placement),
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
              for (final feature in pkg.features)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    feature,
                    textDirection: contentTextDirection(context, feature),
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentPageSubmitted extends StatelessWidget {
  const PaymentPageSubmitted({super.key});

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_advertise_with_us'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('ui_business_submitted_pending'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context)
                      ..popUntil((route) => route.isFirst)
                      ..push(MaterialPageRoute(
                          builder: (_) => const BusinessAdsPage()));
                  },
                  child: Text(t('ui_payment_back_listings')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BusinessAdBanner extends StatelessWidget {
  final BusinessAdData ad;
  final VoidCallback? onTap;
  const BusinessAdBanner({super.key, required this.ad, this.onTap});

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: () {
            unawaited(logAdEvent(ad.id, 'click'));
            unawaited(incrementAdCounter(ad.id, 'clicks_count'));
            if (onTap != null) {
              onTap!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BusinessAdDetailsPage(ad: ad),
                ),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadiusDirectional.only(
                    bottomEnd: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.campaign,
                      size: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 4),
                    Text(
                      t('ui_business_ad_label'),
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (ad.logoUrl != null && ad.logoUrl!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(imgRadius),
                            child: Image.network(
                              ad.logoUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.storefront_outlined,
                                size: 32,
                                color: AppColors.textHint,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.storefront_outlined,
                            size: 32,
                            color: AppColors.textHint,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ad.businessName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            textDirection: appLocale.direction,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        BusinessCategories.label(ad.category),
                        ad.locationText,
                      ].where((value) => value.isNotEmpty).join(' • '),
                      style: TextStyle(
                        color: AppColors.textStrong,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: appLocale.direction,
                    ),
                    if (ad.description != null && ad.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          ad.description!,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: appLocale.direction,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (ad.phone != null && ad.phone!.isNotEmpty)
                      _smallButton(Icons.phone_rounded, t('settings_call'), () {
                        incrementAdCounter(ad.id, 'calls_count');
                        logAdEvent(ad.id, 'call');
                        final parsed = SellerPhone.parse(ad.phone);
                        openExternalLink(
                          context,
                          parsed == null
                              ? null
                              : Uri(scheme: 'tel', path: parsed.telTarget),
                          failureKey: 'misc_call_app_failed',
                        );
                      }),
                    if (ad.whatsapp != null && ad.whatsapp!.isNotEmpty)
                      _smallButton(AppIcons.chat, 'WhatsApp', () {
                        incrementAdCounter(ad.id, 'whatsapp_clicks');
                        logAdEvent(ad.id, 'whatsapp');
                        final parsed = SellerPhone.parse(ad.whatsapp);
                        openExternalLink(
                          context,
                          parsed == null
                              ? null
                              : Uri.https('wa.me', '/${parsed.whatsappDigits}'),
                          failureKey: 'misc_whatsapp_failed',
                        );
                      }),
                    if (ad.mapsUrl != null && ad.mapsUrl!.isNotEmpty)
                      _smallButton(Icons.map_rounded, t('settings_map'), () {
                        incrementAdCounter(ad.id, 'clicks_count');
                        logAdEvent(ad.id, 'map');
                        openExternalLink(context, Uri.tryParse(ad.mapsUrl!));
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallButton(IconData icon, String label, VoidCallback onPressed) {
    return SizedBox(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: AppColors.textStrong),
        label: Text(
          label,
          style: TextStyle(color: AppColors.textStrong, fontSize: 11),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          minimumSize: const Size(48, 44),
        ),
      ),
    );
  }
}
