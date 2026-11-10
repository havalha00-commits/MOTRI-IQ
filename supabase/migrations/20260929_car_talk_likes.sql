-- Car Talk Likes: Add likes table for post reactions

CREATE TABLE IF NOT EXISTS public.car_talk_post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.car_talk_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id)
);

ALTER TABLE public.car_talk_post_likes ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT SELECT ON public.car_talk_post_likes TO anon, authenticated;
GRANT INSERT, DELETE ON public.car_talk_post_likes TO authenticated;

-- RLS Policies
DROP POLICY IF EXISTS "likes readable by authenticated" ON public.car_talk_post_likes;
CREATE POLICY "likes readable by authenticated"
  ON public.car_talk_post_likes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users insert own likes" ON public.car_talk_post_likes;
CREATE POLICY "users insert own likes"
  ON public.car_talk_post_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "users delete own likes" ON public.car_talk_post_likes;
CREATE POLICY "users delete own likes"
  ON public.car_talk_post_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_talk_post_likes_post_id ON public.car_talk_post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_car_talk_post_likes_user_id ON public.car_talk_post_likes(user_id);

-- Trigger to update likes_count on car_talk_posts
CREATE OR REPLACE FUNCTION public.update_car_talk_posts_likes_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.car_talk_posts
    SET likes_count = likes_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.car_talk_posts
    SET likes_count = likes_count - 1
    WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_car_talk_post_likes_count ON public.car_talk_post_likes;
CREATE TRIGGER trigger_car_talk_post_likes_count
  AFTER INSERT OR DELETE ON public.car_talk_post_likes
  FOR EACH ROW EXECUTE FUNCTION public.update_car_talk_posts_likes_count();

NOTIFY pgrst, 'reload schema';