CREATE TABLE IF NOT EXISTS public.car_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  brand text NOT NULL,
  model text,
  year_from integer,
  year_to integer,
  max_price numeric NOT NULL CHECK (max_price > 0),
  province text,
  city text,
  details text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (year_from IS NULL OR year_from BETWEEN 1950 AND 2100),
  CHECK (year_to IS NULL OR year_to BETWEEN 1950 AND 2100),
  CHECK (year_from IS NULL OR year_to IS NULL OR year_from <= year_to)
);

CREATE INDEX IF NOT EXISTS car_requests_open_created_idx
  ON public.car_requests (created_at DESC)
  WHERE status = 'open';
CREATE INDEX IF NOT EXISTS car_requests_buyer_created_idx
  ON public.car_requests (buyer_id, created_at DESC);

ALTER TABLE public.car_requests ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.car_requests TO anon, authenticated;
GRANT INSERT ON public.car_requests TO authenticated;
GRANT UPDATE (status) ON public.car_requests TO authenticated;

DROP POLICY IF EXISTS "open or own car requests are visible" ON public.car_requests;
CREATE POLICY "open or own car requests are visible"
ON public.car_requests FOR SELECT
USING (status = 'open' OR auth.uid() = buyer_id);

DROP POLICY IF EXISTS "buyers create their own car requests" ON public.car_requests;
CREATE POLICY "buyers create their own car requests"
ON public.car_requests FOR INSERT TO authenticated
WITH CHECK (auth.uid() = buyer_id);

DROP POLICY IF EXISTS "buyers close their own car requests" ON public.car_requests;
CREATE POLICY "buyers close their own car requests"
ON public.car_requests FOR UPDATE TO authenticated
USING (auth.uid() = buyer_id)
WITH CHECK (auth.uid() = buyer_id);

CREATE TABLE IF NOT EXISTS public.car_request_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.car_requests(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vehicle text NOT NULL,
  offer_price numeric NOT NULL CHECK (offer_price > 0),
  message text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, seller_id),
  CHECK (buyer_id <> seller_id)
);

CREATE INDEX IF NOT EXISTS car_request_offers_buyer_created_idx
  ON public.car_request_offers (buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS car_request_offers_seller_created_idx
  ON public.car_request_offers (seller_id, created_at DESC);

ALTER TABLE public.car_request_offers ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.car_request_offers TO authenticated;
GRANT UPDATE (status) ON public.car_request_offers TO authenticated;

DROP POLICY IF EXISTS "buyers and sellers see request offers" ON public.car_request_offers;
CREATE POLICY "buyers and sellers see request offers"
ON public.car_request_offers FOR SELECT TO authenticated
USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

DROP POLICY IF EXISTS "sellers send offers to open requests" ON public.car_request_offers;
CREATE POLICY "sellers send offers to open requests"
ON public.car_request_offers FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = seller_id
  AND auth.uid() <> buyer_id
  AND EXISTS (
    SELECT 1 FROM public.car_requests r
    WHERE r.id = request_id
      AND r.buyer_id = car_request_offers.buyer_id
      AND r.status = 'open'
  )
);

DROP POLICY IF EXISTS "buyers respond to request offers" ON public.car_request_offers;
CREATE POLICY "buyers respond to request offers"
ON public.car_request_offers FOR UPDATE TO authenticated
USING (
  auth.uid() = buyer_id
  AND EXISTS (
    SELECT 1 FROM public.car_requests r
    WHERE r.id = request_id AND r.buyer_id = auth.uid()
  )
)
WITH CHECK (
  auth.uid() = buyer_id
  AND EXISTS (
    SELECT 1 FROM public.car_requests r
    WHERE r.id = request_id AND r.buyer_id = auth.uid()
  )
);