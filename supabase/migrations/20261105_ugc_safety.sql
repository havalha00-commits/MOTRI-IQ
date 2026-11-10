CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_blocks FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.user_blocks TO authenticated;

CREATE SCHEMA IF NOT EXISTS motri_ugc_internal;
REVOKE ALL ON SCHEMA motri_ugc_internal FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA motri_ugc_internal TO authenticated;

DROP POLICY IF EXISTS "users manage their own blocks" ON public.user_blocks;
CREATE POLICY "users manage their own blocks"
  ON public.user_blocks FOR ALL TO authenticated
  USING (auth.uid() = blocker_id)
  WITH CHECK (auth.uid() = blocker_id AND auth.uid() <> blocked_id);

CREATE OR REPLACE FUNCTION motri_ugc_internal.chat_user_blocked(
  user_a uuid,
  user_b uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT auth.uid() IS NOT NULL
    AND auth.uid() IN (user_a, user_b)
    AND EXISTS (
      SELECT 1
      FROM public.user_blocks
      WHERE (blocker_id = user_a AND blocked_id = user_b)
         OR (blocker_id = user_b AND blocked_id = user_a)
    );
$$;

CREATE OR REPLACE FUNCTION motri_ugc_internal.offer_chat_available(
  target_offer_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.car_offers AS offer
      WHERE offer.id = target_offer_id
        AND auth.uid() IN (offer.buyer_id, offer.seller_id)
        AND NOT motri_ugc_internal.chat_user_blocked(
          offer.buyer_id,
          offer.seller_id
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.chat_block_status(target_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
DECLARE
  actor_id uuid := auth.uid();
BEGIN
  IF actor_id IS NULL OR target_user_id IS NULL OR actor_id = target_user_id
     OR NOT EXISTS (
       SELECT 1
       FROM public.car_offers AS offer
       WHERE (offer.buyer_id = actor_id AND offer.seller_id = target_user_id)
          OR (offer.seller_id = actor_id AND offer.buyer_id = target_user_id)
     ) THEN
    RAISE EXCEPTION 'Not authorized to inspect this chat';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_blocks
    WHERE blocker_id = actor_id AND blocked_id = target_user_id
  ) THEN
    RETURN 'blocked_by_me';
  ELSIF EXISTS (
    SELECT 1 FROM public.user_blocks
    WHERE blocker_id = target_user_id AND blocked_id = actor_id
  ) THEN
    RETURN 'blocked_me';
  END IF;
  RETURN 'none';
END;
$$;

REVOKE ALL ON FUNCTION motri_ugc_internal.chat_user_blocked(uuid, uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION motri_ugc_internal.offer_chat_available(uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_block_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION motri_ugc_internal.chat_user_blocked(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION motri_ugc_internal.offer_chat_available(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_block_status(uuid) TO authenticated;

DROP POLICY IF EXISTS "blocks restrict offer visibility" ON public.car_offers;
CREATE POLICY "blocks restrict offer visibility"
  ON public.car_offers AS RESTRICTIVE FOR SELECT TO authenticated
  USING (NOT motri_ugc_internal.chat_user_blocked(buyer_id, seller_id));

DROP POLICY IF EXISTS "blocks restrict offer creation" ON public.car_offers;
CREATE POLICY "blocks restrict offer creation"
  ON public.car_offers AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (
    buyer_id = auth.uid()
    AND NOT motri_ugc_internal.chat_user_blocked(buyer_id, seller_id)
  );

DROP POLICY IF EXISTS "blocks restrict message reads" ON public.car_offer_messages;
CREATE POLICY "blocks restrict message reads"
  ON public.car_offer_messages AS RESTRICTIVE FOR SELECT TO authenticated
  USING (motri_ugc_internal.offer_chat_available(offer_id));

DROP POLICY IF EXISTS "blocks restrict message sends" ON public.car_offer_messages;
CREATE POLICY "blocks restrict message sends"
  ON public.car_offer_messages AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND motri_ugc_internal.offer_chat_available(offer_id)
  );

CREATE TABLE IF NOT EXISTS public.user_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  offer_id uuid NOT NULL REFERENCES public.car_offers(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (
    reason IN ('harassment', 'hate_speech', 'sexual_content', 'spam', 'fraud', 'other')
  ),
  details text NOT NULL DEFAULT '' CHECK (length(details) <= 2000),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  admin_note text,
  CHECK (reporter_id <> reported_user_id)
);

CREATE INDEX IF NOT EXISTS user_reports_created_idx
  ON public.user_reports (created_at DESC);
CREATE INDEX IF NOT EXISTS user_reports_status_created_idx
  ON public.user_reports (status, created_at DESC);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_reports FROM anon, authenticated;
GRANT INSERT, SELECT, UPDATE (status, reviewed_by, reviewed_at, admin_note)
  ON public.user_reports TO authenticated;

CREATE OR REPLACE FUNCTION motri_ugc_internal.user_report_context_valid(
  target_offer_id uuid,
  report_author_id uuid,
  report_target_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT auth.uid() = report_author_id
    AND report_author_id <> report_target_id
    AND EXISTS (
      SELECT 1
      FROM public.car_offers AS offer
      WHERE offer.id = target_offer_id
        AND (
          (offer.buyer_id = report_author_id AND offer.seller_id = report_target_id)
          OR (offer.seller_id = report_author_id AND offer.buyer_id = report_target_id)
        )
    );
$$;

REVOKE ALL ON FUNCTION motri_ugc_internal.user_report_context_valid(
  uuid,
  uuid,
  uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION motri_ugc_internal.user_report_context_valid(
  uuid,
  uuid,
  uuid
) TO authenticated;

DROP POLICY IF EXISTS "users can report chat participants" ON public.user_reports;
CREATE POLICY "users can report chat participants"
  ON public.user_reports FOR INSERT TO authenticated
  WITH CHECK (
    motri_ugc_internal.user_report_context_valid(
      offer_id,
      reporter_id,
      reported_user_id
    )
  );

DROP POLICY IF EXISTS "admins can view user reports" ON public.user_reports;
CREATE POLICY "admins can view user reports"
  ON public.user_reports FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "admins can update user reports" ON public.user_reports;
CREATE POLICY "admins can update user reports"
  ON public.user_reports FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.app_admins WHERE user_id = auth.uid()
  ));

CREATE TABLE IF NOT EXISTS public.ugc_policy_acceptances (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  policy_version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, policy_version)
);

ALTER TABLE public.ugc_policy_acceptances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ugc_policy_acceptances FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.has_accepted_ugc_policy()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.ugc_policy_acceptances
    WHERE user_id = auth.uid() AND policy_version = '2026-11-05'
  );
$$;

CREATE OR REPLACE FUNCTION public.accept_ugc_policy(policy_version text)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
BEGIN
  IF auth.uid() IS NULL OR policy_version <> '2026-11-05' THEN
    RAISE EXCEPTION 'Invalid policy acceptance';
  END IF;

  INSERT INTO public.ugc_policy_acceptances (user_id, policy_version)
  VALUES (auth.uid(), policy_version)
  ON CONFLICT (user_id, policy_version) DO NOTHING;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_ugc_policy_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.has_accepted_ugc_policy() THEN
    RAISE EXCEPTION 'ugc_policy_acceptance_required'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.has_accepted_ugc_policy() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_ugc_policy(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.require_ugc_policy_acceptance() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_accepted_ugc_policy() TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_ugc_policy(text) TO authenticated;

DO $$
DECLARE
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'cars', 'market_items', 'jobs', 'car_requests', 'business_ads',
    'car_talk_posts', 'car_talk_comments'
  ] LOOP
    IF to_regclass('public.' || quote_ident(target_table)) IS NOT NULL THEN
      EXECUTE format(
        'DROP TRIGGER IF EXISTS require_ugc_policy_acceptance ON public.%I',
        target_table
      );
      EXECUTE format(
        'CREATE TRIGGER require_ugc_policy_acceptance BEFORE INSERT ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.require_ugc_policy_acceptance()',
        target_table
      );
    END IF;
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
