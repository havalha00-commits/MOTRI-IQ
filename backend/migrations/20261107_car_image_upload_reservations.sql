BEGIN;

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

CREATE INDEX IF NOT EXISTS car_image_upload_reservations_user_submission_idx
  ON public.car_image_upload_reservations (user_id, submission_id);

CREATE INDEX IF NOT EXISTS car_image_upload_reservations_expires_at_idx
  ON public.car_image_upload_reservations (expires_at);

COMMIT;
