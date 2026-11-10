CREATE TABLE IF NOT EXISTS public.seller_showrooms (
  seller_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  showroom_name text NOT NULL CHECK (length(trim(showroom_name)) BETWEEN 2 AND 80),
  province text,
  city text,
  description text,
  contact_phone text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.seller_showrooms ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.seller_showrooms TO anon, authenticated;
GRANT INSERT, UPDATE ON public.seller_showrooms TO authenticated;

DROP POLICY IF EXISTS "showrooms are public"
  ON public.seller_showrooms;
CREATE POLICY "showrooms are public"
  ON public.seller_showrooms FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "sellers create own showroom"
  ON public.seller_showrooms;
CREATE POLICY "sellers create own showroom"
  ON public.seller_showrooms FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id);

DROP POLICY IF EXISTS "sellers update own showroom"
  ON public.seller_showrooms;
CREATE POLICY "sellers update own showroom"
  ON public.seller_showrooms FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id)
  WITH CHECK (auth.uid() = seller_id);

NOTIFY pgrst, 'reload schema';