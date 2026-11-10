ALTER TABLE public.cars ENABLE ROW LEVEL SECURITY;

GRANT SELECT, DELETE ON TABLE public.cars TO authenticated;

DROP POLICY IF EXISTS "car owners select own ads" ON public.cars;
CREATE POLICY "car owners select own ads"
ON public.cars
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "car owners delete own ads" ON public.cars;
CREATE POLICY "car owners delete own ads"
ON public.cars
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
