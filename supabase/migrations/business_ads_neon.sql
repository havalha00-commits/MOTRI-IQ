-- Business Ads System for MOTRI IQ — Neon Edition
-- Adapted from supabase/migrations/20260929_business_ads.sql
--
-- Adjustments for Neon (plain PostgreSQL, no Supabase Auth / Storage):
-- 1. Removed all storage.buckets / storage.objects / storage.foldername() references (no Supabase Storage).
-- 2. Fixed circular FK ordering: business_ad_packages -> business_ads -> business_ad_orders.
--    order_id FK is added via ALTER TABLE after both tables exist (DO block guard).
-- 3. user_id FKs reference public.app_users(id) instead of auth.users(id),
--    matching backend/middleware/auth.js and current_user.js (req.user.id = app_users.id).
-- 4. Replaced auth.uid() in RLS policies with current_setting('app.current_user_id', true)::uuid.
--    Fail-closed when the setting is NULL (NULL = uuid evaluates to false).
-- 5. Removed NOTIFY pgrst (Supabase/PostgREST specific).
-- 6. No CREATE EXTENSION pgcrypto: gen_random_uuid() is available natively in this Neon database.
-- 7. All GRANTs target motri_backend only (the role exists and holds CRUD on public tables).
-- 8. increment_ad_counter only updates counters when status = 'active'.
-- 9. Idempotent: safe to re-run (IF NOT EXISTS, DROP ... IF EXISTS, CREATE OR REPLACE,
--    DO-block guard for the circular FK, DROP TRIGGER IF EXISTS + CREATE TRIGGER).

-- ============================================================
-- Packages Table — managed entirely by admins
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_packages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text    NOT NULL,
  duration_days integer NOT NULL CHECK (duration_days > 0),
  price         numeric NOT NULL CHECK (price >= 0),
  placements    jsonb   NOT NULL DEFAULT '[]'::jsonb,
  features      text[]  NOT NULL DEFAULT '{}',
  is_active     boolean NOT NULL DEFAULT true,
  sort_order    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_ad_packages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "packages are publicly readable" ON public.business_ad_packages;
CREATE POLICY "packages are publicly readable"
  ON public.business_ad_packages FOR SELECT
  USING (is_active = true);

GRANT SELECT ON public.business_ad_packages TO motri_backend;

-- ============================================================
-- Ads Table — the core business advertisement
-- Created BEFORE business_ad_orders so that business_ad_orders
-- can FK-reference business_ads(id). order_id FK is added later
-- via ALTER TABLE to break the circular dependency.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.app_users(id),
  order_id        uuid,
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
                   CHECK (status IN ('pending', 'approved', 'rejected', 'active', 'expired', 'paused')),
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

DROP POLICY IF EXISTS "users can view own business ads" ON public.business_ads;
CREATE POLICY "users can view own business ads"
  ON public.business_ads FOR SELECT
  USING (current_setting('app.current_user_id', true)::uuid = user_id);

DROP POLICY IF EXISTS "public can view approved active business ads" ON public.business_ads;
CREATE POLICY "public can view approved active business ads"
  ON public.business_ads FOR SELECT
  USING (status = 'active');

DROP POLICY IF EXISTS "users can create own business ads" ON public.business_ads;
CREATE POLICY "users can create own business ads"
  ON public.business_ads FOR INSERT
  WITH CHECK (current_setting('app.current_user_id', true)::uuid = user_id);

DROP POLICY IF EXISTS "users can update own ads before approval" ON public.business_ads;
CREATE POLICY "users can update own ads before approval"
  ON public.business_ads FOR UPDATE
  USING (
    current_setting('app.current_user_id', true)::uuid = user_id
    AND status IN ('pending', 'rejected')
  )
  WITH CHECK (
    current_setting('app.current_user_id', true)::uuid = user_id
    AND status IN ('pending', 'rejected')
  );

DROP POLICY IF EXISTS "users can delete own ads before approval" ON public.business_ads;
CREATE POLICY "users can delete own ads before approval"
  ON public.business_ads FOR DELETE
  USING (
    current_setting('app.current_user_id', true)::uuid = user_id
    AND status IN ('pending', 'rejected')
  );

DROP POLICY IF EXISTS "admins can manage business ads" ON public.business_ads;
CREATE POLICY "admins can manage business ads"
  ON public.business_ads FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.business_ads TO motri_backend;

