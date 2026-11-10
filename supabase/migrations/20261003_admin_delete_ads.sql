-- =====================================================================
-- MOTRI IQ — إصلاح حذف الإعلانات للأدمن
-- الملف: supabase/migrations/20261003_admin_delete_ads.sql
-- الحالة: نهائي — جاهز للنسخ المباشر في Supabase SQL Editor
-- قابل لإعادة التشغيل (idempotent) بالكامل.
-- =====================================================================
--
-- تشخيص مسبق (مقيس، غير مفترض)
-- --------------------------------
--   cars          DELETE -> 200 بدون حذف   (RLS لا تسمح بـ DELETE)
--   jobs          DELETE -> 200 بدون حذف   (RLS لا تسمح بـ DELETE)
--   market_items  DELETE -> 401            (لا صلاحية DELETE أصلاً)
--   admin RPC     POST   -> 404 PGRST202    (الدالة غير موجودة)
--
-- سبب PGRST202 الجذري
-- --------------------
-- 1) الدالة لم تكن مُنشأة في القاعدة.
-- 2) PostgREST يخزّن قائمة الدوال في "schema cache" ولا يرى دالة جديدة
--    حتى يصله إشعار إعادة التحميل. 13 من 14 مايجريشن في هذا المشروع
--    تنتهي بـ `NOTIFY pgrst, 'reload schema'` — وبدونه يبقى PGRST202
--    حتى لو نُفِّذت التعريفات بنجاح. القسم 6 يعالج هذا.
--
-- لماذا RPC بدل RLS policies على الجداول
-- -------------------------------------
-- لا يمكن حصر السياسات الموجودة حالياً على الجداول الثلاثة من خارج
-- القاعدة (PostgREST لا يعرض pg_policies). ومنح GRANT DELETE لفتح
-- سياسات جديدة خطر: لو وُجدت سياسة DELETE أوسع مما نراه، فإن GRANT
-- يفعّلها فوراً. لذلك لا نلمس صلاحيات الجداول إطلاقاً، ونستخدم مساراً
-- واحداً مُراجَعاً داخل دالة.
--
--    * الدالة SECURITY DEFINER فتتجاوز RLS والسياسات عمداً.
--    * مُعرّف الجدول يُقارَن بقائمة بيضاء داخل الدالة قبل بناء الاستعلام.
--    * لا grant جديد على cars / market_items / jobs.
--    * المستخدم العادي لا يستطيع الحذف: لا execute لـ anon، ولا execute
--      لـ authenticated privileges، و auth.uid() غير الموجود في
--      app_admins يُرفض بـ reason = 'not_admin'.
--
-- لا يُحذف ولا يُعدَّل أي صف قائم أثناء هذا الملف.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) سجل التدقيق (بلا بيانات، جدول فارغ فقط)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_ad_deletions (
  id         bigserial PRIMARY KEY,
  ad_table   text        NOT NULL,
  ad_id      uuid        NOT NULL,
  admin_id   uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  deleted_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admin_ad_deletions IS
  'سجل تدقيق لعمليات حذف الإعلانات التي نفّذها الأدمن.';

ALTER TABLE public.admin_ad_deletions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'admin_ad_deletions_admin_id_fkey'
  ) THEN
    ALTER TABLE public.admin_ad_deletions
      ADD CONSTRAINT admin_ad_deletions_admin_id_fkey
      FOREIGN KEY (admin_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

-- قراءة السجل للأدمن فقط.
DROP POLICY IF EXISTS "admins can read ad deletions" ON public.admin_ad_deletions;
CREATE POLICY "admins can read ad deletions" ON public.admin_ad_deletions
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

GRANT SELECT ON public.admin_ad_deletions TO authenticated;


-- ---------------------------------------------------------------------
-- 2) تسجيل الأدمن (idempotent — لا يفعل شيئاً إن كان موجوداً)
-- ---------------------------------------------------------------------
INSERT INTO public.app_admins (user_id)
VALUES ('14f652d6-e797-4c38-980c-e535c10d36b2')
ON CONFLICT (user_id) DO NOTHING;


-- ---------------------------------------------------------------------
-- 3) دالة الحذف الإداري.
--
--    تُرجع jsonb بدل integer عمداً:
--      * السلوك حتمي ويمكن اختباره (لا حاجة لمطابقة نصوص استثناءات).
--      * الواجهة تستطيع عرض سبب الرفض بدقة.
--      * لا استثناءات ولا rollback — لا أثر جانبي على أي شيء.
--
--    أمثلة الإرجاع:
--      {"ok": true,  "deleted": 1, "reason": null}
--      {"ok": false, "deleted": 0, "reason": "not_admin"}
--      {"ok": false, "deleted": 0, "reason": "table_not_allowed"}
--      {"ok": false, "deleted": 0, "reason": "not_found"}
--
--    سبب DROP قبل CREATE: الإصدار الأول أعاد integer، وPostgreSQL
--    يرفض تغيير نوع الإرجاع في CREATE OR REPLACE. الحذف ثم الإنشاء
--    يجعل الملف قابلاً لإعادة التشغيل في أي حالة.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_delete_ad(text, uuid);

