CREATE TABLE IF NOT EXISTS public.car_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  car_id text NOT NULL,
  car_title text NOT NULL,
  original_price numeric,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  offer_price numeric NOT NULL CHECK (offer_price > 0),
  message text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (buyer_id <> seller_id)
);

ALTER TABLE public.car_offers ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.car_offers TO authenticated;
GRANT UPDATE (status) ON public.car_offers TO authenticated;
DROP POLICY IF EXISTS "buyers and sellers can view offers" ON public.car_offers;
CREATE POLICY "buyers and sellers can view offers" ON public.car_offers FOR SELECT TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id);
DROP POLICY IF EXISTS "buyers can submit offers" ON public.car_offers;
CREATE POLICY "buyers can submit offers" ON public.car_offers FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = buyer_id AND auth.uid() <> seller_id);
DROP POLICY IF EXISTS "sellers can respond to offers" ON public.car_offers;
CREATE POLICY "sellers can respond to offers" ON public.car_offers FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id)
  WITH CHECK (auth.uid() = seller_id);