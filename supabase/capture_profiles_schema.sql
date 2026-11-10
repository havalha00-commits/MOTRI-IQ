-- =====================================================================
--  التقاط المخطط الحقيقي لـ profiles والتسجيل — للقراءة فقط
--  لا يغيّر أي بيانات. لا ينشئ أي object.
--
--  التشغيل: Supabase → SQL Editor  (دور service_role / postgres)
--  النتيجة: نص DDL جاهز لإعادة بناء نفس المخطط على قاعدة جديدة.
--  انسخ الناتج إلى: supabase/migrations/document_profiles_schema.sql
--
--  لماذا هذا الملف: PostgREST forbids schema introspection بمفتاح
--  publishable (يرد 401 Secret API key required)، فلا يمكن استخراج
--  أنواع الأعمدة و DEFAULT و RLS و تعريف الـ trigger بدون مفتاح
--  service_role.
-- =====================================================================

WITH cols AS (
  SELECT c.oid,
         string_agg(
           format('  %I %s%s%s',
                  a.attname,
                  format_type(a.atttypid, a.atttypmod),
                  CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END,
                  COALESCE(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '')
           ),
           E',\n' ORDER BY a.attnum
         ) AS body
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname = 'public' AND c.relname = 'profiles'
  GROUP BY c.oid
),
cons AS (
  SELECT string_agg(
           format('ALTER TABLE public.profiles ADD CONSTRAINT %I %s;',
                  con.conname, pg_get_constraintdef(con.oid)),
           E'\n' ORDER BY con.conname
         ) AS body
  FROM pg_constraint con
  JOIN pg_class c     ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'profiles'
),
idx AS (
  SELECT string_agg(pg_get_indexdef(i.indexrelid) || ';',
                    E'\n' ORDER BY i.indexrelid::regclass::text) AS body
  FROM pg_index i
  JOIN pg_class c     ON c.oid = i.indrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'profiles'
),
trg AS (
  SELECT string_agg(
           format('DROP TRIGGER IF EXISTS %I ON %s;\nCREATE TRIGGER %I\n%s;',
                  t.tgname,
                  format('%I.%I', n.nspname, c.relname),
                  t.tgname,
                  regexp_replace(pg_get_triggerdef(t.oid),
                                 '^CREATE TRIGGER ' || quote_ident(t.tgname) || E'\s+', '  ')),
           E'\n\n' ORDER BY t.tgname
         ) AS body
  FROM pg_trigger t
  JOIN pg_class c     ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE NOT t.tgisinternal
    AND ( (n.nspname = 'public' AND c.relname = 'profiles')
       OR (n.nspname = 'auth'   AND c.relname = 'users') )
),
fn AS (
  SELECT string_agg(
           format('%s;', pg_get_functiondef(p.oid)),
           E'\n\n' ORDER BY p.proname
         ) AS body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname IN (
    SELECT DISTINCT p2.proname
    FROM pg_trigger t
    JOIN pg_class c     ON c.oid = t.tgrelid
    JOIN pg_namespace n2 ON n2.oid = c.relnamespace
    JOIN pg_proc p2     ON p2.oid = t.tgfoid
    WHERE NOT t.tgisinternal
      AND ( (n2.nspname = 'public' AND c.relname = 'profiles')
         OR (n2.nspname = 'auth'   AND c.relname = 'users') )
  )
),
pol AS (
  SELECT string_agg(
           format('CREATE POLICY %I ON public.profiles\n  FOR %s\n  TO %s\n  USING (%s)\n%s;',
                  pol.polname, pol.polcmd, pol.polroles::regrole[],
                  pol.polqual, COALESCE('  WITH CHECK (' || pol.polwithcheck || ')', '')),
           E'\n\n' ORDER BY pol.polname
         ) AS body
  FROM pg_policies pol
  WHERE pol.schemaname = 'public' AND pol.tablename = 'profiles'
)
SELECT
  E'-- ===== مستخرَج آليًا من قاعدة البيانات الحالية =====\n'
|| E'-- profiles @ ' || now()::timestamp(0) || '\n'
|| E'-- متولّد من: supabase/capture_profiles_schema.sql\n\n'

|| E'CREATE TABLE IF NOT EXISTS public.profiles (\n' || cols.body || E'\n);\n\n'

|| COALESCE('-- Foreign keys / unique / check\n' || cons.body || E'\n\n', '')
|| COALESCE('-- Indexes\n'   || idx.body || E'\n\n', '')
|| COALESCE('-- Triggers (profiles + auth.users)\n' || trg.body || E'\n\n', '')
|| COALESCE('-- Trigger functions (نسخة كاملة كما هي)\n' || fn.body  || E'\n\n', '')

|| E'-- ===== Row Level Security =====\n'
|| COALESCE((
     SELECT format('ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;')
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname='public' AND c.relname='profiles' AND c.relrowsecurity
   ), '-- (RLS غير مفعّل على public.profiles)')
|| COALESCE(E'\n' || pol.body || E'\n', E'\n-- (لا توجد سياسات)\n')

|| E'\n-- ===== RLS على auth.users (للاطلاع فقط) =====\n'
|| COALESCE((
     SELECT string_agg(format('ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;'), E'\n')
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname='auth' AND c.relname='users' AND c.relrowsecurity), '')
;