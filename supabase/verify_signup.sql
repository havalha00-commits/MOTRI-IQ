-- =====================================================================
--  التحقق من إنشاء الحساب بعد تنظيف المخطط
--  Supabase → SQL Editor  (دور postgres)
--
--  ⚠ عدّل السطر الثالث: ضع البريد الذي استخدمته في التطبيق.
-- =====================================================================

-- ↓↓↓ استبدل هذا بالبريد الذي سجّلت به ↓↓↓
\set target_email '''YOUR_EMAIL_HERE'''


-- ═══ 1) هل المستخدم أُنشئ في auth.users؟ ═══════════════════════════
SELECT
  id,
  email,
  created_at,
  email_confirmed_at IS NOT NULL AS email_confirmed,
  raw_user_meta_data->>'username'    AS username,
  raw_user_meta_data->>'full_name'   AS full_name
FROM auth.users
WHERE lower(email) = lower(:'target_email');
-- متوقع: صف واحد. فارغ = فشل الإنشاء.


-- ═══ 2) هل تُنشأ صف profiles المقابل؟ ═══════════════════════════════
SELECT
  p.id,
  p.username,
  p.full_name,
  p.activation_code,
  p.created_at
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE lower(u.email) = lower(:'target_email');
-- متوقع: صف واحد بما فيه activation_code = 'PENDING'


-- ═══ 3) هل فشلت الـ trigger بسبب activation_code؟ ══════════════════
--    يبقى القيد موجودًا؟ وهل Lüuckّ لت等多个 مستخدم之后再 colliding؟
SELECT
  conname,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conname = 'profiles_activation_code_key';
-- فارغ  = القيد محذوف  (حالتهاok إنشا��م جديد)
-- صف واحد = القيد باقٍ  (ولذلك كل تسجيل جديد سيفشل بـ 23505)


-- ═══ 4) كم صفًا يحمل PENDING؟ (إن كان القيد موجودًا فواحد فقط) ════
SELECT activation_code, count(*) AS rows_with_this_code
FROM public.profiles
WHERE activation_code = 'PENDING'
GROUP BY activation_code;


-- ═══ 5) حالة الـ triggers على auth.users ═══════════════════════════
SELECT
  t.tgname       AS trigger_name,
  t.tgenabled    AS enabled,
  pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'auth' AND c.relname = 'users'
  AND NOT t.tgisinternal
ORDER BY t.tgname;


-- ═══ 6) سجل أخطاء Postgres الأحدث (لمعرفة سبب أي فشل) ═════════════
--    اختياري: من Dashboard ← Database ← Logs
--    ابحث عن:
--      duplicate key value violates unique constraint
--        "profiles_activation_code_key"
--    أو
--      new row violates row-level security policy
-- ═════════════════════════════════════════════════════════════════════