BEGIN;

DO $migration$
DECLARE
    source_count BIGINT;
BEGIN
    IF to_regclass('public.app_users') IS NOT NULL THEN
        RAISE EXCEPTION 'public.app_users already exists; refusing to overwrite it';
    END IF;

    IF to_regclass('public.app_sessions') IS NOT NULL THEN
        RAISE EXCEPTION 'public.app_sessions already exists; refusing to overwrite it';
    END IF;

    SELECT count(*) INTO source_count FROM auth.users;
    IF source_count <> 8 THEN
        RAISE EXCEPTION 'Expected 8 auth.users rows, found %; inspect before migration', source_count;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM auth.users
        WHERE email IS NOT NULL
        GROUP BY lower(trim(email))
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate normalized email found; inspect before migration';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE username IS NOT NULL
        GROUP BY lower(trim(username))
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate normalized username found; inspect before migration';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM auth.users u
        LEFT JOIN public.profiles p ON p.id = u.id
        WHERE p.id IS NULL
    ) THEN
        RAISE EXCEPTION 'An auth.users row has no matching profile; inspect before migration';
    END IF;
END;
$migration$;

CREATE TABLE public.app_users (
    LIKE auth.users INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT app_users_pkey PRIMARY KEY (id)
);

ALTER TABLE public.app_users
    ADD COLUMN username TEXT;

INSERT INTO public.app_users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    invited_at,
    confirmation_token,
    confirmation_sent_at,
    recovery_token,
    recovery_sent_at,
    email_change_token_new,
    email_change,
    email_change_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    phone,
    phone_confirmed_at,
    phone_change,
    phone_change_token,
    phone_change_sent_at,
    confirmed_at,
    email_change_token_current,
    email_change_confirm_status,
    banned_until,
    reauthentication_token,
    reauthentication_sent_at,
    is_sso_user,
    deleted_at,
    is_anonymous
)
SELECT
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    invited_at,
    confirmation_token,
    confirmation_sent_at,
    recovery_token,
    recovery_sent_at,
    email_change_token_new,
    email_change,
    email_change_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    phone,
    phone_confirmed_at,
    phone_change,
    phone_change_token,
    phone_change_sent_at,
    confirmed_at,
    email_change_token_current,
    email_change_confirm_status,
    banned_until,
    reauthentication_token,
    reauthentication_sent_at,
    is_sso_user,
    deleted_at,
    is_anonymous
FROM auth.users;

UPDATE public.app_users u
SET username = p.username
FROM public.profiles p
WHERE p.id = u.id;

CREATE UNIQUE INDEX app_users_email_normalized_unique
    ON public.app_users (lower(trim(email)))
    WHERE email IS NOT NULL AND trim(email) <> '';

CREATE UNIQUE INDEX app_users_username_normalized_unique
    ON public.app_users (lower(trim(username)))
    WHERE username IS NOT NULL AND trim(username) <> '';

CREATE TABLE public.app_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
    refresh_token_hash CHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    CONSTRAINT app_sessions_token_hash_format
        CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT app_sessions_expiry_valid
        CHECK (expires_at > created_at)
);

CREATE INDEX idx_app_sessions_user_id
    ON public.app_sessions(user_id);

CREATE INDEX idx_app_sessions_expires_at
    ON public.app_sessions(expires_at);

DO $verification$
DECLARE
    source_count BIGINT;
    target_count BIGINT;
    mismatch_count BIGINT;
BEGIN
    SELECT count(*) INTO source_count FROM auth.users;
    SELECT count(*) INTO target_count FROM public.app_users;

    IF source_count <> target_count THEN
        RAISE EXCEPTION 'Account count mismatch: source %, target %', source_count, target_count;
    END IF;

    SELECT count(*) INTO mismatch_count
    FROM auth.users source
    FULL JOIN public.app_users target ON target.id = source.id
    WHERE source.id IS NULL
       OR target.id IS NULL
       OR to_jsonb(source) IS DISTINCT FROM (to_jsonb(target) - 'username');

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Account data mismatch for % rows', mismatch_count;
    END IF;

    SELECT count(*) INTO mismatch_count
    FROM public.app_users u
    JOIN public.profiles p ON p.id = u.id
    WHERE u.username IS DISTINCT FROM p.username;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Username mismatch for % rows', mismatch_count;
    END IF;
END;
$verification$;

COMMIT;
