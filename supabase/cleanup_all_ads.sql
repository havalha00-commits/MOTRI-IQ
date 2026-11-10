-- =====================================================================
-- MOTRI IQ — تنظيف جميع الإعلانات (cars + market_items + jobs)
-- الملف: supabase/cleanup_all_ads.sql
-- مُحضَّر: 2026-10-03 08:56
-- الصفوف المستهدفة: 11  (cars 5 + market_items 3 + jobs 3)
-- صور Storage المرتبطة: 21 ملفاً، كلها داخل bucket 'cars'
--
-- ⚠️ لماذا هذا الملف necessitates تدخّلك:
--   المفتاح المتاح للتطبيق هو sb_publishable_ (صلاحية anon).
--   delete_status مقيسة على القاعدة نفسها:
--     cars          DELETE -> 200 بلا حذف   (RLS يحجب anon)
--     jobs          DELETE -> 200 بلا حذف   (RLS يحجب anon)
--     market_items  DELETE -> 401            (لا صلاحية DELETE)
--   ودالة admin_delete_ad ترجع PGRST202 لأن المايجريشن غير مطبَّق،
--   وحتى بعد تطبيقها ترفض anon لأن auth.uid() = NULL فيها.
--   أي أن الحذف غير ممكن بأي credencial متاح — وهذا مقصود وأمني.
--
-- ما لا يفعله هذا الملف إطلاقاً:
--   لا يمس profiles / auth.users / app_admins / app_usernames
--   لا يمس seller_reviews ولا أي جدول تقييمات
--   لا يمس business_ads ولا الإعدادات ولا الإشعارات
--   لا يغيّر بنية جداول ولا RLS ولا أي ميزة في التطبيق
-- =====================================================================


-- ---------------------------------------------------------------------
-- الخطوة 0) تأكيد الوضع قبل الحذف — والمتوقّع 5 / 3 / 3
-- ---------------------------------------------------------------------
SELECT 'cars'         AS t, count(*) AS before_delete FROM public.cars
UNION ALL SELECT 'market_items', count(*) FROM public.market_items
UNION ALL SELECT 'jobs',         count(*) FROM public.jobs;


-- ---------------------------------------------------------------------
-- الخطوة 1) الحذف.
--
--   ملاحظة عن market_items: قد تظهر رسالة خطأ "permission denied"
--   على السطر الثالث. هذا طبيعي ومتوقّع إذا كانت RLS تمنع postgres
--   عبرRLS... في هذه الحالة نفّذ:
--       ALTER TABLE public.market_items DISABLE ROW LEVEL SECURITY;
--   ثم أعد تشغيل الجملة، ثم أعد تفعيل RLS فوراً:
--       ALTER TABLE public.market_items ENABLE ROW LEVEL SECURITY;
--   (لا تفعل ذلك إلا إذا ظهر الخطأ فعلاً — RLS يسمح للـ owner عادةً.)
-- ---------------------------------------------------------------------
BEGIN;

DELETE FROM public.cars;
DELETE FROM public.market_items;
DELETE FROM public.jobs;

COMMIT;


-- ---------------------------------------------------------------------
-- الخطوة 2) التحقق بعد الحذف — يجب أن يخرج ثلاث أصفار.
-- ---------------------------------------------------------------------
SELECT 'cars'         AS t, count(*) AS after_delete FROM public.cars
UNION ALL SELECT 'market_items', count(*) FROM public.market_items
UNION ALL SELECT 'jobs',         count(*) FROM public.jobs;
-- المتوقّع: 0 / 0 / 0


-- ---------------------------------------------------------------------
-- الخطوة 3) إثبات أن بيانات المستخدمين لم تُمَس.
-- ---------------------------------------------------------------------
SELECT 'app_admins'     AS t, count(*) FROM public.app_admins
UNION ALL SELECT 'app_usernames', count(*) FROM public.app_usernames
UNION ALL SELECT 'seller_reviews', count(*) FROM public.seller_reviews
UNION ALL SELECT 'favorites',      count(*) FROM public.favorites
UNION ALL SELECT 'activity_notifications', count(*) FROM public.activity_notifications;

SELECT count(*) AS auth_users FROM auth.users;
-- sellers: من المفترض بقاؤه بعدد المستخدمين المسجّلين (لا صف يتكرر)
SELECT count(*) AS profiles FROM public.profiles;


-- =====================================================================
-- الخطوة 4) (اختياري) حذف صور الإعلانات المحذوفة.
--
--   21 ملفاً فقط، كلّها في bucket 'cars'، ومساراتها الدقيقة في:
--       supabase_backup_ads_20261003-085609/linked_storage_paths.txt
--   لا تستخدم أي wildcards ولا تحذف بالـfolder، لأن مجلدات المستخدمين
--   قد تحتوي ملفات من إعلانات أخرى مستقبلاً.
--
--   نفّذ هذا المقطع فقط بعد التأكد أن الخطوة 2 أعطت 0/0/0.
-- =====================================================================

-- 4.1) عرض ما سيُحذف أولاً (للمراجعة، لا يحذف).
-- SELECT name, (metadata->>'size')::bigint AS bytes
-- FROM storage.objects
-- WHERE bucket_id = 'cars'
--   AND name IN (
--     '14f652d6-e797-4c38-980c-e535c10d36b2/1790404661117.jpg',
--     '14f652d6-e797-4c38-980c-e535c10d36b2/car_1790482310809_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790563882719_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725377538_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725379222_1.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725379940_2.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725380594_3.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725381294_4.jpeg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790742035087_0.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790742037942_1.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/job_1790724508089000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711631278000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711633144000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711633742000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711634474000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711635175000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715682741000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715683658000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715684326000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715684977000.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715685658000.jpeg'
--   );

-- 4.2) الحذف الفعلي — نفس القائمة بالضبط، بلا wildcards.
-- DELETE FROM storage.objects
-- WHERE bucket_id = 'cars'
--   AND name IN (
--     '14f652d6-e797-4c38-980c-e535c10d36b2/1790404661117.jpg',
--     '14f652d6-e797-4c38-980c-e535c10d36b2/car_1790482310809_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790563882719_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725377538_0.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725379222_1.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725379940_2.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725380594_3.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790725381294_4.jpeg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790742035087_0.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/car_1790742037942_1.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/job_1790724508089000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711631278000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711633144000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711633742000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711634474000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790711635175000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715682741000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715683658000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715684326000.webp',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715684977000.jpg',
--     '5ac8297b-5154-41d6-bbfd-45d60abe3373/market_1790715685658000.jpeg'
--   );
--
-- 4.3) التحقق: يجب أن يُخرج العدد 21.
-- SELECT count(*) FROM storage.objects
-- WHERE bucket_id = 'cars'
--   AND name IN ( /* نفس القائمة */ );


-- =====================================================================
-- الاستعادة الكاملة (إن رغبت في الرجوع)
-- الملف: supabase_backup_ads_20261003-085609/restore_ads.sql
--   11 جملة INSERT داخل BEGIN/COMMIT — يستعيد الجداول الثلاثة كما كانت.
--   الصور لا تُستعاد به (الملفات نفسها لم تُحذف إلا إذا نفّذت الخطوة 4).
-- =====================================================================
