-- إصلاح ظهور إعلانات الوظائف للزائر (read-only fix).
--
-- التشخيص المؤكد من стороны:
--   - INSERT للإعلانات يعمل للمستخدم المسجّل (تم نشر إعلان فعلي بنجاح).
--   - القراءة كـ anon ترجع 0 صف:  Content-Range: */0
--   - عمود is_approved موجود فعلاً في الجدول (أكّدته رسالة Postgres).
--   => RLS مفعّل، لكن لا توجد سياسة SELECT تسمح لـ anon.
--
-- هذا الملف يكتشف السياسات المشكلة تلقائيًا بالاسم والشرط،
-- فلا حاجة لمعرفة أسمائها مسبقًا.
--
-- ملاحظات أمان:
--   - يمسّ سياسات SELECT فقط. لا يمسّ أي سياسة INSERT / UPDATE / DELETE،
--     فإعلان المستخدم المسجّل وصل كما هو ولن يتأثر.
--   - لا يحذف ولا يعدّل أي بيانات، ولا ينفّذ DELETE / TRUNCATE / DROP TABLE.
--   - لا يضيف ولا يحذف أي عمود.
--   - لا يربط الفلترة بـ is_approved، لأن التطبيق لا يرشّح عليه إطلاقًا
--     (استعلام الصفحة: .select().order('created_at'))، فأي شرط إضافي
--     كان سيخفي الإعلان مرتين. القيم تُطبع في الخطوة 5 للتشخيص فقط.

-- ============================================================
-- الخطوة 1) التشخيص: عرض جميع السياسات الحالية على jobs
--          (نفّذ هذه أولاً وشارك الناتج)
-- ============================================================
SELECT policyname,
       permissive,
       roles::text,
       cmd,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'jobs'
ORDER BY cmd, permissive DESC, policyname;

-- ============================================================
-- الخطوة 2) الإصلاح: إزالة قيود القراءة فقط
-- ============================================================
DO $$
DECLARE
  r record;
BEGIN
  -- 2أ) أي سياسة SELECT من نوع RESTRICTIVE
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jobs'
      AND cmd = 'SELECT' AND permissive = 'RESTRICTIVE'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.jobs', r.policyname);
    RAISE NOTICE 'تم إسقاط RESTRICTIVE SELECT: %', r.policyname;
  END LOOP;

  -- 2ب) أي سياسة SELECT مقيّدة بصاحب الإعلان
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jobs'
      AND cmd = 'SELECT'
      AND permissive = 'PERMISSIVE'
      AND qual ~ '(user_id|owner_id|employer_id)'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.jobs', r.policyname);
    RAISE NOTICE 'تم إسقاط SELECT مقيّدة بصاحب الإعلان: %', r.policyname;
  END LOOP;

  -- 2ج) أي سياسة SELECT لا تسمح للزائر أصلًا
  --      (أي أن الأدوار لا تحتوي على anon)
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'jobs'
      AND cmd = 'SELECT'
      AND permissive = 'PERMISSIVE'
      AND NOT (roles @> ARRAY['anon'])
  LOOP
    EXECUTE format('DROP POLICY %I ON public.jobs', r.policyname);
    RAISE NOTICE 'تم إسقاط SELECT لا تسمح لـ anon: %', r.policyname;
  END LOOP;
END $$;

-- ============================================================
-- الخطوة 3) سياسة قراءة عامة واحدة للزائر والمسجّل معًا
-- ============================================================
DROP POLICY IF EXISTS "jobs readable by public" ON public.jobs;
CREATE POLICY "jobs readable by public"
  ON public.jobs
  FOR SELECT
  TO anon, authenticated
  AS PERMISSIVE
  USING (true);

-- ============================================================
-- الخطوة 4) الصلاحيات: قراءة فقط، والكتابة تبقى محمية
-- ============================================================
GRANT SELECT ON public.jobs TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- الخطوة 5) التحقق النهائي
-- ============================================================
-- 5أ) ما الذي يراه الزائر (يجب أن يكون أكبر من صفر)
BEGIN;
  SET LOCAL ROLE anon;
  SELECT count(*) AS jobs_seen_by_anon FROM public.jobs;
ROLLBACK;

-- 5ب) ما الذي يراه المستخدم المسجّل
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}';
  SELECT count(*) AS jobs_seen_by_authenticated FROM public.jobs;
ROLLBACK;

-- 5ج) العدد الحقيقي في الجدول
SELECT count(*) AS total_jobs FROM public.jobs;

-- 5د) تشخيص is_approved للعلم فقط (لا يغيّر شيئًا)
SELECT is_approved, count(*) AS rows
FROM public.jobs
GROUP BY is_approved
ORDER BY is_approved;

-- policies after the fix
SELECT policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'jobs'
ORDER BY cmd, permissive DESC, policyname;
