CREATE TABLE IF NOT EXISTS public.app_usernames (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_usernames_username_format
    CHECK (username ~ '^[a-z0-9_]{3,24}$')
);

ALTER TABLE public.app_usernames ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.app_usernames FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.app_usernames TO service_role;

CREATE OR REPLACE FUNCTION public.register_auth_username()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_username text;
BEGIN
  normalized_username := lower(trim(NEW.raw_user_meta_data->>'username'));

  IF normalized_username IS NULL
     OR normalized_username !~ '^[a-z0-9_]{3,24}$' THEN
    RAISE EXCEPTION 'Username must be 3-24 letters, numbers, or underscores';
  END IF;

  INSERT INTO public.app_usernames (user_id, username)
  VALUES (NEW.id, normalized_username);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.register_auth_username() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS auth_user_register_username ON auth.users;
CREATE TRIGGER auth_user_register_username
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.register_auth_username();

CREATE OR REPLACE FUNCTION public.set_my_username(p_username text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_username text := lower(trim(p_username));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;

  IF normalized_username IS NULL
     OR normalized_username !~ '^[a-z0-9_]{3,24}$' THEN
    RAISE EXCEPTION 'Username must be 3-24 letters, numbers, or underscores';
  END IF;

  INSERT INTO public.app_usernames (user_id, username)
  VALUES (auth.uid(), normalized_username)
  ON CONFLICT (user_id)
  DO UPDATE SET username = EXCLUDED.username;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_username(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_username(text) TO authenticated;