CREATE FUNCTION public.admin_delete_ad(p_table text, p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin   uuid    := auth.uid();
  v_deleted integer := 0;
BEGIN
  -- (أ) جلسة مسجّلة الدخول فقط — anon يُرفض هنا.
  IF v_admin IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'deleted', 0,
                              'reason', 'not_authenticated');
  END IF;

  -- (ب) يجب أن يكون مدرجاً في app_admins.
  IF NOT EXISTS (
        SELECT 1 FROM public.app_admins WHERE user_id = v_admin
      ) THEN
    RETURN jsonb_build_object('ok', false, 'deleted', 0,
                              'reason', 'not_admin');
  END IF;

  -- (ج) القائمة البيضاء — الحماية الأساسية قبل بناء أي استعلام.
  IF p_table IS NULL
     OR NOT (p_table = ANY (ARRAY['cars', 'market_items', 'jobs'])) THEN
    RETURN jsonb_build_object('ok', false, 'deleted', 0,
                              'reason', 'table_not_allowed');
  END IF;

  IF p_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'deleted', 0,
                              'reason', 'bad_id');
  END IF;

  -- (د) الحذف. %I يهرّب المعرّف، ولا يُبنى إلا بعد اجتياز (ج).
  EXECUTE format('DELETE FROM public.%I WHERE id = $1', p_table)
    USING p_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- (هـ) التدقيق — فقط عند حذف فعلي.
  IF v_deleted > 0 THEN
    INSERT INTO public.admin_ad_deletions (ad_table, ad_id, admin_id)
    VALUES (p_table, p_id, v_admin);
  END IF;

  RETURN jsonb_build_object(
           'ok',      v_deleted > 0,
           'deleted', v_deleted,
           'reason',  CASE WHEN v_deleted > 0 THEN NULL ELSE 'not_found' END
         );
END;
$$;

COMMENT ON FUNCTION public.admin_delete_ad(text, uuid) IS
  'حذف إعلان واحد للأدمن فقط. جداول مسموحة: cars, market_items, jobs.';


-- ---------------------------------------------------------------------
-- 4) دالة فحص الصلاحية
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.is_admin();

CREATE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 5) الصلاحيات.
--    ملاحظة: EXECUTE مُمنوح للـpublic افتراضياً على أي دالة جديدة،
--    لذلك يُسحب أولاً صراحةً قبل منح authenticated.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_delete_ad(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_delete_ad(text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_ad(text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;


-- =====================================================================
-- 6) إصلاح PGRST202 — إعادة تحميل مخطط PostgREST.
--
--    بدون هذا السطر يستمر التطبيق في الرد:
--        404 PGRST202 "Could not find the function ..."
--    حتى لو نُفِّذ كل ما سبق بنجاح.
-- =====================================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================================
-- 7) اختبارات بعد التنفيذ — نفّذها في SQL Editor واقرأ النتائج.
-- =====================================================================

-- 7.1) الدالة موجودة وأنها SECURITY DEFINER(path مثبّت) وصلاحياتها.
SELECT p.proname,
       p.prorettype::regtype            AS returns,
       p.prosecdef                     AS security_definer,
       p.proconfig                     AS search_path,
       p.proacl                        AS acl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('admin_delete_ad', 'is_admin');
-- المتوقّع: admin_delete_ad | jsonb | t | {search_path=public, pg_temp}

-- 7.2) الأدمن مسجّل.
SELECT user_id, added_at FROM public.app_admins
WHERE user_id = '14f652d6-e797-4c38-980c-e535c10d36b2';
-- المتوقّع: صف واحد.

-- 7.3) اختبار المستخدم العادي: أنت داخل SQL Editor، فأنت postgres
--       وليس auth.uid(). يجب أن يُرجع reason = not_authenticated
--       وألا يحذف شيئاً.
SELECT public.admin_delete_ad('cars', gen_random_uuid()) AS as_normal_user;
-- المتوقّع: {"ok": false, "deleted": 0, "reason": "not_authenticated"}

-- 7.4) اختبار القائمة البيضاء (لا يحذف شيئاً — جدول غير مسموح).
SELECT public.admin_delete_ad('profiles', gen_random_uuid()) AS as_profiles;
-- المتوقّع: {"ok": false, "deleted": 0, "reason": "table_not_allowed"}

-- 7.5) اختبار جدول مسموح بمعرّف غير موجود (لا يحذف شيئاً).
SELECT public.admin_delete_ad('jobs', gen_random_uuid()) AS as_missing_row;
-- المتوقّع: {"ok": false, "deleted": 0, "reason": "not_found"}

-- 7.6) بيانات الإعلانات سليمة بعد كل الاختبارات.
SELECT 'cars' AS t, count(*) FROM public.cars
UNION ALL SELECT 'market_items', count(*) FROM public.market_items
UNION ALL SELECT 'jobs',         count(*) FROM public.jobs;
-- المتوقّع حالياً: 5 / 3 / 3

-- 7.7) سجل التدقيق يجب أن يبقى فارغاً (كل الاختبارات السابقة جافة).
SELECT count(*) AS audit_rows FROM public.admin_ad_deletions;
-- المتوقّع: 0

-- 7.8) بيانات المستخدمين لم تُمَس.
SELECT count(*) AS profiles FROM public.profiles;
SELECT count(*) AS auth_users FROM auth.users;
SELECT count(*) AS seller_reviews FROM public.seller_reviews;
