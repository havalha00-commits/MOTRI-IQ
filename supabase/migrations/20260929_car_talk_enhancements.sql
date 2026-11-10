-- Car Talk Enhancements: Add missing columns and indexes for community features

-- Add missing columns to car_talk_posts
ALTER TABLE public.car_talk_posts
ADD COLUMN IF NOT EXISTS image_url text,
ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS comments_count integer NOT NULL DEFAULT 0;

-- Add missing index for comments created_at ordering
CREATE INDEX IF NOT EXISTS idx_car_talk_comments_created_at ON public.car_talk_comments(created_at);

-- Update RLS grants to include new columns (grants already cover all columns)
-- No additional RLS policies needed - existing policies cover new columns

-- Verify the updated schema
COMMENT ON COLUMN public.car_talk_posts.image_url IS 'Optional image URL for the post';
COMMENT ON COLUMN public.car_talk_posts.likes_count IS 'Cached count of likes for this post';
COMMENT ON COLUMN public.car_talk_posts.comments_count IS 'Cached count of comments for this post';

NOTIFY pgrst, 'reload schema';