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

ALTER TABLE public.seller_reviews ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.seller_reviews TO anon, authenticated;
GRANT INSERT, UPDATE ON public.seller_reviews TO authenticated;

DROP POLICY IF EXISTS "reviews are public" ON public.seller_reviews;
CREATE POLICY "reviews are public"
  ON public.seller_reviews FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "authenticated users can review sellers" ON public.seller_reviews;
CREATE POLICY "authenticated users can review sellers"
  ON public.seller_reviews FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = reviewer_id AND auth.uid() <> seller_id);

DROP POLICY IF EXISTS "reviewers update own review" ON public.seller_reviews;
CREATE POLICY "reviewers update own review"
  ON public.seller_reviews FOR UPDATE
  TO authenticated
  USING (auth.uid() = reviewer_id)
  WITH CHECK (auth.uid() = reviewer_id AND auth.uid() <> seller_id);

NOTIFY pgrst, 'reload schema';
