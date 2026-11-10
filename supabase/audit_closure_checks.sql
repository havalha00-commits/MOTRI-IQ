-- =====================================================================
--  فحوصات إغلاق التدقيق — قراءة فقط (SELECT فقط)
--  Supabase → SQL Editor  (دور postgres)
--
--  يغطي Findings غير المحسومة في تقرير التدقيق الأمني:
--    A-1  · RLS على cars / market_items / jobs / profiles
--    A-2  · الصلاحيات (GRANT) على الجداول الأساسية
--    B-1  · increment_ad_counter — SECURITY DEFINER / search_path / EXECUTE
--    B-2  · Triggers على profiles و auth.users
--    B-4  · حالة إصلاح activation_code
--
--  ⚠ SELECT خالص. لا يكتب ولا يحذف ولا يغيّر شيئًا.
--
--  ── تصحيحات أخطاء SQL (بدون تغيير أي منطق) ─────────────────────
--    1) t.tgenabled من نوع "char" الداخلي → cast إلى ::text،
--       لأن text || "char" غير معرَّف في PostgreSQL.
--    2) B-1: كان الاستعلام الفرعي يشير إلى p2 قبل وجوده في النطاق،
--      .Was خطأ يمنع التنفيذ ← استُبدل بـ array_to_string مباشرة.
--    3) B-1b: كان ARRAY(SELECT unnest(...)) مركّبًا خاطئًا
--       ← استُبدل بـ aclexplode (المصدر الرسمي لصلاحيات الدوال).
--    4) A-2: table_name/grantee نطاقان над sql_identifier
--       ← cast إلى ::text قبل الدمج.
--    5) B-4: كانت لا تُرجع صفًا عند غياب العنصر، فيبدو الفحص
--       فارغًا ← صارت تُرجع رسالة صريحة دائمًا.
-- =====================================================================

-- ═══ A-1 · حالة RLS ═══════════════════════════════════════════════
SELECT 'A-1 · RLS' AS section,
       relname::text AS object,
       CASE WHEN relrowsecurity THEN 'محمي ✓' ELSE '!! غير محمي ✗' END AS result
FROM pg_class
WHERE relname IN ('cars','market_items','jobs','profiles')
ORDER BY 1,2;


-- ═══ A-2 · صلاحيات الجداول (هل يستطيع anon الكتابة؟) ═════════════
SELECT 'A-2 · privileges' AS section,
       table_name::text || ' → ' || grantee::text AS object,
       string_agg(privilege_type::text, ',' ORDER BY privilege_type::text) AS result
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('cars','market_items','jobs','profiles')
  AND grantee IN ('anon','authenticated','PUBLIC')
GROUP BY table_name::text, grantee::text
ORDER BY table_name::text, grantee::text;


-- ═══ B-1 · increment_ad_counter ═══════════════════════════════════
SELECT 'B-1 · ad counter' AS section,
       p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS object,
       'SECURITY DEFINER=' || p.prosecdef::text
       || ' | search_path=' || COALESCE(array_to_string(p.proconfig, ','), 'UNSET ← خطر')
       AS result
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'increment_ad_counter';


-- ═══ B-1b · من يستطيع تنفيذها (acl حقيقي من aclexplode) ═══════════
SELECT 'B-1b · EXECUTE' AS section,
       COALESCE(r.rolname::text, 'PUBLIC') AS object,
       'granted_by=' || pg_get_userbyid(acl.grantor)::text
       || ' | grantable=' || acl.is_grantable::text AS result
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
LEFT JOIN pg_roles r ON r.oid = acl.grantee
WHERE n.nspname = 'public'
  AND p.proname = 'increment_ad_counter'
  AND acl.privilege_type = 'EXECUTE'
ORDER BY 2;


-- ═══ B-2 · triggers على profiles و auth.users ══════════════════════
SELECT 'B-2 · trigger' AS section,
       n.nspname::text || '.' || c.relname::text || ' → ' || t.tgname::text AS object,
       'enabled=' || t.tgenabled::text
       || ' | fn=' || p.proname::text
       || ' | SECURITY DEFINER=' || p.prosecdef::text
       || ' | search_path=' || COALESCE(array_to_string(p.proconfig, ','), 'UNSET')
       AS result
FROM pg_trigger t
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p      ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal
  AND ( (n.nspname='public' AND c.relname='profiles')
     OR (n.nspname='auth'   AND c.relname='users') )
ORDER BY 1,2;


-- ═══ B-2b · دوال إنشاء المستخدم ══════════════════════════════════
SELECT 'B-2b · function' AS section,
       'public.' || p.proname::text AS object,
       'SECURITY DEFINER=' || p.prosecdef::text
       || ' | search_path=' || COALESCE(array_to_string(p.proconfig, ','), '!! بلا search_path')
       AS result
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('handle_new_user', 'register_auth_username', 'on_auth_user_created')
ORDER BY 1,2;


-- ═══ B-4 · حالة إصلاح activation_code ════════════════════════════
SELECT 'B-4 · index' AS section,
       COALESCE(
         (SELECT string_agg(indexname::text || ' :: ' || indexdef, E'\n')
            FROM pg_indexes
           WHERE schemaname='public' AND tablename='profiles'
             AND indexname LIKE '%activation%'),
         '(لا يوجد index يخص activation)') AS result

UNION ALL

SELECT 'B-4b · constraint',
       COALESCE(
         (SELECT conname::text || ' :: ' || pg_get_constraintdef(oid)
            FROM pg_constraint WHERE conname = 'profiles_activation_code_key'),
         '(profiles_activation_code_key غير موجود ✓)')

UNION ALL

SELECT 'B-4c · column',
       COALESCE(
         (SELECT 'default=' || COALESCE(column_default,'NULL')
                 || ' | is_nullable=' || is_nullable
                 || ' | type=' || data_type
            FROM information_schema.columns
           WHERE table_schema='public' AND table_name='profiles'
             AND column_name='activation_code'),
         '(عمود activation_code غير موجود!)');

-- ═══ ملخص سريع: عدّ الجداول غير المحمية ══════════════════════════
SELECT 'SUMMARY · unprotected' AS section,
       'جداول بلا RLS = ' || count(*)::text AS result
FROM pg_class
WHERE relname IN ('cars','market_items','jobs','profiles')
  AND NOT relrowsecurity;