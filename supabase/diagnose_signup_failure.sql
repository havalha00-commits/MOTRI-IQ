-- =====================================================================
--  تشخيص فشل إنشاء الحساب — استعلامات قراءة فقط (لا تغيّر أي بيانات)
--  شغّلها في Supabase → SQL Editor
-- =====================================================================

-- 1) كل الـ triggers الموجودة فعليًا على auth.users
--    هذا هو المفتاح: قد يوجد trigger غير مسجّل في مجلد migrations.
SELECT
  t.tgname                                   AS trigger_name,
  t.tgenabled                                AS enabled,
  pg_get_triggerdef(t.oid)                   AS definition,
  n.nspname || '.' || p.proname              AS function_schema_name,
  p.prosecdef                                AS is_security_definer,
  pg_get_functiondef(p.oid)                  AS function_body
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p      ON p.oid = t.tgfoid
WHERE c.relname = 'users'
  AND n.nspname = 'auth'
  AND NOT t.tgisinternal
ORDER BY t.tgname;


-- 2) بنية جدول app_usernames كما هي في القاعدة فعليًا
SELECT
  a.attname                                   AS column_name,
  format_type(a.atttypid, a.atttypmod)        AS data_type,
  a.attnotnull                                AS not_null,
  pg_get_expr(d.adbin, d.adrelid)             AS default_value
FROM pg_attribute a
JOIN pg_class c     ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE n.nspname = 'public'
  AND c.relname = 'app_usernames'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;


-- 3) القيود (constraints) — تكشف أي عمود NOT NULL بلا قيمة افتراضية
SELECT con.conname, pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class c     ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_usernames';


-- 4) حالة RLS وعدد السياسات على الجدول
SELECT
  c.relrowsecurity  AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  (SELECT count(*) FROM pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename = 'app_usernames') AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'app_usernames';


-- 5) من يملك الـ trigger function وهل يتجاوز RLS فعلًا
SELECT
  p.proname,
  pg_get_userbyid(p.proowner)   AS owner,
  r.rolbypassrls               AS owner_bypasses_rls,
  p.prosecdef                  AS is_security_definer
FROM pg_proc p
JOIN pg_class c     ON c.oid = p.pronamespace
JOIN pg_namespace n ON n.oid = c.oid
JOIN pg_roles r     ON r.oid = p.proowner
WHERE n.nspname = 'public'
  AND p.proname IN ('register_auth_username', 'handle_new_user', 'set_my_username');


-- 6) هل يوجد تعارض أسماء مستخدمين؟ (سبب شائع جدًا للفشل)
SELECT username, count(*) AS uses
FROM public.app_usernames
GROUP BY username
HAVING count(*) > 1;


-- 7) هل الـ trigger يُغلق على كل المستخدمين أم يمرّ؟
--    إذا كان رصيد الصفوف 0 مع وجود مستخدمين في auth.users
--    فمعنى ذلك أن التسجيل معطّل حاليًا.
SELECT
  (SELECT count(*) FROM auth.users)  AS auth_users,
  (SELECT count(*) FROM public.app_usernames) AS usernames_rows;


-- =====================================================================
--  قسم profiles — أُضيف أثناء تشخيص 2026-10-02
--  الاستعلامات السابقة تغطي app_usernames فقط، وكانت هناك فجوة:
--  بنية public.profiles (وهي الهدف الحقيقي للـ trigger) لم تكن
--  موثّقة. هذا القسم يغطّيها بالكامل.
-- =====================================================================

-- 8) أعمدة public.profiles: النوع + NOT NULL + DEFAULT
--   (DEFAULT مهم: يكشف من أين تأتي قيمة 'PENDING')
SELECT
  a.attname                                   AS column_name,
  format_type(a.atttypid, a.atttypmod)        AS data_type,
  a.attnotnull                                AS not_null,
  pg_get_expr(d.adbin, d.adrelid)             AS default_value
FROM pg_attribute a
JOIN pg_class c     ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE n.nspname = 'public'
  AND c.relname = 'profiles'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;


-- 9) كل قيود profiles: PRIMARY KEY / UNIQUE / CHECK / FOREIGN KEY
--    (تعريف profiles_activation_code_key يظهر هنا كاملًا)
SELECT
  con.conname                                 AS constraint_name,
  CASE con.contype
    WHEN 'p' THEN 'PRIMARY KEY'
    WHEN 'u' THEN 'UNIQUE'
    WHEN 'c' THEN 'CHECK'
    WHEN 'f' THEN 'FOREIGN KEY'
    WHEN 'n' THEN 'CHECK (named)'
    ELSE con.contype::text
  END                                         AS constraint_type,
  pg_get_constraintdef(con.oid)               AS definition
FROM pg_constraint con
JOIN pg_class c     ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'profiles'
ORDER BY con.conname;


-- 10) الفهارس على profiles (قد يفرض فهرس فريد شرطًا لا يظهر في القيود)
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'profiles'
ORDER BY indexname;


-- 11) التوزيع الفعلي لقيم activation_code — يوضح أي قيمة استُهلكت
--     (هنا سيظهر أن 'PENDING' مستهلكة مرة واحدة فقط)
SELECT activation_code, count(*) AS rows_with_this_code
FROM public.profiles
GROUP BY activation_code
ORDER BY rows_with_this_code DESC, activation_code;


-- 12) RLS والسياسات على profiles
SELECT
  c.relrowsecurity       AS rls_enabled,
  c.relforcerowsecurity  AS rls_forced,
  (SELECT count(*) FROM pg_policies p
    WHERE p.schemaname='public' AND p.tablename='profiles') AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname='public' AND c.relname='profiles';


-- 13) كل سياسات profiles بنصها الكامل
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public' AND tablename='profiles'
ORDER BY policyname;


-- 14) Triggers على profiles نفسها (إن وجدت)
SELECT
  t.tgname                                   AS trigger_name,
  t.tgenabled                                AS enabled,
  pg_get_triggerdef(t.oid)                   AS definition
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname='public' AND c.relname='profiles' AND NOT t.tgisinternal
ORDER BY t.tgname;


-- =====================================================================
--  قراءة handle_new_user() سطرًا لكل سطر
--  (المخرجات في SQL Editor تُقصّ إذا came كل الدالة في خلية واحدة)
-- =====================================================================

-- 15) كل أسطر الدالة — سطر واحد لكل صف (ابدأ بهذا إن أردت الدالة كاملة)
SELECT g AS line_no,
       (string_to_array(pg_get_functiondef(p.oid), E'\n'))[g] AS line
FROM pg_proc p,
     generate_series(1,
       array_length(string_to_array(pg_get_functiondef(p.oid), E'\n'), 1)) g
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'handle_new_user'
ORDER BY g;


-- 16) الأسطر المهمة فقط: INSERT / الأعمدة / VALUES / COALESCE
--     / activation_code / ON CONFLICT
--     هذه هي الأسطر التي تحسم سبب 23505
SELECT g AS line_no,
       (string_to_array(pg_get_functiondef(p.oid), E'\n'))[g] AS line
FROM pg_proc p,
     generate_series(1,
       array_length(string_to_array(pg_get_functiondef(p.oid), E'\n'), 1)) g
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('handle_new_user', 'register_auth_username')
  AND (string_to_array(pg_get_functiondef(p.oid), E'\n'))[g]
      ~* '(INSERT\s+INTO|VALUES|COALESCE|activation_code|ON\s+CONFLICT|INSERT)'
ORDER BY p.proname, g;