GRANT INSERT ON TABLE public.cars TO authenticated;

DROP POLICY IF EXISTS "car owners insert own ads" ON public.cars;
CREATE POLICY "car owners insert own ads"
ON public.cars
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);
