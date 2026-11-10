ALTER TABLE public.market_items ENABLE ROW LEVEL SECURITY;

REVOKE DELETE ON TABLE public.market_items FROM PUBLIC, anon;
GRANT DELETE ON TABLE public.market_items TO authenticated;

DROP POLICY IF EXISTS "market item owners delete own ads"
ON public.market_items;
CREATE POLICY "market item owners delete own ads"
ON public.market_items
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "market item delete ownership guard"
ON public.market_items;
CREATE POLICY "market item delete ownership guard"
ON public.market_items
AS RESTRICTIVE
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
