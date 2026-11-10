-- Adaptive Seller Reputation System
-- Caches computed reputation data for fast lookups and
-- provides badge tiers beyond the verified badge.

CREATE TABLE IF NOT EXISTS public.seller_reputations (
  seller_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  avg_rating numeric(3,2) NOT NULL DEFAULT 0,
  review_count integer NOT NULL DEFAULT 0,
  completed_sales integer NOT NULL DEFAULT 0,
  avg_response_minutes numeric(8,1) DEFAULT 0,
  reputation_score numeric(5,2) NOT NULL DEFAULT 0,
  badge_tier text NOT NULL DEFAULT 'none'
    CHECK (badge_tier IN ('none', 'bronze', 'silver', 'gold')),
  last_updated timestamptz NOT NULL DEFAULT now()
);

-- Track when a seller first responds to a buyer message.
-- The row is created when a buyer sends a message to a seller.
-- first_response_at is filled when the seller replies.
CREATE TABLE IF NOT EXISTS public.seller_response_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES public.car_offers(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_buyer_message_at timestamptz NOT NULL DEFAULT now(),
  seller_responded boolean NOT NULL DEFAULT false,
  first_response_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.seller_reputations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_response_tracking ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.seller_reputations TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.seller_reputations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.seller_response_tracking TO authenticated;

-- Reputations are publicly readable, only the system/role can update
DROP POLICY IF EXISTS "reputations are public" ON public.seller_reputations;
CREATE POLICY "reputations are public"
  ON public.seller_reputations FOR SELECT USING (true);
DROP POLICY IF EXISTS "sellers manage own reputation cache" ON public.seller_reputations;
CREATE POLICY "sellers manage own reputation cache"
  ON public.seller_reputations FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id);
CREATE POLICY "sellers update own reputation cache"
  ON public.seller_reputations FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id);

DROP POLICY IF EXISTS "tracking visible to participants" ON public.seller_response_tracking;
CREATE POLICY "tracking visible to participants"
  ON public.seller_response_tracking FOR SELECT TO authenticated
  USING (seller_id = auth.uid() OR buyer_id = auth.uid());

-- Calculate badge tier and reputation score from aggregate data.
CREATE OR REPLACE FUNCTION public.calc_badge_tier(
  p_avg_rating numeric,
  p_review_count integer
) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_avg_rating >= 4.5 AND p_review_count >= 10 THEN
    RETURN 'gold';
  ELSIF p_avg_rating >= 4.0 AND p_review_count >= 5 THEN
    RETURN 'silver';
  ELSIF p_avg_rating >= 3.5 AND p_review_count >= 1 THEN
    RETURN 'bronze';
  END IF;
  RETURN 'none';
END;
$$;

CREATE OR REPLACE FUNCTION public.calc_reputation_score(
  p_avg_rating numeric,
  p_review_count integer,
  p_completed_sales integer,
  p_avg_response_minutes numeric
) RETURNS numeric(5,2) LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  rating_component numeric;
  review_component numeric;
  sales_component numeric;
  response_component numeric;
BEGIN
  rating_component := COALESCE(p_avg_rating, 0) / 5.0 * 40;
  review_component := LEAST(COALESCE(p_review_count, 0)::numeric, 50) / 50 * 30;
  sales_component := LEAST(COALESCE(p_completed_sales, 0)::numeric, 30) / 30 * 20;
  -- response rate: respond within 30 min = full points, scale down
  IF COALESCE(p_avg_response_minutes, 0) = 0 THEN
    response_component := 10;
  ELSE
    response_component := GREATEST(0, 10 - LEAST(p_avg_response_minutes / 30.0 * 10, 10));
  END IF;
  RETURN rating_component + review_component + sales_component + response_component;
END;
$$;

-- Recalculate reputation cache for a single seller.
CREATE OR REPLACE FUNCTION public.refresh_seller_reputation(p_seller_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  avg_rating_val numeric(3,2);
  review_count_val integer;
  completed_sales_val integer;
  avg_response_val numeric(8,1);
BEGIN
  SELECT
    ROUND(AVG(rating), 2),
    COUNT(*)
  INTO avg_rating_val, review_count_val
  FROM public.seller_reviews
  WHERE seller_id = p_seller_id;

  IF avg_rating_val IS NULL THEN
    avg_rating_val := 0;
    review_count_val := 0;
  END IF;

  SELECT COUNT(*)
  INTO completed_sales_val
  FROM public.car_offers
  WHERE seller_id = p_seller_id AND status = 'accepted';

  -- Average response time in minutes (only for responded messages)
  SELECT ROUND(AVG(EXTRACT(EPOCH FROM (first_response_at - last_buyer_message_at)) / 60))
  INTO avg_response_val
  FROM public.seller_response_tracking
  WHERE seller_id = p_seller_id AND seller_responded = true;

  IF avg_response_val IS NULL THEN
    avg_response_val := 0;
  END IF;

  INSERT INTO public.seller_reputations
    (seller_id, avg_rating, review_count, completed_sales, avg_response_minutes,
     reputation_score, badge_tier, last_updated)
  VALUES
    (p_seller_id, avg_rating_val, review_count_val, completed_sales_val, avg_response_val,
     public.calc_reputation_score(avg_rating_val, review_count_val, completed_sales_val, avg_response_val),
     public.calc_badge_tier(avg_rating_val, review_count_val),
     now())
  ON CONFLICT (seller_id)
  DO UPDATE SET
    avg_rating = EXCLUDED.avg_rating,
    review_count = EXCLUDED.review_count,
    completed_sales = EXCLUDED.completed_sales,
    avg_response_minutes = EXCLUDED.avg_response_minutes,
    reputation_score = EXCLUDED.reputation_score,
    badge_tier = EXCLUDED.badge_tier,
    last_updated = now();
END;
$$;

-- Auto-refresh reputation on review insert/update/delete
CREATE OR REPLACE FUNCTION public.trigger_refresh_seller_reputation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_seller_reputation(OLD.seller_id);
  ELSE
    PERFORM public.refresh_seller_reputation(NEW.seller_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS seller_reputation_on_review ON public.seller_reviews;
CREATE TRIGGER seller_reputation_on_review
AFTER INSERT OR UPDATE OR DELETE ON public.seller_reviews
FOR EACH ROW EXECUTE FUNCTION public.trigger_refresh_seller_reputation();

-- Auto-refresh reputation when an offer is accepted (completed sales counter)
CREATE OR REPLACE FUNCTION public.trigger_refresh_seller_reputation_offer()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'accepted' THEN
    PERFORM public.refresh_seller_reputation(NEW.seller_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seller_reputation_on_offer ON public.car_offers;
CREATE TRIGGER seller_reputation_on_offer
AFTER UPDATE OF status ON public.car_offers
FOR EACH ROW EXECUTE FUNCTION public.trigger_refresh_seller_reputation_offer();

NOTIFY pgrst, 'reload schema';
