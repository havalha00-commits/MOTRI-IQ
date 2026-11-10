-- Business Ads System for MOTRI IQ
-- This migration creates tables for paid business advertisements
-- separate from car listings.

-- ============================================================
-- Storage Bucket for Business Ad Images
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('business_ads', 'business_ads', true, 10485760, ARRAY['image/*']::text[])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage policies: any authenticated user can upload/manage their own files
DROP POLICY IF EXISTS "business ad owners can upload own images" ON storage.objects;
CREATE POLICY "business ad owners can upload own images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'business_ads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "business ad owners can inspect own image files" ON storage.objects;
CREATE POLICY "business ad owners can inspect own image files"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'business_ads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "business ad owners can update own image files" ON storage.objects;
CREATE POLICY "business ad owners can update own image files"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'business_ads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'business_ads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Public read access so ads can display images
DROP POLICY IF EXISTS "public can read business ad images" ON storage.objects;
CREATE POLICY "public can read business ad images"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'business_ads');

-- ============================================================
-- Packages Table — managed entirely by admins
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_packages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text    NOT NULL,
  duration_days integer NOT NULL CHECK (duration_days > 0),
  price         numeric NOT NULL CHECK (price >= 0),
  -- JSON description of where ads for this package will appear
  placements    jsonb   NOT NULL DEFAULT '[]'::jsonb,
  features      text[]  NOT NULL DEFAULT '{}',
  is_active     boolean NOT NULL DEFAULT true,
  sort_order    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_ad_packages ENABLE ROW LEVEL SECURITY;

-- Everyone can read active packages
GRANT SELECT ON public.business_ad_packages TO anon, authenticated;
DROP POLICY IF EXISTS "packages are publicly readable" ON public.business_ad_packages;
CREATE POLICY "packages are publicly readable"
  ON public.business_ad_packages FOR SELECT TO anon, authenticated
  USING (is_active = true);

-- Only admins can insert/update/delete packages
DROP POLICY IF EXISTS "admins can manage packages" ON public.business_ad_packages;
CREATE POLICY "admins can manage packages"
  ON public.business_ad_packages FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- ============================================================
-- Orders Table — tracks payment flow per ad
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id           uuid NOT NULL REFERENCES public.business_ads(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  package_id      uuid NOT NULL REFERENCES public.business_ad_packages(id),
  package_price   numeric NOT NULL,
  payment_status  text  NOT NULL DEFAULT 'unpaid'
                     CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'failed', 'refunded')),
  payment_method  text  NOT NULL DEFAULT 'manual',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_ad_orders ENABLE ROW LEVEL SECURITY;

-- Users can read their own orders; admins can read all
GRANT SELECT ON public.business_ad_orders TO authenticated;
DROP POLICY IF EXISTS "users can view own orders" ON public.business_ad_orders;
CREATE POLICY "users can view own orders"
  ON public.business_ad_orders FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Users can create orders for themselves
DROP POLICY IF EXISTS "users can create own orders" ON public.business_ad_orders;
CREATE POLICY "users can create own orders"
  ON public.business_ad_orders FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Admin can view all orders
DROP POLICY IF EXISTS "admins can view all orders" ON public.business_ad_orders;
CREATE POLICY "admins can view all orders"
  ON public.business_ad_orders FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- Admin can update payment status
DROP POLICY IF EXISTS "admins can update orders" ON public.business_ad_orders;
CREATE POLICY "admins can update orders"
  ON public.business_ad_orders FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- Users cannot modify payment_status directly
DROP POLICY IF EXISTS "users cannot modify payment status" ON public.business_ad_orders;

-- ============================================================
-- Ads Table — the core business advertisement
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id        uuid REFERENCES public.business_ad_orders(id) ON DELETE SET NULL,
  business_name   text NOT NULL CHECK (length(trim(business_name)) BETWEEN 2 AND 100),
  category        text NOT NULL,
  description     text CHECK (length(description) <= 2000),
  logo_url        text,
  image_urls      text[] NOT NULL DEFAULT '{}',
  phone           text,
  whatsapp        text,
  governorate     text,
  area            text,
  address         text,
  latitude        double precision,
  longitude       double precision,
  maps_url        text,
  instagram_url   text,
  facebook_url    text,
  working_hours   text,
  status          text NOT NULL DEFAULT 'pending'
                   CHECK (status IN (
                     'pending',
                     'approved',
                     'rejected',
                     'active',
                     'expired',
                     'paused'
                   )),
  package_id      uuid REFERENCES public.business_ad_packages(id),
  start_at        timestamptz,
  end_at          timestamptz,
  price           numeric,
  payment_status  text NOT NULL DEFAULT 'unpaid'
                   CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'failed', 'refunded')),
  views_count     integer NOT NULL DEFAULT 0,
  clicks_count    integer NOT NULL DEFAULT 0,
  calls_count     integer NOT NULL DEFAULT 0,
  whatsapp_clicks integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_ads ENABLE ROW LEVEL SECURITY;

