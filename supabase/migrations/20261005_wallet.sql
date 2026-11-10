-- =====================================================================
-- MOTRI IQ — محفظة المستخدم (رصيد + طلبات تعبئة)
-- الملف: supabase/migrations/20261005_wallet.sql
-- الحالة: نهائي — جاهز للنسخ المباشر في Supabase SQL Editor
-- قابل لإعادة التشغيل (idempotent) بالكامل.
-- =====================================================================
--
-- لماذا هذا الملف
-- ---------------
-- في التطبيق بطاقة «رصيد المحفظة» وخيار «تعبئة المحفظة» كانا نصّين
-- ثابتين («غير مفعّل في هذا الإصدار»). لا يوجد في القاعدة أي جدول محفظة،
-- فهذه أول بنية تخزين لها، ولا تُلمس أي جدول قائم.
--
-- القاعدة الأساسية: الرصيد = مجموع العمليات **المؤكَّدة** فقط
-- -------------------------------------------------------
-- Therefore «pending» لا يزيد الرصيد إطلاقًا، حتى لو أعاد تحميل الصفحة.
-- والخصم من رصيد (إن أُضيف لاحقًا) لا بدّ أن يمرّ بالسياق نفسه:也只有
-- confirmed/rejected_hard affect the sum. `pending` و`rejected` محايدان.
--
-- لماذا RPC للتأكيد بدل صلاحية UPDATE للمستخدم
-- ------------------------------------------
-- لو مُنح المستخدم UPDATE على الجدول لكان بإمكانه كتابة
-- status = 'confirmed' بنفسه、增加 رصيد بلا تحويل ولا مراجعة. لذلك:
--   * SELECT + INSERT فقط للمستخدم (Insert بـ CHECK يفرض pending).
--   * لا UPDATE ولا DELETE للمستخدم إطلاقًا.
--   * التأكيد عبر دالة SECURITY DEFINER تتحقق من app_admins.
-- هذا هو المصدر الوحيد الذي يستطيع تحريك الرصيد.
--
-- المبلغ بالدينار العراقي (integer)، لا USD: لا كسور عشرية في الدينار،
-- ولا مجال لتأخير التقريب في حساب الرصيد. conversions USD→IQD إن احتُوجت
-- تبقى في التطبيق كما هي في formatCurrency.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) جدول عمليات المحفظة
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount      integer     NOT NULL CHECK (amount > 0),
  status      text        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'confirmed', 'rejected')),
  admin_id    uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  admin_note  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  -- عدد صحيح، حتى لا تتراكم Krona الكسرية على 20k عملية.
  CONSTRAINT wallet_amount_is_integer CHECK (amount = trunc(amount)),
  -- `confirmed_at` لا وجود له إلا مع confirmed: يمنع صفاً مؤكَّداً بلا وقت،
  -- وصفاً مرفوضاً يحمل وقت تأكيد فيراه المستخدم كأنه دخل رصيده.
  CONSTRAINT wallet_confirmed_at_matches_status
    CHECK ((status = 'confirmed') = (confirmed_at IS NOT NULL))
);

COMMENT ON TABLE public.wallet_transactions IS
  'عمليات محفظة المستخدم بالدينار العراقي. الرصيد = مجموع الصفوف المؤكَّدة.';

COMMENT ON COLUMN public.wallet_transactions.amount IS
  'المبلغ بالدينار العراقي (integer). يزيد الرصيد فقط عند status = confirmed.';

CREATE INDEX IF NOT EXISTS wallet_transactions_user_created_idx
  ON public.wallet_transactions (user_id, created_at DESC);

-- فهرس مساعِد للتأكيد: يبحث الأدمن في «المعلّقة» فقط.
CREATE INDEX IF NOT EXISTS wallet_transactions_pending_idx
  ON public.wallet_transactions (created_at DESC)
  WHERE status = 'pending';


-- ---------------------------------------------------------------------
-- 2) RLS والصلاحيات
-- ---------------------------------------------------------------------
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

-- SELECT/INSERT فقط. UPDATE و DELETE غير ممنوحين للمستخدم عمداً.
GRANT SELECT, INSERT ON public.wallet_transactions TO authenticated;

-- المستخدم يرى عملياته وحدها.
DROP POLICY IF EXISTS "users read own wallet transactions"
  ON public.wallet_transactions;
CREATE POLICY "users read own wallet transactions"
  ON public.wallet_transactions
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- الأدمن يرى الكل (لتأكيد طلبات التعبئة).
DROP POLICY IF EXISTS "admins read all wallet transactions"
  ON public.wallet_transactions;
CREATE POLICY "admins read all wallet transactions"
  ON public.wallet_transactions
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- الإدراج: للمستخدم لنفسه فقط، و`status` محكوم بـ CHECK فلا يصلح أن
-- يكتب confirmed عند الإدراج (سيرفضه القيد).
DROP POLICY IF EXISTS "users request their own top ups"
  ON public.wallet_transactions;
CREATE POLICY "users request their own top ups"
  ON public.wallet_transactions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);


-- ---------------------------------------------------------------------
-- 3) دالة تأكيد الأدمن
--
--    تُرجع jsonb ع��ل integer عمداً:
--      * السلوك حتمي ويمكن اختباره (لا مطابقة نصوص استثناءات).
--      * الواجهة تعرض سبب الرفض بدقة بدل «فشل غير معروف».
--
--    أمثلة الإرجاع:
--      {"ok": true,  "reason": null,                 "status": "confirmed"}
--      {"ok": false, "reason": "not_authenticated", "status": null}
--      {"ok": false, "reason": "not_admin",         "status": null}
--      {"ok": false, "reason": "bad_status",        "status": null}
--      {"ok": false, "reason": "not_found",         "status": null}
--      {"ok": false, "reason": "already_decided",   "status": "pending"}
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_wallet_decide(uuid, text);

