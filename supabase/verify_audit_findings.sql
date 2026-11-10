-- =====================================================================
--  فحوصات تحقق — قراءة فقط (SELECT فقط، لا DDL ولا DML)
--  Supabase → SQL Editor  (دور postgres أو service_role)
--
--  يجيب عن ثلاثة أسئلة في نتيجة واحدة:
--    F1  هل طُبِّق إصلاح activation_code؟
--    F2  هل RLS مفعّل على الجداول الأساسية؟
--    F3  هل DEFAULT الخاص بـ activation_code ما زال 'PENDING'؟
--
--  آمن تمامًا: استعلام SELECT واحد لا يكتب شيئًا.
-- =====================================================================

SELECT 'F1 · index on profiles' AS check_name,
       COALESCE(
         indexname || ' :: ' || indexdef,
         '(لا يوجد أي index يخص activation — الإصلاح غير مطبَّق أو القيد ما زال موجودًا)'
       ) AS result
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'profiles'
  AND indexname LIKE '%activation%'
HAVING count(*) >= 0

UNION ALL

SELECT 'F1b · constraint exists?',
       COALESCE((SELECT conname || ' :: ' || pg_get_constraintdef(oid)
                 FROM pg_constraint WHERE conname = 'profiles_activation_code_key'),
                '(غير موجود — تم حذفه)')
WHERE NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_activation_code_key')

UNION ALL

SELECT 'F2 · RLS status :: ' || relname,
       'relrowsecurity=' || relrowsecurity
       || ' | relforcerowsecurity=' || relforcerowsecurity
       || CASE WHEN relrowsecurity THEN '  [محمي]' ELSE '  [!! غير محمي]' END
FROM pg_class
WHERE relname IN ('cars', 'market_items', 'jobs', 'profiles')

UNION ALL

SELECT 'F3 · activation_code column',
       'default=' || COALESCE(column_default, 'NULL')
       || ' | is_nullable=' || is_nullable
       || ' | type=' || data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
  AND column_name = 'activation_code'

ORDER BY 1;