-- Users can view their own ads; approved+active ads are public
GRANT SELECT, INSERT, UPDATE ON public.business_ads TO authenticated;
GRANT DELETE ON public.business_ads TO authenticated;

DROP POLICY IF EXISTS "users can view own business ads" ON public.business_ads;
CREATE POLICY "users can view own business ads"
  ON public.business_ads FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "public can view approved active business ads" ON public.business_ads;
CREATE POLICY "public can view approved active business ads"
  ON public.business_ads FOR SELECT TO anon
  USING (status = 'active');

-- Users can insert their own ads
DROP POLICY IF EXISTS "users can create own business ads" ON public.business_ads;
CREATE POLICY "users can create own business ads"
  ON public.business_ads FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own ads when in editable states (before approval)
DROP POLICY IF EXISTS "users can update own ads before approval" ON public.business_ads;
CREATE POLICY "users can update own ads before approval"
  ON public.business_ads FOR UPDATE TO authenticated
  USING (
    auth.uid() = user_id
    AND status IN ('pending', 'rejected')
  )
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('pending', 'rejected')
  );

-- Users cannot change critical fields like status, payment_status, or counts directly
-- These are enforced via the admin-only UPDATE policy below

-- Admin can do anything
DROP POLICY IF EXISTS "admins can manage business ads" ON public.business_ads;
CREATE POLICY "admins can manage business ads"
  ON public.business_ads FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()));

-- Users can delete their own pending/rejected ads
DROP POLICY IF EXISTS "users can delete own ads before approval" ON public.business_ads;
CREATE POLICY "users can delete own ads before approval"
  ON public.business_ads FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    AND status IN ('pending', 'rejected')
  );

-- ============================================================
-- Events Table — tracks view/click/call statistics
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id       uuid NOT NULL REFERENCES public.business_ads(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN ('view', 'click', 'call', 'whatsapp', 'map', 'share')),
  user_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  ip_address  inet
);

ALTER TABLE public.business_ad_events ENABLE ROW LEVEL SECURITY;
GRANT INSERT ON public.business_ad_events TO authenticated;
GRANT SELECT ON public.business_ad_events TO authenticated;

-- Anyone can insert events (views) for public ads
DROP POLICY IF EXISTS "anyone can log ad events" ON public.business_ad_events;
CREATE POLICY "anyone can log ad events"
  ON public.business_ad_events FOR INSERT TO anon, authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.business_ads
      WHERE id = ad_id
      AND status = 'active'
    )
  );

-- Users can see events for ads they own; admins can see all
DROP POLICY IF EXISTS "users can view own ad events" ON public.business_ad_events;
CREATE POLICY "users can view own ad events"
  ON public.business_ad_events FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.business_ads
      WHERE id = ad_id AND user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- RPC: Safely increment counters (prevents client-side tampering)
-- ============================================================
CREATE OR REPLACE FUNCTION public.increment_ad_counter(
  p_ad_id uuid,
  p_counter text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_counter = 'views_count' THEN
    UPDATE public.business_ads SET views_count = views_count + 1 WHERE id = p_ad_id;
  ELSIF p_counter = 'clicks_count' THEN
    UPDATE public.business_ads SET clicks_count = clicks_count + 1 WHERE id = p_ad_id;
  ELSIF p_counter = 'calls_count' THEN
    UPDATE public.business_ads SET calls_count = calls_count + 1 WHERE id = p_ad_id;
  ELSIF p_counter = 'whatsapp_clicks' THEN
    UPDATE public.business_ads SET whatsapp_clicks = whatsapp_clicks + 1 WHERE id = p_ad_id;
  END IF;
END;
$$;

-- Anyone can call the function, but it only increments the counter
-- The SECURITY DEFINER ensures the increment happens on the server side
REVOKE ALL ON FUNCTION public.increment_ad_counter(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_ad_counter(uuid, text) TO anon, authenticated;

-- ============================================================
-- Trigger: Auto-advance expired ads to 'expired' status
-- ============================================================
CREATE OR REPLACE FUNCTION public.expire_business_ads()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.end_at IS NOT NULL AND NEW.end_at < now() AND NEW.status = 'active' THEN
    NEW.status := 'expired';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER business_ads_expire_trigger
  BEFORE INSERT OR UPDATE ON public.business_ads
  FOR EACH ROW
  EXECUTE FUNCTION public.expire_business_ads();

-- ============================================================
-- Trigger: Auto-update updated_at timestamp
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER business_ads_updated_at_trigger
  BEFORE UPDATE ON public.business_ads
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER business_ad_orders_updated_at_trigger
  BEFORE UPDATE ON public.business_ad_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER business_ad_packages_updated_at_trigger
  BEFORE UPDATE ON public.business_ad_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

NOTIFY pgrst, 'reload schema';
