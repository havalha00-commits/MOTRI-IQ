-- سوالف السيارات: جداول المناقشة الاجتماعية العراقية للسيارات

CREATE TABLE IF NOT EXISTS public.car_talk_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city text,
  province text,
  brand text,
  model text,
  year integer,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.car_talk_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.car_talk_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  parent_comment_id uuid REFERENCES public.car_talk_comments(id) ON DELETE CASCADE,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.car_talk_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.car_talk_posts(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('inappropriate', 'spam', 'fraud', 'abuse', 'other')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, reporter_id)
);

ALTER TABLE public.car_talk_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_talk_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_talk_reports ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT SELECT ON public.car_talk_posts TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.car_talk_posts TO authenticated;

GRANT SELECT ON public.car_talk_comments TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.car_talk_comments TO authenticated;

GRANT SELECT ON public.car_talk_reports TO anon, authenticated;
GRANT INSERT ON public.car_talk_reports TO authenticated;

-- RLS Policies: posts
DROP POLICY IF EXISTS "posts readable by authenticated" ON public.car_talk_posts;
CREATE POLICY "posts readable by authenticated"
  ON public.car_talk_posts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users insert own posts" ON public.car_talk_posts;
CREATE POLICY "users insert own posts"
  ON public.car_talk_posts FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "authors update own posts" ON public.car_talk_posts;
CREATE POLICY "authors update own posts"
  ON public.car_talk_posts FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "authors delete own posts" ON public.car_talk_posts;
CREATE POLICY "authors delete own posts"
  ON public.car_talk_posts FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- RLS Policies: comments
DROP POLICY IF EXISTS "comments readable by authenticated" ON public.car_talk_comments;
CREATE POLICY "comments readable by authenticated"
  ON public.car_talk_comments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users insert own comments" ON public.car_talk_comments;
CREATE POLICY "users insert own comments"
  ON public.car_talk_comments FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "authors update own comments" ON public.car_talk_comments;
CREATE POLICY "authors update own comments"
  ON public.car_talk_comments FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "authors delete own comments" ON public.car_talk_comments;
CREATE POLICY "authors delete own comments"
  ON public.car_talk_comments FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- RLS Policies: reports
DROP POLICY IF EXISTS "reports readable by authenticated" ON public.car_talk_reports;
CREATE POLICY "reports readable by authenticated"
  ON public.car_talk_reports FOR SELECT TO authenticated USING (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "users insert own reports" ON public.car_talk_reports;
CREATE POLICY "users insert own reports"
  ON public.car_talk_reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_car_talk_posts_user_id ON public.car_talk_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_car_talk_posts_province ON public.car_talk_posts(province);
CREATE INDEX IF NOT EXISTS idx_car_talk_posts_created_at ON public.car_talk_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_car_talk_comments_post_id ON public.car_talk_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_car_talk_comments_post_id_created_at ON public.car_talk_comments(post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_car_talk_comments_parent_id ON public.car_talk_comments(parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_car_talk_comments_user_id ON public.car_talk_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_car_talk_reports_post_id ON public.car_talk_reports(post_id);

-- Trigger to update updated_at on posts
CREATE OR REPLACE FUNCTION public.update_car_talk_posts_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_car_talk_posts_updated_at ON public.car_talk_posts;
CREATE TRIGGER trigger_car_talk_posts_updated_at
  BEFORE UPDATE ON public.car_talk_posts
  FOR EACH ROW EXECUTE FUNCTION public.update_car_talk_posts_updated_at();

CREATE OR REPLACE FUNCTION public.update_car_talk_comments_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_car_talk_comments_updated_at ON public.car_talk_comments;
CREATE TRIGGER trigger_car_talk_comments_updated_at
  BEFORE UPDATE ON public.car_talk_comments
  FOR EACH ROW EXECUTE FUNCTION public.update_car_talk_comments_updated_at();

NOTIFY pgrst, 'reload schema';
