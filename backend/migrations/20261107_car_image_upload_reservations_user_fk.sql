-- G10.42.23: harden car_image_upload_reservations ownership integrity (motri_iq_test/app DBs).
-- Safe: no app-level DELETE /api/users endpoint found; reservation cleanup only deletes expired unconsumed;
-- ON DELETE CASCADE ensures orphan prevention on legitimate user removal. Check orphans before apply.
BEGIN;

DO $$
DECLARE orphan_count bigint;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM public.car_image_upload_reservations r
  WHERE NOT EXISTS (SELECT 1 FROM public.app_users u WHERE u.id = r.user_id);
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'Refusing: % orphan reservation row(s) with no app_users owner', orphan_count;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'car_image_upload_reservations_user_id_fkey') THEN
    ALTER TABLE public.car_image_upload_reservations
      ADD CONSTRAINT car_image_upload_reservations_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE CASCADE;
  END IF;
END $$;

COMMIT;
