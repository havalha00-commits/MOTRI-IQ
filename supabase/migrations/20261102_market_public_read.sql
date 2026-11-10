ALTER TABLE public.market_items ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy record;
BEGIN
  FOR policy IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'market_items'
      AND cmd = 'SELECT'
      AND permissive = 'RESTRICTIVE'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.market_items', policy.policyname);
  END LOOP;

  FOR policy IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'market_items'
      AND cmd = 'SELECT'
      AND permissive = 'PERMISSIVE'
      AND qual ~ '(user_id|owner_id|seller_id)'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.market_items', policy.policyname);
  END LOOP;
END
$$;

DROP POLICY IF EXISTS "market items readable by public"
ON public.market_items;
CREATE POLICY "market items readable by public"
ON public.market_items
FOR SELECT
TO anon, authenticated
USING (true);

GRANT SELECT ON TABLE public.market_items TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