-- ============================================================
-- Orders Table — tracks payment flow per ad
-- Created AFTER business_ads so FK ad_id -> business_ads(id) resolves.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id           uuid NOT NULL REFERENCES public.business_ads(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.app_users(id),
  package_id      uuid NOT NULL REFERENCES public.business_ad_packages(id),
  package_price   numeric NOT NULL,
  payment_status  text NOT NULL DEFAULT 'unpaid'
                   CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'failed', 'refunded')),
  payment_method  text NOT NULL DEFAULT 'manual',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_ad_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users can view own orders" ON public.business_ad_orders;
CREATE POLICY "users can view own orders"
  ON public.business_ad_orders FOR SELECT
  USING (current_setting('app.current_user_id', true)::uuid = user_id);

DROP POLICY IF EXISTS "users can create own orders" ON public.business_ad_orders;
CREATE POLICY "users can create own orders"
  ON public.business_ad_orders FOR INSERT
  WITH CHECK (current_setting('app.current_user_id', true)::uuid = user_id);

DROP POLICY IF EXISTS "admins can view all orders" ON public.business_ad_orders;
CREATE POLICY "admins can view all orders"
  ON public.business_ad_orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  );

DROP POLICY IF EXISTS "admins can update orders" ON public.business_ad_orders;
CREATE POLICY "admins can update orders"
  ON public.business_ad_orders FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.business_ad_orders TO motri_backend;

-- ============================================================
-- Close circular FK: business_ads.order_id -> business_ad_orders(id)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'business_ads_order_id_fkey'
      AND conrelid = 'public.business_ads'::regclass
  ) THEN
    ALTER TABLE public.business_ads
      ADD CONSTRAINT business_ads_order_id_fkey
      FOREIGN KEY (order_id) REFERENCES public.business_ad_orders(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- Events Table — tracks view/click/call statistics
-- ============================================================
CREATE TABLE IF NOT EXISTS public.business_ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id       uuid NOT NULL REFERENCES public.business_ads(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN ('view', 'click', 'call', 'whatsapp', 'map', 'share')),
  user_id     uuid REFERENCES public.app_users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  ip_address  inet
);

ALTER TABLE public.business_ad_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone can log ad events" ON public.business_ad_events;
CREATE POLICY "anyone can log ad events"
  ON public.business_ad_events FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.business_ads
      WHERE id = ad_id AND status = 'active'
    )
  );

DROP POLICY IF EXISTS "users can view own ad events" ON public.business_ad_events;
CREATE POLICY "users can view own ad events"
  ON public.business_ad_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.business_ads
      WHERE id = ad_id AND user_id = current_setting('app.current_user_id', true)::uuid
    )
    OR EXISTS (
      SELECT 1 FROM public.app_admins a
      WHERE a.user_id = current_setting('app.current_user_id', true)::uuid
    )
  );

GRANT SELECT, INSERT ON public.business_ad_events TO motri_backend;

-- ============================================================
-- RPC: Safely increment counters (only for active ads)
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
    UPDATE public.business_ads
       SET views_count = views_count + 1
     WHERE id = p_ad_id AND status = 'active';
  ELSIF p_counter = 'clicks_count' THEN
    UPDATE public.business_ads
       SET clicks_count = clicks_count + 1
     WHERE id = p_ad_id AND status = 'active';
  ELSIF p_counter = 'calls_count' THEN
    UPDATE public.business_ads
       SET calls_count = calls_count + 1
     WHERE id = p_ad_id AND status = 'active';
  ELSIF p_counter = 'whatsapp_clicks' THEN
    UPDATE public.business_ads
       SET whatsapp_clicks = whatsapp_clicks + 1
     WHERE id = p_ad_id AND status = 'active';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_ad_counter(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_ad_counter(uuid, text) TO motri_backend;

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

DROP TRIGGER IF EXISTS business_ads_expire_trigger ON public.business_ads;
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

DROP TRIGGER IF EXISTS business_ads_updated_at_trigger ON public.business_ads;
CREATE TRIGGER business_ads_updated_at_trigger
  BEFORE UPDATE ON public.business_ads
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS business_ad_orders_updated_at_trigger ON public.business_ad_orders;
CREATE TRIGGER business_ad_orders_updated_at_trigger
  BEFORE UPDATE ON public.business_ad_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS business_ad_packages_updated_at_trigger ON public.business_ad_packages;
CREATE TRIGGER business_ad_packages_updated_at_trigger
  BEFORE UPDATE ON public.business_ad_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
