-- Users request top-ups; only admin_wallet_decide may confirm them.
-- The original status/confirmed_at CHECK accepts confirmed + non-null timestamp.
BEGIN;
DROP POLICY IF EXISTS "users request their own top ups" ON public.wallet_transactions;
CREATE POLICY "users request their own top ups"
ON public.wallet_transactions FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND status = 'pending'
  AND confirmed_at IS NULL
  AND admin_id IS NULL
  AND admin_note IS NULL
);
-- Restrictive policy also guards against another permissive INSERT policy.
DROP POLICY IF EXISTS "wallet insert must start pending" ON public.wallet_transactions;
CREATE POLICY "wallet insert must start pending"
ON public.wallet_transactions AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id AND status = 'pending' AND confirmed_at IS NULL
  AND admin_id IS NULL AND admin_note IS NULL
);
-- Receipts contain financial information; public URLs must stop working.
UPDATE storage.buckets SET public = false WHERE id = 'wallet_receipts';
DROP POLICY IF EXISTS "wallet receipts are publicly readable" ON storage.objects;
DROP POLICY IF EXISTS "wallet receipts owner or admin read" ON storage.objects;
CREATE POLICY "wallet receipts owner or admin read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'wallet_receipts'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid())
  )
);
NOTIFY pgrst, 'reload schema';
COMMIT;
