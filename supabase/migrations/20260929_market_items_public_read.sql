-- Market items: توحيد قراءة الإعلانات العامة للزائر والمسجّل.
--
-- التشخيص المؤكد:
--   - ads_seen_by_anon         = 3  (يعمل)
--   - ads_seen_by_authenticated = 0  (ممنوع)  ← المشكلة هنا
--   => يوجد على الجدول إما سياسة SELECT من نوع RESTRICTIVE،
--      أو سياسة SELECT مقيّدة بصاحب الإعلان (user_id/owner_id/seller_id).
--
-- هذا الملف يكتشف السياسات المشكلة تلقائيًا بالاسم والشرط،
-- فلا حاجة لمعرفة أسمائها مسبقًا.
--
-- ملاحظات أمان:
--   - يمسّ سياسات SELECT فقط. لا يمسّ أي سياسة INSERT / UPDATE / DELETE،
--     فصلاحيات صاحب الإعلان في التعديل والحذف تبقى كما هي بالضبط.
--   - لا يحذف أي بيانات، ولا ينفّذ DELETE / TRUNCATE / DROP TABLE.

-- ============================================================
-- الخطوة 1) التشخيص: عرض جميع السياسات الحالية
--          (نفّذ هذه أولاً وشارك الناتج — هذه هي القائمة المطلوبة)
-- ============================================================
SELECT policyname,
       permissive,
       roles::text,
       cmd,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'market_items'
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
    WHERE schemaname = 'public' AND tablename = 'market_items'
      AND cmd = 'SELECT' AND permissive = 'RESTRICTIVE'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.market_items', r.policyname);
    RAISE NOTICE 'تم إسقاط RESTRICTIVE SELECT: %', r.policyname;
  END LOOP;

  -- 2ب) أي سياسة SELECT مقيّدة بصاحب الإعلان
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'market_items'
      AND cmd = 'SELECT'
      AND permissive = 'PERMISSIVE'
      AND qual ~ '(user_id|owner_id|seller_id)'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.market_items', r.policyname);
    RAISE NOTICE 'تم إسقاط SELECT مقيّدة بصاحب الإعلان: %', r.policyname;
  END LOOP;
END $$;

-- ============================================================
-- الخطوة 3) سياسة قراءة عامة واحدة للزائر والمسجّل معًا
-- ============================================================
DROP POLICY IF EXISTS "market items readable by public" ON public.market_items;
CREATE POLICY "market items readable by public"
  ON public.market_items
  FOR SELECT
  TO anon, authenticated
  AS PERMISSIVE
  USING (true);

-- ============================================================
-- الخطوة 4) الصلاحيات: قراءة فقط، والكتابة تبقى محمية
-- ============================================================
GRANT SELECT ON public.market_items TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.market_items FROM anon;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- الخطوة 5) التحقق النهائي — يجب أن تكون ads_seen_by_authenticated = 3
-- ============================================================
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}';
SELECT count(*) AS ads_seen_by_authenticated FROM public.market_items;
ROLLBACK;

BEGIN;
SELECT count(*) AS ads_seen_by_anon FROM public.market_items;
ROLLBACK;

SELECT count(*) AS total_ads FROM public.market_items;

-- policies after the fix
SELECT policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'market_items'
ORDER BY cmd, permissive DESC, policyname;
