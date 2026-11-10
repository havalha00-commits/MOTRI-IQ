BEGIN;

CREATE TABLE IF NOT EXISTS public.saved_searches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query_text TEXT,
  brand TEXT,
  province TEXT,
  city TEXT,
  body_type TEXT,
  min_year INTEGER CHECK (min_year IS NULL OR min_year BETWEEN 1886 AND 2100),
  max_year INTEGER CHECK (max_year IS NULL OR max_year BETWEEN 1886 AND 2100),
  min_price NUMERIC CHECK (min_price IS NULL OR min_price BETWEEN 0 AND 1000000000),
  max_price NUMERIC CHECK (max_price IS NULL OR max_price BETWEEN 0 AND 1000000000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT saved_searches_year_range
    CHECK (min_year IS NULL OR max_year IS NULL OR min_year <= max_year),
  CONSTRAINT saved_searches_price_range
    CHECK (min_price IS NULL OR max_price IS NULL OR min_price <= max_price),
  CONSTRAINT saved_searches_has_criteria
    CHECK (
      NULLIF(BTRIM(query_text), '') IS NOT NULL OR
      NULLIF(BTRIM(brand), '') IS NOT NULL OR
      NULLIF(BTRIM(province), '') IS NOT NULL OR
      NULLIF(BTRIM(city), '') IS NOT NULL OR
      NULLIF(BTRIM(body_type), '') IS NOT NULL OR
      min_year IS NOT NULL OR max_year IS NOT NULL OR
      min_price IS NOT NULL OR max_price IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS saved_searches_user_created_idx
  ON public.saved_searches (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.car_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  saved_search_id UUID NOT NULL REFERENCES public.saved_searches(id) ON DELETE CASCADE,
  car_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  CONSTRAINT car_alerts_saved_search_car_unique UNIQUE (saved_search_id, car_id)
);

CREATE INDEX IF NOT EXISTS car_alerts_user_created_idx
  ON public.car_alerts (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS car_alerts_car_id_idx
  ON public.car_alerts (car_id);

CREATE OR REPLACE FUNCTION public.car_matches_saved_search(
  p_search public.saved_searches,
  p_car public.cars
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $function$
  SELECT
    (p_search.query_text IS NULL OR
      concat_ws(' ', p_car.title, p_car.brand, p_car.model, p_car.description)
        ILIKE '%' || p_search.query_text || '%')
    AND (p_search.brand IS NULL OR p_car.brand ILIKE '%' || p_search.brand || '%')
    AND (p_search.province IS NULL OR lower(p_car.province) = lower(p_search.province))
    AND (p_search.city IS NULL OR p_car.city ILIKE '%' || p_search.city || '%')
    AND (p_search.body_type IS NULL OR lower(p_car.body_type) = lower(p_search.body_type))
    AND (p_search.min_year IS NULL OR p_car.year >= p_search.min_year)
    AND (p_search.max_year IS NULL OR p_car.year <= p_search.max_year)
    AND (p_search.min_price IS NULL OR p_car.price >= p_search.min_price)
    AND (p_search.max_price IS NULL OR p_car.price <= p_search.max_price)
$function$;

CREATE OR REPLACE FUNCTION public.create_car_alerts_for_saved_search()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.car_alerts (user_id, saved_search_id, car_id)
  SELECT NEW.user_id, NEW.id, matches.id
  FROM (
    SELECT c.id
    FROM public.cars AS c
    WHERE c.is_approved IS TRUE
      AND c.user_id <> NEW.user_id
      AND public.car_matches_saved_search(NEW, c)
    ORDER BY c.created_at DESC
    LIMIT 100
  ) AS matches
  ON CONFLICT (saved_search_id, car_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_car_alerts_for_approved_car()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.is_approved IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.is_approved IS TRUE THEN
      RETURN NEW;
    END IF;
  END IF;

  INSERT INTO public.car_alerts (user_id, saved_search_id, car_id)
  SELECT s.user_id, s.id, NEW.id
  FROM public.saved_searches AS s
  WHERE s.user_id <> NEW.user_id
    AND public.car_matches_saved_search(s, NEW)
  ON CONFLICT (saved_search_id, car_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS saved_searches_create_car_alerts ON public.saved_searches;
CREATE TRIGGER saved_searches_create_car_alerts
AFTER INSERT ON public.saved_searches
FOR EACH ROW
EXECUTE FUNCTION public.create_car_alerts_for_saved_search();

DROP TRIGGER IF EXISTS cars_create_car_alerts_on_insert ON public.cars;
CREATE TRIGGER cars_create_car_alerts_on_insert
AFTER INSERT ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.create_car_alerts_for_approved_car();

DROP TRIGGER IF EXISTS cars_create_car_alerts_on_approval ON public.cars;
CREATE TRIGGER cars_create_car_alerts_on_approval
AFTER UPDATE OF is_approved ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.create_car_alerts_for_approved_car();

COMMIT;
