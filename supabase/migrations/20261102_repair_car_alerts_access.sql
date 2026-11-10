CREATE TABLE IF NOT EXISTS public.car_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  car_id text NOT NULL,
  brand text,
  model text,
  province text,
  city text,
  price numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

ALTER TABLE public.car_alerts ENABLE ROW LEVEL SECURITY;

GRANT SELECT, UPDATE ON TABLE public.car_alerts TO authenticated;

DROP POLICY IF EXISTS "alerts select own" ON public.car_alerts;
CREATE POLICY "alerts select own"
ON public.car_alerts
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "alerts update own" ON public.car_alerts;
CREATE POLICY "alerts update own"
ON public.car_alerts
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
