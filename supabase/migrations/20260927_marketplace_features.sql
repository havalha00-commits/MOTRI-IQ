ALTER TABLE public.cars
  ADD COLUMN IF NOT EXISTS province text,
  ADD COLUMN IF NOT EXISTS body_type text;

GRANT UPDATE, DELETE ON public.cars TO authenticated;
DROP POLICY IF EXISTS "car owners update own ads" ON public.cars;
CREATE POLICY "car owners update own ads" ON public.cars FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "car owners delete own ads" ON public.cars;
CREATE POLICY "car owners delete own ads" ON public.cars FOR DELETE USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.saved_searches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query_text text,
  brand text,
  province text,
  city text,
  body_type text,
  min_year integer,
  max_year integer,
  min_price numeric,
  max_price numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

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

CREATE TABLE IF NOT EXISTS public.seller_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (seller_id, reviewer_id),
  CHECK (seller_id <> reviewer_id)
);

ALTER TABLE public.saved_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_reviews ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, DELETE ON public.saved_searches TO authenticated;
GRANT SELECT, UPDATE ON public.car_alerts TO authenticated;
GRANT SELECT ON public.seller_reviews TO anon, authenticated;
GRANT INSERT, UPDATE ON public.seller_reviews TO authenticated;

DROP POLICY IF EXISTS "saved searches select own" ON public.saved_searches;
CREATE POLICY "saved searches select own" ON public.saved_searches FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "saved searches insert own" ON public.saved_searches;
CREATE POLICY "saved searches insert own" ON public.saved_searches FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "saved searches delete own" ON public.saved_searches;
CREATE POLICY "saved searches delete own" ON public.saved_searches FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "alerts select own" ON public.car_alerts;
CREATE POLICY "alerts select own" ON public.car_alerts FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "alerts update own" ON public.car_alerts;
CREATE POLICY "alerts update own" ON public.car_alerts FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reviews are public" ON public.seller_reviews;
CREATE POLICY "reviews are public" ON public.seller_reviews FOR SELECT USING (true);
DROP POLICY IF EXISTS "authenticated users can review sellers" ON public.seller_reviews;
CREATE POLICY "authenticated users can review sellers" ON public.seller_reviews FOR INSERT WITH CHECK (auth.uid() = reviewer_id AND auth.uid() <> seller_id);
DROP POLICY IF EXISTS "reviewers update own review" ON public.seller_reviews;
CREATE POLICY "reviewers update own review" ON public.seller_reviews FOR UPDATE USING (auth.uid() = reviewer_id) WITH CHECK (auth.uid() = reviewer_id AND auth.uid() <> seller_id);

CREATE OR REPLACE FUNCTION public.create_saved_search_alerts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.car_alerts (user_id, car_id, brand, model, province, city, price)
  SELECT s.user_id, NEW.id::text, NEW.brand, NEW.model, NEW.province, NEW.city, NEW.price
  FROM public.saved_searches AS s
  WHERE s.user_id <> NEW.user_id
    AND (NULLIF(trim(s.query_text), '') IS NULL
      OR concat_ws(' ', NEW.brand, NEW.model) ILIKE '%' || trim(s.query_text) || '%')
    AND (NULLIF(trim(s.brand), '') IS NULL OR NEW.brand ILIKE '%' || trim(s.brand) || '%')
    AND (NULLIF(trim(s.province), '') IS NULL OR NEW.province = s.province)
    AND (NULLIF(trim(s.city), '') IS NULL OR NEW.city ILIKE '%' || trim(s.city) || '%')
    AND (NULLIF(trim(s.body_type), '') IS NULL OR NEW.body_type = s.body_type)
    AND (s.min_year IS NULL OR NEW.year >= s.min_year)
    AND (s.max_year IS NULL OR NEW.year <= s.max_year)
    AND (s.min_price IS NULL OR NEW.price >= s.min_price)
    AND (s.max_price IS NULL OR NEW.price <= s.max_price);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cars_saved_search_alerts ON public.cars;
CREATE TRIGGER cars_saved_search_alerts
AFTER INSERT ON public.cars
FOR EACH ROW EXECUTE FUNCTION public.create_saved_search_alerts();
