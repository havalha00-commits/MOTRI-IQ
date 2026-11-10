CREATE TABLE IF NOT EXISTS public.seller_verifications (
  seller_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  verified_at timestamptz NOT NULL DEFAULT now(),
  verified_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note text
);

ALTER TABLE public.seller_verifications ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.seller_verifications TO anon, authenticated;
DROP POLICY IF EXISTS "seller verifications are public" ON public.seller_verifications;
CREATE POLICY "seller verifications are public" ON public.seller_verifications FOR SELECT USING (true);

-- Manage verification rows only through a trusted administrator account/service role.
CREATE TABLE IF NOT EXISTS public.car_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  car_id text NOT NULL,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seller_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (car_id, reporter_id),
  CHECK (seller_id IS NULL OR seller_id <> reporter_id)
);

ALTER TABLE public.car_reports ENABLE ROW LEVEL SECURITY;
GRANT INSERT ON public.car_reports TO authenticated;
DROP POLICY IF EXISTS "users can report ads once" ON public.car_reports;
CREATE POLICY "users can report ads once" ON public.car_reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id AND (seller_id IS NULL OR auth.uid() <> seller_id));