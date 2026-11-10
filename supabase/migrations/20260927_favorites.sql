CREATE TABLE IF NOT EXISTS public.favorites (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  car_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, car_id)
);

ALTER TABLE public.favorites
  ADD COLUMN IF NOT EXISTS car_id text;

CREATE UNIQUE INDEX IF NOT EXISTS favorites_user_car_unique
  ON public.favorites (user_id, car_id)
  WHERE car_id IS NOT NULL;

ALTER TABLE public.favorites
  ADD COLUMN IF NOT EXISTS item_type text DEFAULT 'car';

ALTER TABLE public.favorites
  ADD COLUMN IF NOT EXISTS item_id text;

ALTER TABLE public.favorites
  ALTER COLUMN item_type SET DEFAULT 'car';

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, DELETE ON public.favorites TO authenticated;

DROP POLICY IF EXISTS "users read own favorites" ON public.favorites;
CREATE POLICY "users read own favorites"
  ON public.favorites FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "users add own favorites" ON public.favorites;
CREATE POLICY "users add own favorites"
  ON public.favorites FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "users remove own favorites" ON public.favorites;
CREATE POLICY "users remove own favorites"
  ON public.favorites FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';



