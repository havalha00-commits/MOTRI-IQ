INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('cars', 'cars', true, 10485760, ARRAY['image/*']::text[])
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "car owners can upload own images" ON storage.objects;
CREATE POLICY "car owners can upload own images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'cars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "car owners can inspect own image files" ON storage.objects;
CREATE POLICY "car owners can inspect own image files"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'cars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "car owners can overwrite own image files" ON storage.objects;
CREATE POLICY "car owners can overwrite own image files"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'cars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'cars' AND (storage.foldername(name))[1] = auth.uid()::text);