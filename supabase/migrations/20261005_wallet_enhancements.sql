-- =====================================================================
-- MOTRI IQ — تحسين محفظة المستخدم: بصمات الدفع، إعدادات كي كارد، 
--   صندوق تخزين الإيصالات
-- الملف: supabase/migrations/20261005_wallet_enhancements.sql
-- الحالة: نهائي
-- =====================================================================
--
-- لماذا هذا الملف
-- ---------------
-- يضيف أعمدة وترفقات ضرورية لتمكن تدفق تعبئة المحفظة الكامل:
--   1. receipt_image_url  — رابط صورة إثبات الدفع الذي يرفعه المستخدم.
--   2. payment_method      — كي كارد (كحالة افتراضية، ويمكن توسيعها لاحقاً).
--   3. wallet_settings      — جدول إعدادات يديره المشرف فقط؛ يُخزن فيه
--      رقم حساب كي كارد بدلاً من إرفاقه ثابتاً في الواجهة.
--   4. bucket wallet_receipts — صندوق تخزين آمن لإيصالات التعبئة.
--
-- لا يُلمس أي جدول غير محفظة، ولا يُنشأ جدول بديل.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) إضافة أعمدة لجدول معاملات المحفظة
-- ---------------------------------------------------------------------
ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'kcard'
    CHECK (payment_method IN ('kcard')),
  ADD COLUMN IF NOT EXISTS receipt_image_url text;


-- ---------------------------------------------------------------------
-- 2) جدول إعدادات المحفظة (يديره المشرفون فقط)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_settings (
  key          text    PRIMARY KEY,
  value        text    NOT NULL,
  description  text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid    REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE public.wallet_settings ENABLE ROW LEVEL SECURITY;

-- المشرفون يديرون الإعدادات (INSERT / UPDATE / DELETE)
DROP POLICY IF EXISTS "admins manage wallet settings" ON public.wallet_settings;
CREATE POLICY "admins manage wallet settings"
  ON public.wallet_settings FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- الجميع (المشرفون والمستخدمون العاديون) يقرأون الإعدادات
DROP POLICY IF EXISTS "everyone reads wallet settings" ON public.wallet_settings;
CREATE POLICY "everyone reads wallet settings"
  ON public.wallet_settings FOR SELECT TO anon, authenticated
  USING (true);


-- ---------------------------------------------------------------------
-- 3) صندوق تخزين إيصالات التعبئة
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('wallet_receipts', 'wallet_receipts', true, 10485760, ARRAY['image/*']::text[])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- المستخدمون يرفعون إيصالاتهم الخاصة
DROP POLICY IF EXISTS "wallet receipt owners can upload own receipts" ON storage.objects;
CREATE POLICY "wallet receipt owners can upload own receipts"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'wallet_receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- الجميع يقرأ إيصالات التعبئة (المشرفون يحتاجونها للمراجعة)
DROP POLICY IF EXISTS "wallet receipts are publicly readable" ON storage.objects;
CREATE POLICY "wallet receipts are publicly readable"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'wallet_receipts');

-- أصحاب الملفات يمكنهم تعديلها
DROP POLICY IF EXISTS "wallet receipt owners can update own receipts" ON storage.objects;
CREATE POLICY "wallet receipt owners can update own receipts"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'wallet_receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'wallet_receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );


-- ---------------------------------------------------------------------
-- 4) إعادة تحميل مخطط PostgREST
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ---------------------------------------------------------------------
-- 5) اختبارات ما بعد التنفيذ
-- ---------------------------------------------------------------------
-- 5.1) الأعمدة الجديدة موجودة
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'wallet_transactions'
   AND column_name IN ('payment_method', 'receipt_image_url')
 ORDER BY ordinal_position;

-- 5.2) جدول الإعدادات موجود ومُحمّل
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'wallet_settings'
 ORDER BY ordinal_position;

-- 5.3) صندوق التخزين موجود
SELECT id, name, public FROM storage.buckets WHERE id = 'wallet_receipts';

-- 5.4) لا عمليات محفظة موجودة بعد (الملف الأصلي لم ينشئ أي صفوف)
SELECT count(*) AS wallet_tx_count FROM public.wallet_transactions;
-- المتوقّع: 0
