CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.app_admins TO authenticated;
DROP POLICY IF EXISTS "admins can read own membership" ON public.app_admins;
CREATE POLICY "admins can read own membership" ON public.app_admins
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

ALTER TABLE public.car_reports
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_note text;
GRANT SELECT, UPDATE ON public.car_reports TO authenticated;
DROP POLICY IF EXISTS "admins can view reports" ON public.car_reports;
CREATE POLICY "admins can view reports" ON public.car_reports FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "admins can update reports" ON public.car_reports;
CREATE POLICY "admins can update reports" ON public.car_reports FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

GRANT INSERT, DELETE ON public.seller_verifications TO authenticated;
DROP POLICY IF EXISTS "admins can verify sellers" ON public.seller_verifications;
CREATE POLICY "admins can verify sellers" ON public.seller_verifications FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "admins can remove seller verification" ON public.seller_verifications;
CREATE POLICY "admins can remove seller verification" ON public.seller_verifications FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));