CREATE FUNCTION public.admin_wallet_decide(p_id uuid, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin   uuid := auth.uid();
  v_status  text;
  v_current text;
BEGIN
  -- (أ) جلسة مسجّلة الدخول فقط — anon يُرفض هنا.
  IF v_admin IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated',
                              'status', NULL);
  END IF;

  -- (ب) يجب أن يكون مدرجاً في app_admins.
  IF NOT EXISTS (
        SELECT 1 FROM public.app_admins WHERE user_id = v_admin
      ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_admin',
                              'status', NULL);
  END IF;

  -- (ج) الحالة المسموحة فقط. 'pending' ليست قراراً: هي الحالة الأولى.
  IF p_status IS NULL
     OR NOT (p_status = ANY (ARRAY['confirmed', 'rejected'])) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_status',
                              'status', NULL);
  END IF;

  IF p_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_id',
                              'status', NULL);
  END IF;

  -- (د) لا قرار مرتين على العملية نفسها: متى تأكّدت، لا تُنقض.
  SELECT status INTO v_current
    FROM public.wallet_transactions
   WHERE id = p_id;

  IF v_current IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found',
                              'status', NULL);
  END IF;

  IF v_current <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_decided',
                              'status', v_current);
  END IF;

  -- (هـ) التنفيذ. confirmed_at يُضبط على confirmed فقط، كما يشترط القيد.
  v_status := CASE WHEN p_status = 'confirmed' THEN 'confirmed' ELSE 'rejected' END;

  UPDATE public.wallet_transactions
     SET status      = v_status,
         admin_id    = v_admin,
         confirmed_at = CASE WHEN v_status = 'confirmed' THEN now() ELSE NULL END
   WHERE id = p_id
     AND status = 'pending';

  RETURN jsonb_build_object('ok', true, 'reason', NULL, 'status', v_status);
END;
$$;

COMMENT ON FUNCTION public.admin_wallet_decide(uuid, text) IS
  'تأكيد أو رفض طلب تعبئة محفظة. للأدمن فقط، ولا ينجح مرتين على نفس الطلب.';


-- ---------------------------------------------------------------------
-- 4) الصلاحيات
--    ملاحظة: EXECUTE مُمنوح للـpublic افتراضياً على أي دالة جديدة،
--    لذلك يُسحب أولاً صراحةً قبل منح authenticated.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_wallet_decide(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_wallet_decide(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_wallet_decide(uuid, text) TO authenticated;


-- =====================================================================
-- 5) إصلاح PGRST202 — إعادة تحميل مخطط PostgREST.
--    بدون هذا السطر يبقى 404 PGRST202 حتى لو نُفِّذ كل ما سبق.
-- =====================================================================
NOTIFY pgrst, 'reload schema';


-- =====================================================================
-- 6) اختبارات بعد التنفيذ — نفّذها في SQL Editor واقرأ النتائج.
-- =====================================================================

-- 6.1) الجدول موجود والقيود مطبَّقة.
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'wallet_transactions'
 ORDER BY ordinal_position;
-- المتوقّع: id | uuid | user_id | uuid | amount | integer | status | text
--            admin_id | uuid | admin_note | text | created_at | timestamptz
--            confirmed_at | timestamptz

-- 6.2) القيود: لا مبلغ سالب ولا صفر، وconfirmed_at مرتبط بالحالة.
SELECT conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'public.wallet_transactions'::regclass
 ORDER BY conname;

-- 6.3) المستخدم لا يملك UPDATE/DELETE على الجدول.
SELECT privilege_type
  FROM information_schema.role_table_grants
 WHERE table_name = 'wallet_transactions'
   AND grantee = 'authenticated'
 ORDER BY privilege_type;
-- المتوقّع: INSERT, SELECT فقط. لا UPDATE ولا DELETE.

-- 6.4) الدالة موجودة وSECURITY DEFINER(path مثبّت) وصلاحياتها.
SELECT p.proname,
       p.prorettype::regtype  AS returns,
       p.prosecdef           AS security_definer,
       p.proconfig           AS search_path,
       p.proacl              AS acl
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'admin_wallet_decide';

-- 6.5) الاختبارات جافة — أنت داخل SQL Editor فأنت postgres وليس
--       auth.uid()، فيُرفض بـ not_authenticated ولا يتغيّر أي رصيد.
SELECT public.admin_wallet_decide(gen_random_uuid(), 'confirmed') AS as_normal_user;
-- المتوقّع: {"ok": false, "reason": "not_authenticated", "status": null}

SELECT public.admin_wallet_decide(gen_random_uuid(), 'pending') AS as_bad_status;
-- المتوقّع: {"ok": false, "reason": "bad_status", "status": null}

-- 6.6) لا عمليات في الجدول — الملف لا ينشئ أي صف.
SELECT count(*) AS wallet_rows FROM public.wallet_transactions;
-- المتوقّع: 0

-- 6.7) بيانات المشروع سليمة بعد التنفيذ (لا شيء من هذا الملف يمسّها).
SELECT 'cars' AS t, count(*) FROM public.cars
UNION ALL SELECT 'market_items', count(*) FROM public.market_items
UNION ALL SELECT 'jobs',         count(*) FROM public.jobs
UNION ALL SELECT 'profiles',     count(*) FROM public.profiles;
