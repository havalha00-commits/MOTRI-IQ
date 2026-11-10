-- =====================================================================
--  إصلاح جذري: فشل إنشاء كل حساب جديد
--  "Database error saving new user" / unexpected_failure (HTTP 500)
--
--  ── السبب الحقيقي (مُثبَت بالاستنساخ، لا بالتخمين) ────────────────
--  استنسختُ الطلب عبر /auth/v1/signup فردَّ الخادم:
--     {"code":"23505",
--      "message":"duplicate key value violates unique constraint
--                 \"profiles_activation_code_key\"",
--      "detail":"Key (activation_code)=(PENDING) already exists."}
--
--  أي أن public.profiles.activation_code عليه قيد UNIQUE من مستوى
--  العمود، وDEFAULT قيمته الثابتة 'PENDING'. القيمة الثابتة على عمود
--  فريد تُستهلك مرة واحدة فقط: يأخذها أول مستخدم، ثم تفشل كل عمليات
--  التسجيل اللاحقة بمخالفة 23505، فيتحوّل الخطأ إلى 500.
--  هذا يفسّر لماذا كان الحساب الأول فقط ينجح.
--
--  ── الحل ──────────────────────────────────────────────────────────
--  استبدال قيد التفرّد العام بفهرس فريد جزئي يستثني 'PENDING':
--    · 'PENDING'            → تصبح قابلة للتكرار بلا حد
--    · أي قيمة تفعيل حقيقية → تبقى فريدة كما هي
--
--  ── ما لا يفعله هذا الملف ────────────────────────────────────────
--  · لا يمس DEFAULT الخاص بـ activation_code (يبقى 'PENDING')
--  · لا يمس handle_new_user() ولا on_auth_user_created
--  · لا يمس أي سياسة RLS ولا صلاحية
--  · لا يحذف أو يعدّل أي صف، ولا يغيّر عدد الصفوف
--  · لا يستخدم CASCADE
--  · لا ينشئ أي حساب
--
--  ── قابلية إعادة التطبيق ─────────────────────────────────────────
--  · فحص وجود القيد داخل DO $$  → لا يفشل إن كان محذوفًا مسبقًا
--  · IF NOT EXISTS على الفهرس   → لا يفشل عند إعادة التشغيل
-- =====================================================================

BEGIN;

-- 1) إزالة القيد الفريد العام من مستوى العمود إن كان موجودًا.
--    القيد هو سبب الخطأ مباشرة. الحذف على المخطط فقط ولا يمس الصفوف.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class c     ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname  = 'profiles'
      AND con.conname = 'profiles_activation_code_key'
  ) THEN
    ALTER TABLE public.profiles DROP CONSTRAINT profiles_activation_code_key;
    RAISE NOTICE 'تمت إزالة profiles_activation_code_key';
  ELSE
    RAISE NOTICE 'القيد profiles_activation_code_key غير موجود — لا حاجة';
  END IF;
END;
$$;

-- 2) فهرس فريد جزئي: يضمن عدم تكرار أكواد التفعيل الحقيقية فقط،
--    ويتجاوز 'PENDING'. لا يمس DEFAULT ولا الدوال ولا RLS.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_activation_code_unique
  ON public.profiles (activation_code)
  WHERE activation_code IS DISTINCT FROM 'PENDING';

COMMIT;

-- =====================================================================
--  التحقق بعد التشغيل:
--
--  SELECT indexname, indexdef FROM pg_indexes
--   WHERE schemaname = 'public' AND tablename = 'profiles';
--
--  المتوقع:
--    · profiles_activation_code_unique   ← يجب أن يظهر
--    · profiles_activation_code_key     ← يجب ألا يظهر
--
--  ثم جرّب إنشاء حساب جديد — يجب أن ينجح.
--  الحسابات التي فشلت سابقًا لم تُنشأ أصلًا، فلا يحتاج شيء لتنظيف.
-- =====================================================================