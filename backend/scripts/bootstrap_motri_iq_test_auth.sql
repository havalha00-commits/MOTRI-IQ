-- G10.42.21: test-only bootstrap for motri_iq_test (isolated). No auth.users, no prod data.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- app_admins (referenced by auth queries)
CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id UUID PRIMARY KEY REFERENCES public.app_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- app_users columns required by backend/routes/auth.js
ALTER TABLE public.app_users ADD COLUMN IF NOT EXISTS encrypted_password TEXT;
ALTER TABLE public.app_users ADD COLUMN IF NOT EXISTS raw_user_meta_data JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.app_users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.app_users ALTER COLUMN email_confirmed_at SET DEFAULT now();
ALTER TABLE public.app_users ALTER COLUMN updated_at SET DEFAULT now();
CREATE UNIQUE INDEX IF NOT EXISTS app_users_email_normalized_unique
  ON public.app_users (lower(trim(email))) WHERE email IS NOT NULL AND trim(email) <> '';

-- profiles columns required by register/login/refresh
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS activation_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_normalized_unique
  ON public.profiles (lower(trim(username))) WHERE username IS NOT NULL AND trim(username) <> '';

-- app_sessions required by auth + middleware (refresh_token_hash, last_used_at, constraints)
ALTER TABLE public.app_sessions ADD COLUMN IF NOT EXISTS refresh_token_hash CHAR(64);
ALTER TABLE public.app_sessions ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;
UPDATE public.app_sessions SET refresh_token_hash = encode(gen_random_bytes(32), 'hex') WHERE refresh_token_hash IS NULL;
ALTER TABLE public.app_sessions ALTER COLUMN refresh_token_hash SET NOT NULL;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='app_sessions_refresh_token_hash_key') THEN
    ALTER TABLE public.app_sessions ADD CONSTRAINT app_sessions_refresh_token_hash_key UNIQUE (refresh_token_hash);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='app_sessions_token_hash_format') THEN
    ALTER TABLE public.app_sessions ADD CONSTRAINT app_sessions_token_hash_format CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='app_sessions_expiry_valid') THEN
    ALTER TABLE public.app_sessions ADD CONSTRAINT app_sessions_expiry_valid CHECK (expires_at > created_at);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_app_sessions_user_id ON public.app_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_app_sessions_expires_at ON public.app_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_app_sessions_refresh_hash ON public.app_sessions(refresh_token_hash);

-- cars: ensure user_id FK to app_users (test isolation; no prod data copied)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='cars_user_id_fkey') THEN
    ALTER TABLE public.cars ADD CONSTRAINT cars_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE CASCADE;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_cars_user_id ON public.cars(user_id);

-- car_image_upload_reservations ownership integrity (G10.42.23)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'car_image_upload_reservations_user_id_fkey') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.car_image_upload_reservations r
      WHERE NOT EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = r.user_id)
    ) THEN
      ALTER TABLE public.car_image_upload_reservations
        ADD CONSTRAINT car_image_upload_reservations_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- car_image_upload_reservations indexes (migration parity)
CREATE INDEX IF NOT EXISTS car_image_upload_reservations_user_submission_idx
  ON public.car_image_upload_reservations (user_id, submission_id);
CREATE INDEX IF NOT EXISTS car_image_upload_reservations_expires_at_idx
  ON public.car_image_upload_reservations (expires_at);

COMMIT;
