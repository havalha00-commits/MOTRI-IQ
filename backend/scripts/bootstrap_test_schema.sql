BEGIN;

CREATE TABLE IF NOT EXISTS public.app_users (
    id UUID PRIMARY KEY,
    email TEXT,
    deleted_at TIMESTAMPTZ,
    banned_until TIMESTAMPTZ,
    email_confirmed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES public.app_users(id) ON DELETE CASCADE,
    is_admin BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS public.app_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
    revoked_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cars (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    title TEXT,
    brand TEXT,
    model TEXT,
    year INTEGER,
    price NUMERIC,
    governorate TEXT,
    fuel TEXT,
    transmission TEXT,
    mileage INTEGER,
    description TEXT,
    phone TEXT,
    images TEXT,
    city TEXT,
    image_url TEXT,
    province TEXT,
    body_type TEXT,
    seller_phone TEXT,
    plate_regions JSONB,
    is_approved BOOLEAN DEFAULT FALSE,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.car_image_upload_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    submission_id UUID NOT NULL,
    photo_id UUID NOT NULL,
    object_key TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, submission_id, photo_id),
    UNIQUE (object_key)
);

-- G10.52 M1C: isolated market/jobs + draft image ref fixtures (motri_iq_test only)
CREATE TABLE IF NOT EXISTS public.market_items (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    title TEXT NOT NULL,
    category TEXT,
    price NUMERIC(12,2),
    governorate TEXT,
    description TEXT,
    phone TEXT,
    images TEXT[] DEFAULT '{}'::text[],
    is_approved BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    title TEXT NOT NULL,
    company TEXT,
    governorate TEXT,
    salary NUMERIC(12,2),
    job_type TEXT,
    experience TEXT,
    description TEXT,
    phone TEXT,
    is_approved BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    images TEXT[] NULL
);

CREATE TABLE IF NOT EXISTS public.market_image_upload_refs (
    ref TEXT PRIMARY KEY,
    user_id UUID NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('market','job')),
    object_key TEXT NOT NULL,
    content_type TEXT NOT NULL,
    size_bytes INTEGER,
    status TEXT NOT NULL DEFAULT 'unbound' CHECK (status IN ('unbound','bound','expired')),
    expires_at TIMESTAMPTZ NOT NULL,
    bound_table TEXT,
    bound_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (object_key)
);
CREATE INDEX IF NOT EXISTS market_image_upload_refs_user_status_expires_idx
    ON public.market_image_upload_refs (user_id, status, expires_at);

COMMIT;
