import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/auth/auth_feedback.dart';
import 'package:motri_iq/auth/auth_capabilities.dart';
import 'package:motri_iq/ui/account_navigation_tile.dart';
import 'package:motri_iq/ui/otp_verification_dialog.dart';
import 'package:motri_iq/ui/username_editor_dialog.dart';
import 'package:motri_iq/ui/message_hub_sheet.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> reveal(WidgetTester tester, Finder target,
    {double delta = 250}) async {
  for (var i = 0; i < 35 && target.hitTestable().evaluate().isEmpty; i++) {
    final list = find.byType(ListView).first;
    var movement = -delta;
    if (target.evaluate().isNotEmpty &&
        tester.getRect(target).center.dy < tester.getRect(list).top + 40) {
      movement = delta.abs();
    }
    await tester.drag(list, Offset(0, movement));
    await frames(tester);
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> networkUntil(WidgetTester tester, bool Function() settled) async {
  for (var i = 0; i < 30 && !settled(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await frames(tester);
  }
  expect(settled(), isTrue);
}

void main() {
  const id = '00000000-0000-4000-8000-000000000001';
  var failLogin = false,
      failVerify = false,
      failProfile = false,
      failNotifications = false,
      failUsername = false;
  var authCalls = 0,
      signups = 0,
      otpCalls = 0,
      verifyCalls = 0,
      usernameWrites = 0;
  String? sentPhone, verifiedCode;
  Map<String, dynamic>? signupData;
  Completer<void>? loginGate, usernameGate, notificationGate, profileGate;
  var notificationReads = 0;
  var notificationRows = <Map<String, Object?>>[];
  String? savedUsername;
  var phoneEnabled = true, capabilitiesFailed = false, signupSession = false;
  Future<AuthCapabilitiesResult> capabilityLoader() async => capabilitiesFailed
      ? const AuthCapabilitiesResult.failed()
      : AuthCapabilitiesResult.ready(
          AuthCapabilities(phoneOtpEnabled: phoneEnabled, emailEnabled: true));
  late Map<String, dynamic> user;
  late Map<String, dynamic> session;
  Future<void> signIn() async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'fixture@example.com',
      password: 'local-only',
    );
    user['full_name'] = (user['user_metadata'] as Map)['full_name'];
    await backendAuthSession.login(
      email: 'fixture@example.com',
      password: 'local-only',
    );
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
  }

  http.Response response(http.Request req, Object? body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, request: req, headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-supabase-api-version': '2024-01-01'
      });
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in {
      'MotriLatin': 'Inter',
      'MotriSans': 'Cairo',
      'MotriKurdish': 'NotoSansArabic'
    }.entries) {
      final loader = FontLoader(font.key);
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold'
      ]) {
        loader
            .addFont(rootBundle.load('assets/fonts/${font.value}-$weight.ttf'));
      }
      await loader.load();
    }
    SharedPreferences.setMockInitialValues({});
    user = {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'long.member.address@example.com',
      'phone': '+9647715339922',
      'created_at': '2026-01-01T00:00:00Z',
      'user_metadata': {
        'full_name':
            'MOTRI automotive community member with a long display name'
      }
    };
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': id,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final signature =
        base64Url.encode(List<int>.filled(32, 0)).replaceAll('=', '');
    session = {
      'authenticated': true,
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user
    };
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (path == '/auth/v1/token') {
            if (loginGate != null) await loginGate!.future;
            return response(
                req,
                failLogin
                    ? {
                        'code': 'invalid_credentials',
                        'msg': 'Private fixture authentication error'
                      }
                    : session,
                status: failLogin ? 400 : 200);
          }
          if (path == '/functions/v1/login-with-username') {
            return response(req, session);
          }
          if (path == '/auth/v1/signup') {
            signupData = jsonDecode(req.body) as Map<String, dynamic>;
            return response(req, signupSession ? session : user);
          }
          if (path == '/auth/v1/otp') {
            otpCalls++;
            sentPhone = (jsonDecode(req.body) as Map)['phone'] as String;
            return response(req, {});
          }
          if (path == '/auth/v1/verify') {
            verifyCalls++;
            verifiedCode = (jsonDecode(req.body) as Map)['token'] as String;
            return response(
                req,
                failVerify
                    ? {
                        'code': 'otp_expired',
                        'msg': 'Private fixture verification error'
                      }
                    : session,
                status: failVerify ? 400 : 200);
          }
          if (path == '/auth/v1/user') return response(req, user);
          if (path == '/auth/v1/logout') return response(req, {});
          if (path.endsWith('/set_my_username')) {
            savedUsername =
                (jsonDecode(req.body) as Map)['p_username'] as String;
            await usernameGate?.future;
            return response(
                req,
                failUsername
                    ? {'message': 'Private fixture username failure'}
                    : null,
                status: failUsername ? 400 : 200);
          }
          expectSync(req.method, 'GET',
              reason:
                  'Auth scenarios may only change their isolated auth/username fixtures');
          if (path.endsWith('/app_usernames')) {
            await profileGate?.future;
            return response(
                req,
                failProfile
                    ? {'message': 'Private fixture profile failure'}
                    : {'username': 'motri_member'},
                status: failProfile ? 400 : 200);
          }
          if (path.endsWith('/activity_notifications')) {
            await notificationGate?.future;
            return response(
                req,
                failNotifications
                    ? {'message': 'Private notification read failure'}
                    : notificationRows,
                status: failNotifications ? 400 : 200);
          }
          return response(req, []);
        }));
    backendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/auth/login')) {
          authCalls++;
          if (loginGate != null) await loginGate!.future;
          if (failLogin) {
            return response(
              req,
              {'error': 'invalid_credentials'},
              status: 401,
            );
          }
          return response(req, session);
        }
        if (path.endsWith('/auth/register')) {
          signups++;
          signupData = jsonDecode(req.body) as Map<String, dynamic>;
          return response(
            req,
            signupSession ? session : {'requires_email_confirmation': true},
          );
        }
        if (path.endsWith('/auth/logout')) return response(req, {});
        if (path.endsWith('/profile/me')) {
          await profileGate?.future;
          return response(
            req,
            failProfile
                ? {'error': 'Private fixture profile failure'}
                : {
                    'success': true,
                    'data': {
                      'id': id,
                      'username': 'motri_member',
                      'display_name':
                          user['full_name']?.toString().trim().isNotEmpty ==
                                  true
                              ? user['full_name'].toString().trim()
                              : 'motri_member',
                      'email': user['email'],
                    }
                  },
            status: failProfile ? 500 : 200,
          );
        }
        if (path.endsWith('/profile/username')) {
          usernameWrites++;
          savedUsername = (jsonDecode(req.body) as Map)['username'] as String;
          await usernameGate?.future;
          return response(
            req,
            failUsername
                ? {'error': 'Private fixture username failure'}
                : {'success': true},
            status: failUsername ? 400 : 200,
          );
        }
        if (path.endsWith('/activity/notifications')) {
          notificationReads++;
          await notificationGate?.future;
          return response(
            req,
            failNotifications
                ? {'error': 'Private notification read failure'}
                : {'data': notificationRows},
            status: failNotifications ? 500 : 200,
          );
        }
        return response(req, {'data': []});
      }),
    );
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendAccessToken: () => backendAuthSession.accessToken,
      backendAccessTokenAsync: () => backendAuthSession.validAccessToken(),
      client: MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/sellers/admin/status')) {
          return response(req, {'error': 'Admin status fixture unavailable'},
              status: 503);
        }
        if (path.endsWith('/profile/me')) {
          await profileGate?.future;
          return response(
            req,
            failProfile
                ? {'error': 'Private fixture profile failure'}
                : {
                    'success': true,
                    'data': {
                      'id': id,
                      'username': 'motri_member',
                      'display_name': 'motri_member',
                      'email': user['email'],
                    }
                  },
            status: failProfile ? 500 : 200,
          );
        }
        if (path.endsWith('/profile/username')) {
          usernameWrites++;
          savedUsername = (jsonDecode(req.body) as Map)['username'] as String;
          await usernameGate?.future;
          return response(
            req,
            failUsername
                ? {'error': 'Private fixture username failure'}
                : {'success': true},
            status: failUsername ? 400 : 200,
          );
        }
        if (path.endsWith('/activity/notifications')) {
          notificationReads++;
          await notificationGate?.future;
          return response(
            req,
            failNotifications
                ? {'error': 'Private notification read failure'}
                : {'data': notificationRows},
            status: failNotifications ? 500 : 200,
          );
        }
        return response(req, {'data': []});
      }),
    );
  });
  setUp(() async {
    await backendAuthSession.logout();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    failLogin = false;
    failVerify = false;
    failProfile = false;
    failNotifications = false;
    failUsername = false;
    authCalls = 0;
    signups = 0;
    otpCalls = 0;
    verifyCalls = 0;
    usernameWrites = 0;
    usernameGate = null;
    profileGate = null;
    notificationGate = null;
    notificationReads = 0;
    notificationRows = [];
    savedUsername = null;
    loginGate = null;
    phoneEnabled = true;
    capabilitiesFailed = false;
    signupSession = false;
    sentPhone = null;
    verifiedCode = null;
    signupData = null;
    trustCache.reset();
    user['phone'] = '+9647715339922';
    user['full_name'] = (user['user_metadata'] as Map)['full_name'];
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  tearDownAll(() async {
    await backendAuthSession.logout();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  });
  Widget host(Widget page, AppLocale locale, bool dark) => MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
      locale: locale.locale,
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!),
      home: Directionality(
          textDirection: locale.direction,
          child: AuthCapabilitiesScope(loader: capabilityLoader, child: page)));
  void size(WidgetTester tester) {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
  }

  Future<void> account(WidgetTester tester, AppLocale locale, bool dark) async {
    size(tester);
    appLocaleNotifier.value = locale;
    AppColors.isDark = dark;
    await tester.pumpWidget(host(
        const Scaffold(body: SafeArea(child: AccountTab())), locale, dark));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
  }

  Finder field(String name) => find.byKey(ValueKey('auth_$name'));
  final submit = find.byKey(const ValueKey('auth_submit'));
  final phoneSubmit = find.byKey(const ValueKey('auth_phone_submit'));

  testWidgets('account removes user profile row and exposes push settings',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, false);

    expect(find.text(t('account_user_profile')), findsNothing);
    final pushSettings = find.text(t('settings_push_notifications'));
    await reveal(tester, pushSettings);
    await tester.tap(pushSettings);
    await frames(tester);

    expect(find.text(t('ui_notification_preferences_note')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  test(
      'auth feedback and OTP normalization preserve useful, localized failures',
      () {
    expect(
        authFeedbackKey(
            const AuthException('private', code: 'invalid_credentials')),
        'login_wrong_credentials');
    expect(authFeedbackKey(const AuthException('private', statusCode: '429')),
        'ui_auth_rate_limit');
    expect(
        authFeedbackKey(
            const FunctionException(status: 401, details: 'private')),
        'ui_auth_failed');
    expect(
        authFeedbackKey(const FunctionException(
            status: 400, details: {'code': 'invalid_credentials'})),
        'login_wrong_credentials');
    expect(authFeedbackKey(TimeoutException('private')), 'ui_auth_network');
    expect(authFeedbackKey(const AuthException('private', code: 'otp_expired')),
        'ui_auth_otp_expired');
    expect(normalizedOtpCode('١٢٣ ٤٥٦'), '123456');
    expect(normalizedOtpCode('۱۲۳۴۵۶'), '123456');
    expect(normalizedOtpCode('123a456'), isNull);
    expect(normalizedOtpCode('12345'), isNull);
    expect(validAuthEmail('member@example.com'), isTrue);
    expect(validAuthEmail('member@'), isFalse);
  });
  for (final locale in AppLocale.values) {
    for (final latin in [true, false]) {
      testWidgets('account header direction ${locale.code} latin=$latin',
          (tester) async {
        final previous = user['user_metadata'];
        addTearDown(() => user['user_metadata'] = previous);
        final name = latin
            ? 'MOTRI automotive community member with a long display name'
            : 'عضو مجتمع السيارات والبيع والشراء باسم طويل للتجربة';
        user['user_metadata'] = {'full_name': name};
        await tester.runAsync(signIn);
        await account(tester, locale, locale == AppLocale.ku);
        final heading = find.text(name);
        expect(heading, findsOneWidget);
        expect(tester.widget<Text>(heading).textDirection,
            latin ? TextDirection.ltr : TextDirection.rtl);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(
            tester, latin ? 'ACCOUNT_NAME_LATIN' : 'ACCOUNT_NAME_ARABIC');
        await finish(tester);
      });
    }
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final mode in ['login', 'signup', 'signed-in', 'profile']) {
        testWidgets('${locale.code} account $mode dark=$dark', (tester) async {
          size(tester);
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (mode == 'signed-in' || mode == 'profile') {
            await tester.runAsync(signIn);
          }
          await tester.pumpWidget(host(
              mode == 'profile'
                  ? const UserProfilePage()
                  : const Scaffold(body: SafeArea(child: AccountTab())),
              locale,
              dark));
          await frames(tester);
          if (mode == 'signup') {
            await reveal(tester, find.text(t('login_no_account')));
            await tester.tap(find.text(t('login_no_account')));
            await frames(tester);
            expect(field('name'), findsOneWidget);
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await frames(tester);
          }
          if (mode == 'login' || mode == 'signup') {
            final labels = [
              mode == 'login' ? t('ui_login_identifier') : t('login_email'),
              if (mode == 'signup') t('login_username')
            ];
            for (final label in labels) {
              expect(
                  tester
                      .renderObject<RenderParagraph>(find.text(label))
                      .didExceedMaxLines,
                  isFalse,
                  reason:
                      'Auth field names must remain readable with bundled fonts');
            }
            if (mode == 'login') {
              expect(
                  tester
                      .renderObject<RenderParagraph>(
                          find.text(t('login_email_or_username')))
                      .didExceedMaxLines,
                  isFalse);
            }
            if (mode == 'signup') {
              expect(find.text(t('login_username_rule')), findsOneWidget);
              expect(
                  tester
                      .renderObject<RenderParagraph>(
                          find.text(t('login_username_rule')))
                      .didExceedMaxLines,
                  isFalse);
            }
          }
          if (mode == 'signed-in') {
            await currentTypographyCheckpoint(tester, 'ACCOUNT_HEADER');
            await reveal(tester, find.text(t('account_sell_car')));
            final action = find
                .ancestor(
                    of: find.text(t('account_sell_car')),
                    matching: find.byType(InkWell))
                .first;
            expect(tester.getSize(action).height, lessThan(120),
                reason:
                    'Enlarged-text quick actions should remain compact, readable rows');
          }
          await currentTypographyCheckpoint(
              tester, 'ACCOUNT_${mode.toUpperCase().replaceAll('-', '_')}');
          if (const bool.fromEnvironment('UI_ACCOUNT_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark &&
              mode == 'login') {
            debugPrint('UI_ACCOUNT_LOGIN_REVIEW_READY');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 15)));
          }
          if (const bool.fromEnvironment('UI_ACCOUNT_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark &&
              mode == 'signed-in') {
            debugPrint('UI_ACCOUNT_REVIEW_READY');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 15)));
          }
          if (const bool.fromEnvironment('UI_ACCOUNT_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark &&
              mode == 'profile') {
            debugPrint('UI_PROFILE_REVIEW_READY');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 15)));
          }
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 7; i++) {
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -300));
            await frames(tester);
            expect(tester.takeException(), isNull);
          }
          if (mode == 'profile' || mode == 'signed-in') {
            expect(
                find.descendant(
                    of: find.byType(AccountNavigationTile).first,
                    matching: find.byIcon(Icons.chevron_right_rounded)),
                findsOneWidget);
          }
          expect(find.textContaining('Private fixture'), findsNothing);
          await finish(tester);
        });
      }
    }
    testWidgets(
        '${locale.code} invalid auth values stay inline and do not send requests',
        (tester) async {
      await account(tester, locale, false);
      await reveal(tester, submit);
      await tester.tap(submit);
      await frames(tester);
      expect(find.text(t('wanted')), findsWidgets);
      expect(authCalls, 0);
      await reveal(tester, find.text(t('login_no_account')));
      await tester.tap(find.text(t('login_no_account')));
      await frames(tester);
      await tester.enterText(field('name'), 'Member');
      await tester.enterText(field('username'), '!');
      await tester.enterText(field('email'), 'bad@');
      await tester.enterText(field('password'), '123');
      await reveal(tester, submit);
      await tester.tap(submit);
      await frames(tester);
      expect(find.text(t('ui_auth_invalid_email')), findsOneWidget);
      expect(signups, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('failed sign-in keeps draft and prevents overlapping requests',
      (tester) async {
    await account(tester, AppLocale.en, false);
    failLogin = true;
    await tester.enterText(field('email'), 'member@example.com');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    loginGate = Completer<void>();
    await tester.tap(submit);
    await frames(tester);
    expect(authCalls, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    loginGate!.complete();
    await frames(tester);
    expect(find.text(t('login_wrong_credentials')), findsOneWidget);
    expect(find.textContaining('Private fixture'), findsNothing);
    expect(tester.widget<TextFormField>(field('password')).controller!.text,
        'password123');
    failLogin = false;
    loginGate = null;
    await reveal(tester, submit);
    await tester.tap(submit);
    await frames(tester);
    expect(backendAuthSession.user, isNotNull);
    expect(find.byKey(const ValueKey('account_guest')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('username sign-in exchanges the local fixture session',
      (tester) async {
    await account(tester, AppLocale.en, false);
    await tester.enterText(field('email'), 'Motri_User');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
    await tester.tap(submit);
    await networkUntil(tester, () => backendAuthSession.user != null);
    await frames(tester);
    expect(backendAuthSession.user, isNotNull);
    expect(authCalls, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('signup confirmation returns to sign-in with normalized metadata',
      (tester) async {
    await account(tester, AppLocale.en, false);
    await reveal(tester, find.text(t('login_no_account')));
    await tester.tap(find.text(t('login_no_account')));
    await frames(tester);
    await tester.enterText(field('name'), ' Member ');
    await tester.enterText(field('username'), 'Motri_User');
    await tester.enterText(field('email'), 'member@example.com');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
    await tester.tap(submit);
    await networkUntil(tester, () => signups > 0);
    await frames(tester);
    expect(signups, 1);
    expect(signupData!['username'], 'motri_user');
    expect(find.text(t('login_account_created_mail')), findsOneWidget);
    expect(field('name'), findsNothing);
    expect(tester.widget<TextFormField>(field('password')).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'OTP validates locally, retains failed code and verifies localized digits',
      (tester) async {
    await account(tester, AppLocale.en, true);
    final phone = find.widgetWithText(TextFormField, t('field_iraqi_phone'));
    await reveal(tester, phone);
    await tester.enterText(phone, '٠٧٧١٥٣٣٩٩٢٢');
    await reveal(tester, phoneSubmit);
    await tester.tap(phoneSubmit);
    await frames(tester);
    expect(otpCalls, 1);
    expect(sentPhone, '+9647715339922');
    expect(find.byType(OtpVerificationDialog), findsOneWidget);
    if (const bool.fromEnvironment('UI_ACCOUNT_REVIEW_HOLD') ||
        const bool.fromEnvironment('UI_ACCOUNT_OTP_REVIEW_HOLD')) {
      debugPrint('UI_ACCOUNT_OTP_REVIEW_READY');
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
    }

    await tester.enterText(field('otp'), '١٢٣');
    await tester.tap(find.text(t('login_verify')));
    await frames(tester);
    expect(verifyCalls, 0);
    failVerify = true;
    await tester.enterText(field('otp'), '١٢٣٤٥٦');
    await tester.tap(find.text(t('login_verify')));
    await frames(tester);
    expect(find.text(t('ui_auth_otp_expired')), findsOneWidget);
    expect(find.textContaining('Private fixture'), findsNothing);
    expect(
        tester.widget<TextFormField>(field('otp')).controller!.text, '١٢٣٤٥٦');
    failVerify = false;
    await tester.enterText(field('otp'), '۱۲۳۴۵۶');
    await tester.tap(find.text(t('login_verify')));
    await frames(tester);
    expect(verifiedCode, '123456');
    expect(verifyCalls, 2);
    expect(find.byType(OtpVerificationDialog), findsNothing);
    expect(Supabase.instance.client.auth.currentUser, isNotNull);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Profile delayed read ${locale.code} dark=$dark',
          (tester) async {
        size(tester);
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await tester.runAsync(signIn);
        profileGate = Completer<void>();
        failProfile = dark;
        await tester.pumpWidget(host(const UserProfilePage(), locale, dark));
        await frames(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('motri_member'), findsNothing);
        expect(find.text(t('ui_load_error_title')), findsNothing);
        await currentTypographyCheckpoint(tester, 'PROFILE_LOADING');
        profileGate!.complete();
        await frames(tester);
        if (dark) {
          expect(find.text(t('ui_load_error_title')), findsOneWidget);
          failProfile = false;
          profileGate = null;
          await tester.tap(find.text(t('ui_retry')));
          await frames(tester);
        }
        expect(
            find.text(
                t('ui_profile_greeting').replaceAll('{name}', 'motri_member')),
            findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  }

  testWidgets('profile load retries and Favorites opens the saved-list screen',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    await tester.runAsync(signIn);
    failProfile = true;
    await tester.pumpWidget(host(const UserProfilePage(), AppLocale.en, false));
    await frames(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    failProfile = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    final saved = find.text(t('account_favorites'));
    await reveal(tester, saved);
    await tester.tap(saved);
    await frames(tester);
    expect(find.byType(FavoritesPage), findsOneWidget);
    expect(find.byType(SectionPage), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('notification count failure does not block message navigation',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, true);
    failNotifications = true;
    final chat = find.text(t('account_chat'));
    await reveal(tester, chat);
    await tester.tap(chat);
    await frames(tester);
    expect(find.text(t('ui_unread_unavailable')), findsOneWidget);
    await tester.tap(find.text(t('chat_messages_title')));
    await frames(tester);
    expect(find.byType(MyMessagesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'message hub delayed count does not block destinations or duplicate opens',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, false);
    notificationGate = Completer<void>();
    final chat = find.text(t('account_chat'));
    await reveal(tester, chat);
    final open = tester
        .widget<InkWell>(
            find.ancestor(of: chat, matching: find.byType(InkWell)).first)
        .onTap!;
    open();
    open();
    await frames(tester);
    expect(find.text(t('chat_messages_title')), findsOneWidget);
    expect(notificationReads, 1);
    await tester.tap(find.text(t('chat_messages_title')));
    await frames(tester);
    expect(find.byType(MyMessagesPage), findsOneWidget);
    notificationGate!.complete();
    await frames(tester);
    expect(find.text(t('chat_hub_desc')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Message hub ${locale.code} dark=$dark loading error retry',
          (tester) async {
        await tester.runAsync(signIn);
        await account(tester, locale, dark);
        notificationGate = Completer<void>();
        final chat = find.text(t('account_chat'));
        await reveal(tester, chat);
        await tester.tap(chat);
        await frames(tester);
        expect(find.byType(MessageHubSheet), findsOneWidget);
        expect(find.text(t('chat_messages_title')), findsOneWidget);
        expect(find.text(t('ui_loading_title')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'MESSAGE_HUB_LOADING');
        failNotifications = true;
        notificationGate!.complete();
        await frames(tester);
        expect(find.text(t('ui_unread_unavailable')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'MESSAGE_HUB_ERROR');
        failNotifications = false;
        notificationRows = [
          {'id': 'one', 'read_at': null},
          {'id': 'two', 'read_at': null},
          {'id': 'read', 'read_at': '2026-10-01'}
        ];
        await tester.tap(find.byTooltip(t('ui_retry')));
        await frames(tester);
        expect(find.text(t('ui_unread_count').replaceAll('{count}', '2')),
            findsOneWidget);
        expect(notificationReads, 2);
        await currentTypographyCheckpoint(tester, 'MESSAGE_HUB_READY');
        await tester.tap(find.text(t('chat_messages_title')));
        await frames(tester);
        expect(find.byType(MyMessagesPage), findsOneWidget);
        expect(find.byType(MessageHubSheet), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  }
  testWidgets('message hub hides expired counts after same-account return',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, true);
    notificationGate = Completer<void>();
    final chat = find.text(t('account_chat'));
    await reveal(tester, chat);
    await tester.tap(chat);
    await frames(tester);
    await tester.runAsync(signOut);
    await frames(tester);
    await tester.runAsync(signIn);
    await frames(tester);
    notificationRows = [
      {'id': 'old', 'read_at': null}
    ];
    notificationGate!.complete();
    await frames(tester);
    expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
    expect(find.text(t('chat_messages_title')), findsNothing);
    expect(find.text(t('ui_unread_count').replaceAll('{count}', '1')),
        findsNothing);
    final sheetContext = tester.element(find.byType(MessageHubSheet));
    await tester.tap(find
        .byTooltip(MaterialLocalizations.of(sheetContext).closeButtonTooltip));
    await frames(tester);
    await reveal(tester, find.text(t('account_chat')));
    await tester.tap(find.text(t('account_chat')));
    await frames(tester);
    expect(find.text(t('chat_messages_title')), findsOneWidget);
    await tester.tap(find.text(t('chat_hub_desc')));
    await frames(tester);
    expect(find.byType(ActivityNotificationsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'username validation retains input until valid and hides backend errors',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, false);
    failUsername = true;
    final edit = find.text(t('account_username_login'));
    await reveal(tester, edit);
    await tester.tap(edit);
    await frames(tester);
    final input = find.byType(TextFormField);
    await tester.enterText(input, '!');
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(usernameWrites, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(input, 'New_User');
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(usernameWrites, 1);
    expect(find.text(t('ui_username_save_failed')), findsOneWidget);
    expect(find.byType(UsernameEditorDialog), findsOneWidget);
    expect(tester.widget<TextFormField>(input).controller!.text, 'New_User');
    failUsername = false;
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(usernameWrites, 2);
    expect(savedUsername, 'new_user');
    expect(find.byType(UsernameEditorDialog), findsNothing);
    expect(find.textContaining('Private fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Username recovery ${locale.code} dark=$dark enlarged',
          (tester) async {
        await tester.runAsync(signIn);
        await account(tester, locale, dark);
        failUsername = true;
        final edit = find.text(t('account_username_login'));
        await reveal(tester, edit);
        await tester.tap(edit);
        await frames(tester);
        final input = find.byKey(const ValueKey('username_editor_input'));
        await tester.enterText(input, 'New_User');
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(find.text(t('ui_username_save_failed')), findsOneWidget);
        expect(
            tester.widget<TextFormField>(input).controller!.text, 'New_User');
        final rules = tester.widget<Text>(find.text(t('misc_username_rule')));
        expect(rules.maxLines, isNull);
        await currentTypographyCheckpoint(tester, 'USERNAME_RECOVERY');
        failUsername = false;
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(usernameWrites, 2);
        expect(savedUsername, 'new_user');
        expect(find.byType(UsernameEditorDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  }
  testWidgets('username pending save guards duplicate calls and stale sessions',
      (tester) async {
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, true);
    final edit = find.text(t('account_username_login'));
    await reveal(tester, edit);
    await tester.tap(edit);
    await frames(tester);
    await tester.enterText(
        find.byKey(const ValueKey('username_editor_input')), 'New_User');
    usernameGate = Completer<void>();
    final action = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, t('common_save')))
        .onPressed!;
    action();
    action();
    await frames(tester);
    expect(usernameWrites, 1);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, t('common_cancel')))
            .onPressed,
        isNull);
    await tester.runAsync(signOut);
    await frames(tester);
    await tester.runAsync(signIn);
    await frames(tester);
    usernameGate!.complete();
    await frames(tester);
    expect(find.byType(UsernameEditorDialog), findsOneWidget);
    expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, t('common_save')))
            .onPressed,
        isNull);
    expect(find.text(t('misc_username_saved')), findsNothing);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final pending in [false, true]) {
    testWidgets(
        'username ${pending ? 'disposal during save' : 'focused cancellation'} stays safe',
        (tester) async {
      await tester.runAsync(signIn);
      await account(tester, AppLocale.en, false);
      final edit = find.text(t('account_username_login'));
      await reveal(tester, edit);
      await tester.tap(edit);
      await frames(tester);
      final input = find.byKey(const ValueKey('username_editor_input'));
      await tester.tap(input);
      await tester.enterText(input, 'Retained_User');
      if (pending) {
        usernameGate = Completer<void>();
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(usernameWrites, 1);
        await tester.pumpWidget(const SizedBox());
        usernameGate!.complete();
      } else {
        await tester.tap(find.text(t('common_cancel')));
      }
      await frames(tester);
      expect(find.byType(UsernameEditorDialog), findsNothing);
      expect(usernameWrites, pending ? 1 : 0);
      expect(find.text(t('misc_username_saved')), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('sign-out returns account to a cleared password form',
      (tester) async {
    await account(tester, AppLocale.en, false);
    await tester.enterText(field('email'), 'member@example.com');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    await tester.tap(submit);
    await frames(tester);
    final logout = find.text(t('account_sign_out'));
    await reveal(tester, logout);
    await tester.tap(logout);
    await frames(tester);
    expect(find.byKey(const ValueKey('account_guest')), findsOneWidget);
    expect(tester.widget<TextFormField>(field('password')).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'support FAQ follows locale changes instead of caching first language',
      (tester) async {
    size(tester);
    for (final locale in AppLocale.values) {
      appLocaleNotifier.value = locale;
      await tester.pumpWidget(host(const SupportCenterPage(), locale, false));
      await frames(tester);
      final question = find.text(t('support_q_publish'));
      await reveal(tester, question);
      expect(question, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await finish(tester);
  });
  testWidgets(
      'auth feedback and validation follow locale changes without losing draft',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    failLogin = true;
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => MaterialApp(
              theme: buildAppTheme(Brightness.light),
              locale: locale.locale,
              supportedLocales: const [
                Locale('ar'),
                Locale('ku'),
                Locale('en')
              ],
              localizationsDelegates: appLocalizationsDelegates,
              builder: (context, child) => AppStringsScope(
                  locale: locale,
                  child: Directionality(
                      textDirection: locale.direction,
                      child: MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: TextScaler.linear(1.6)),
                          child: child!))),
              home: AuthCapabilitiesScope(
                  loader: capabilityLoader,
                  child: const Scaffold(body: SafeArea(child: AccountTab()))),
            )));
    await frames(tester);
    await tester.enterText(field('email'), 'member@example.com');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    await tester.tap(submit);
    await frames(tester);
    for (final locale in AppLocale.values) {
      appLocaleNotifier.value = locale;
      await frames(tester);
      expect(find.text(t('login_wrong_credentials')), findsOneWidget);
      expect(tester.widget<TextFormField>(field('email')).controller!.text,
          'member@example.com');
    }
    await reveal(tester, field('password'));
    await tester.showKeyboard(field('password'));
    await frames(tester);
    // Keep the real IME synchronized; synthetic empty input can echo stale text.
    final editable = tester.state<EditableTextState>(find.descendant(
        of: field('password'), matching: find.byType(EditableText)));
    editable.userUpdateTextEditingValue(
        const TextEditingValue(
            text: '', selection: TextSelection.collapsed(offset: 0)),
        SelectionChangedCause.keyboard);
    await frames(tester);
    expect(tester.widget<TextFormField>(field('password')).controller!.text,
        isEmpty);
    await reveal(tester, submit);
    await tester.tap(submit);
    await frames(tester);
    for (final locale in AppLocale.values) {
      appLocaleNotifier.value = locale;
      await frames(tester);
      expect(find.text(t('wanted')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(authCalls, 1);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code} OTP stays usable above keyboard and cancels without verifying',
        (tester) async {
      await account(tester, locale, locale == AppLocale.ku);
      final phone = find.widgetWithText(TextFormField, t('field_iraqi_phone'));
      await reveal(tester, phone);
      await tester.enterText(phone, '07715339922');
      await reveal(tester, phoneSubmit);
      await tester.tap(phoneSubmit);
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('auth_otp')));
      await frames(tester);
      await tester.enterText(find.byKey(const ValueKey('auth_otp')), '12');
      if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
      } else {
        final editable = tester.state<EditableTextState>(find.descendant(
            of: find.byKey(const ValueKey('auth_otp')),
            matching: find.byType(EditableText)));
        for (var attempt = 0;
            attempt < 50 && tester.view.viewInsets.bottom == 0;
            attempt++) {
          editable.requestKeyboard();
          await tester.pump();
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await frames(tester);
      final keyboard =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(keyboard, greaterThan(0));
      await Scrollable.ensureVisible(
          tester.element(find.byKey(const ValueKey('auth_otp'))),
          alignment: .9);
      await frames(tester);
      expect(
          tester.getBottomRight(find.byKey(const ValueKey('auth_otp'))).dy,
          lessThanOrEqualTo(
              tester.getTopLeft(find.text(t('common_cancel'))).dy + 1));
      expect(
          tester.getBottomRight(find.text(t('common_cancel'))).dy,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
                  keyboard));
      await currentTypographyCheckpoint(tester, 'ACCOUNT_OTP');
      await tester.tap(find.text(t('login_verify')));
      await frames(tester);
      expect(verifyCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(t('common_cancel')));
      await frames(tester);
      expect(find.byType(OtpVerificationDialog), findsNothing);
      expect(Supabase.instance.client.auth.currentUser, isNull);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets(
      'email-only account identifies itself by email instead of an unavailable phone',
      (tester) async {
    user['phone'] = '';
    await tester.runAsync(signIn);
    await account(tester, AppLocale.en, true);
    expect(find.text('long.member.address@example.com'), findsOneWidget);
    expect(find.text(t('common_unavailable')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final brightness in Brightness.values) {
    test('loading accent remains visible on common surfaces $brightness', () {
      final theme = buildAppTheme(brightness);
      final foreground = theme.progressIndicatorTheme.color!;
      final backgrounds = [
        theme.scaffoldBackgroundColor,
        theme.colorScheme.primaryContainer,
        theme.filledButtonTheme.style!.backgroundColor!
            .resolve({WidgetState.disabled})!
      ];
      for (final background in backgrounds) {
        final first = foreground.computeLuminance(),
            second = background.computeLuminance();
        final contrast = first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
        expect(contrast, greaterThanOrEqualTo(3),
            reason:
                'Loading activity must be distinguishable from its surface');
      }
    });
  }
  test(
      'public capability read handles enabled, disabled and malformed service responses',
      () async {
    var good = true;
    final client = MockClient((request) async {
      expectSync(request.method, 'GET');
      expectSync(request.url.path, '/auth/v1/settings');
      expectSync(request.headers['apikey'], 'fixture-public-key');
      return http.Response(
          jsonEncode(good
              ? {
                  'external': {'phone': false, 'email': true}
                }
              : {}),
          200);
    });
    final loaded = await fetchAuthCapabilities(
        baseUrl: 'https://example.test',
        publishableKey: 'fixture-public-key',
        client: client);
    expect(loaded.value!.phoneOtpEnabled, isFalse);
    expect(loaded.value!.emailEnabled, isTrue);
    good = false;
    expect(
        (await fetchAuthCapabilities(
                baseUrl: 'https://example.test',
                publishableKey: 'fixture-public-key',
                client: client))
            .value,
        isNull);
  });
  testWidgets(
      'disabled phone provider presents an accurate alternative instead of a broken SMS action',
      (tester) async {
    phoneEnabled = false;
    await account(tester, AppLocale.en, false);
    final status = find.text(t('ui_phone_unavailable'));
    await reveal(tester, status);
    if (const bool.fromEnvironment('UI_ACCOUNT_PHONE_DISABLED_REVIEW_HOLD')) {
      debugPrint('UI_ACCOUNT_DISABLED_PHONE_REVIEW_READY');
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
    }
    expect(status, findsOneWidget);
    expect(phoneSubmit, findsNothing);
    expect(find.widgetWithText(TextFormField, t('field_iraqi_phone')),
        findsNothing);
    expect(otpCalls, 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('failed capability check retries without clearing credentials',
      (tester) async {
    capabilitiesFailed = true;
    await account(tester, AppLocale.en, true);
    await tester.enterText(field('email'), 'member@example.com');
    final retry = find.text(t('ui_retry'));
    await reveal(tester, retry);
    expect(find.text(t('ui_auth_options_failed')), findsOneWidget);
    expect(phoneSubmit, findsNothing);
    capabilitiesFailed = false;
    await tester.tap(retry);
    await frames(tester);
    expect(phoneSubmit, findsOneWidget);
    expect(tester.widget<TextFormField>(field('email')).controller!.text,
        'member@example.com');
    expect(otpCalls, 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'autoconfirmed signup enters the account without a confirmation-only notice',
      (tester) async {
    signupSession = true;
    await account(tester, AppLocale.en, false);
    await reveal(tester, find.text(t('login_no_account')));
    await tester.tap(find.text(t('login_no_account')));
    await frames(tester);
    await tester.enterText(field('name'), 'Member');
    await tester.enterText(field('username'), 'motri_user');
    await tester.enterText(field('email'), 'member@example.com');
    await tester.enterText(field('password'), 'password123');
    await reveal(tester, submit);
    await tester.tap(submit);
    await networkUntil(tester, () => backendAuthSession.user != null);
    expect(find.byKey(const ValueKey('account_guest')), findsNothing);
    expect(find.text(t('login_account_created_mail')), findsNothing);
    expect(signups, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code} signup name follows writing direction without changing identifiers',
        (tester) async {
      await account(tester, locale, false);
      await reveal(tester, find.text(t('login_no_account')));
      await tester.tap(find.text(t('login_no_account')));
      await frames(tester);
      for (final sample in [
        'MOTRI Member',
        '\u0639\u0644\u064a',
        '\u0633\u06d5\u06cc\u0627\u0631\u06d5'
      ]) {
        await tester.enterText(field('name'), sample);
        await frames(tester);
        expect(
            tester
                .widget<TextField>(find.descendant(
                    of: field('name'), matching: find.byType(TextField)))
                .textDirection,
            sample.startsWith('MOTRI') ? TextDirection.ltr : TextDirection.rtl);
      }
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: field('email'), matching: find.byType(TextField)))
              .textDirection,
          TextDirection.ltr);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: field('username'), matching: find.byType(TextField)))
              .textDirection,
          TextDirection.ltr);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: field('password'), matching: find.byType(TextField)))
              .textDirection,
          TextDirection.ltr);
      await tester.enterText(field('name'), '');
      await frames(tester);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: field('name'), matching: find.byType(TextField)))
              .textDirection,
          locale.direction);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
}
