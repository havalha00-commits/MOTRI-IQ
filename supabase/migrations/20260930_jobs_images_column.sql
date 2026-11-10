-- صور إعلان الوظيفة: إضافة العمود الناقص فقط.
--
-- فحوص تم تنفيذها على public.jobs قبل كتابة هذا الملف:
--   select=* يرجع بالضبط 12 عمودًا:
--     id, user_id, title, company, governorate, salary,
--     job_type, experience, description, phone, is_approved, created_at
--
-- مطابقة الحقول المطلوبة مع الأعمدة الموجودة فعلًا:
--   اسم الوظيفة  -> title        (موجود)  ✅
--   الراتب       -> salary       (موجود، numeric) ✅
--   الموقع       -> governorate  (موجود)  ✅
--   نوع الدوام   -> job_type     (موجود)  ✅
--   الصور        -> ✗ لا يوجد عمود صور إطلاقًا
--
-- => العمود الناقص الوحيد هو الصور.
--
-- الاسم المقترح: images   (بنفس اسم market_items.images بالضبط)
-- النوع المقترح: text[]   (نفس نوع market_items.images بالضبط)
--                ليبقى الكود في market_images.dart متوافقًا مع الجدولين.
--
-- ملاحظات أمان:
--   - لا يحذف ولا يعدّل أي عمود أو صف موجود.
--   - لا يلمس أي RLS policy: ولا INSERT ولا UPDATE ولا DELETE.
--     سياستا القراءة التي أصلحناها للزائر تبقى كما هي تمامًا.
--   - إضافة العمود Nullable، فالإعلانات الحالية تبقى صالحة بلا صور.

-- ============================================================
-- الخطوة 1) فحص قبل التغيير
-- ============================================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'jobs'
ORDER BY ordinal_position;

-- ============================================================
-- الخطوة 2) إضافة عمود الصور (نفس نوع market_items.images)
-- ============================================================
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS images text[] NULL;

-- ============================================================
-- الخطوة 3) تحقّق بعد التغيير
-- ============================================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'jobs'
  AND column_name = 'images';

-- يجب أن ترى: images | ARRAY | YES

-- تأمين أن الإعلان المنشور سابقًا لم يتأثر
SELECT id, title, salary, governorate, job_type, is_approved,
       COALESCE(array_length(images, 1), 0) AS image_count
FROM public.jobs
ORDER BY created_at DESC;

NOTIFY pgrst, 'reload schema';
