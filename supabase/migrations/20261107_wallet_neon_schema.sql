-- =====================================================================
-- MOTRI IQ — محفظة المستخدم على Neon (مستقل عن Supabase auth)
-- الملف: supabase/migrations/20261107_wallet_neon_schema.sql
-- الحالة: مسودة — جاهز للمراجعة قبل التنفيذ على Neon
-- ملاحظة: READ-ONLY للتحضير فقط. لا يُنفَّذ على قاعدة الإنتاج الآن.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) جدول معاملات المحفظة (مستقل عن auth.users)
--    الربط بـ app_users.id فقط. لا auth.uid() ولا Supabase RPC.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL
                  REFERENCES public.app_users(id) ON DELETE RESTRICT,
  amount      integer     NOT NULL CHECK (amount > 0),
  status      text        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'confirmed', 'rejected')),
  admin_id    uuid
                  REFERENCES public.app_users(id) ON DELETE SET NULL,
  admin_note  text,
  payment_method text    NOT NULL DEFAULT 'kcard'
                  CHECK (payment_method = 'kcard'),
  receipt_image_url text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  CONSTRAINT wallet_confirmed_at_matches_status
    CHECK ((status = 'confirmed') = (confirmed_at IS NOT NULL))
);

COMMENT ON TABLE public.wallet_transactions IS
  'عمليات محفظة المستخدم على Neon. الرصيد = مجموع الصفوف المؤكَّدة فقط.';
COMMENT ON COLUMN public.wallet_transactions.user_id IS
  'مستخدم App owns the transaction. FK to app_users.id, ON DELETE RESTRICT.';
COMMENT ON COLUMN public.wallet_transactions.admin_id IS
  'أدمن أكد أو رفض المعاملة. FK to app_users.id, ON DELETE SET NULL.';
COMMENT ON COLUMN public.wallet_transactions.receipt_image_url IS
  'مسار الكائن في Storage (خاص). يُربط بعد رفع الإيصال بنجاح.';


-- ---------------------------------------------------------------------
-- 2) فهارس لدعم الاستعلامات الشائعة
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS wallet_transactions_user_created_idx
  ON public.wallet_transactions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS wallet_transactions_pending_idx
  ON public.wallet_transactions (created_at DESC)
  WHERE status = 'pending';


-- ---------------------------------------------------------------------
-- 3) جدول إعدادات المحفظة (يديره المشرفون فقط)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_settings (
  key          text    PRIMARY KEY,
  value        text    NOT NULL,
  description  text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid    REFERENCES public.app_users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.wallet_settings IS
  'إعدادات المحفظة التي يديرها المشرفون فقط (مثل رقم حساب كي كارد).';


-- ---------------------------------------------------------------------
-- 4) جدول أذونات الرفع (Upload Authorizations) — للإنتاج على Neon
--    يربط الإذن بالمستخدم والمعاملة ومفتاح الملف المحدد.
--    الاستهلاك ذري: UPDATE ... SET used = true WHERE used = false.
--    لا ON DELETE CASCADE على wallet_transactions لحفظ السجل المالي.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.upload_authorizations (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL
                  REFERENCES public.app_users(id) ON DELETE RESTRICT,
  tx_id       uuid        NOT NULL
                  REFERENCES public.wallet_transactions(id) ON DELETE RESTRICT,
  object_key  text        NOT NULL,
  bucket      text        NOT NULL DEFAULT 'wallet_receipts',
  expires_at  timestamptz NOT NULL,
  used        boolean     NOT NULL DEFAULT FALSE,
  created_at  timestamptz NOT NULL DEFAULT now(),

  -- منع ربط نفس مفتاح الملف بإذن نشط أكثر من مرة
  CONSTRAINT upload_authorizations_object_key_unique
    UNIQUE (object_key, bucket),

  -- الصلاحية: لا يمكن إنشاء إذن لمنتهٍ الصلاحية في الماضي
  CONSTRAINT upload_authorizations_expires_future
    CHECK (expires_at > created_at)
);

COMMENT ON TABLE public.upload_authorizations IS
  'أذونات رفع الإيصالات المؤقتة. يربط الإذن بالمستخدم والمعاملة ومفتاح الملف المحدد. الاستهلاك مرة واحدة فقط.';

CREATE INDEX IF NOT EXISTS upload_authorizations_tx_id_idx
  ON public.upload_authorizations (tx_id);

CREATE INDEX IF NOT EXISTS upload_authorizations_user_id_idx
  ON public.upload_authorizations (user_id);

CREATE INDEX IF NOT EXISTS upload_authorizations_used_expires_idx
  ON public.upload_authorizations (used, expires_at)
  WHERE used = FALSE;

-- ملاحظة: لا يوجد قيد wallet_receipt_only_when_pending.
-- الإيصال (receipt_image_url) يجب أن يظل محفوظاً بعد تأكيد أو رفض المعاملة.
-- المنع من تغيير إيصال معاملة محسومة يُفرض في الكود الخلفي عبر:
--   WHERE status = 'pending' في UPDATE receipt_image_url
--   و WHERE status = 'pending' في UPDATE status/admin_id/confirmed_at (في /decide)
