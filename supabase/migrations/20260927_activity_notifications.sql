CREATE TABLE IF NOT EXISTS public.activity_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type text NOT NULL CHECK (
    notification_type IN ('new_offer', 'offer_accepted', 'new_message')
  ),
  offer_id uuid NOT NULL REFERENCES public.car_offers(id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

CREATE INDEX IF NOT EXISTS activity_notifications_user_created_idx
  ON public.activity_notifications (user_id, created_at DESC);

ALTER TABLE public.activity_notifications ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.activity_notifications TO authenticated;
GRANT UPDATE (read_at) ON public.activity_notifications TO authenticated;

DROP POLICY IF EXISTS "users read own activity notifications"
  ON public.activity_notifications;
CREATE POLICY "users read own activity notifications"
  ON public.activity_notifications FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "users mark own activity notifications read"
  ON public.activity_notifications;
CREATE POLICY "users mark own activity notifications read"
  ON public.activity_notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.notify_car_offer_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.activity_notifications
      (user_id, notification_type, offer_id, title, body)
    VALUES
      (NEW.seller_id, 'new_offer', NEW.id, 'عرض سعر جديد',
       'وصلك عرض على ' || NEW.car_title || ' بسعر ' || NEW.offer_price || ' دولار');
  ELSIF TG_OP = 'UPDATE'
      AND OLD.status IS DISTINCT FROM NEW.status
      AND NEW.status = 'accepted' THEN
    INSERT INTO public.activity_notifications
      (user_id, notification_type, offer_id, title, body)
    VALUES
      (NEW.buyer_id, 'offer_accepted', NEW.id, 'تم قبول عرضك',
       'وافق البائع على عرضك لسيارة ' || NEW.car_title);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS car_offer_activity_notification
  ON public.car_offers;
CREATE TRIGGER car_offer_activity_notification
AFTER INSERT OR UPDATE OF status ON public.car_offers
FOR EACH ROW EXECUTE FUNCTION public.notify_car_offer_activity();

CREATE OR REPLACE FUNCTION public.notify_offer_message_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  buyer_user_id uuid;
  seller_user_id uuid;
  recipient_id uuid;
  offer_title text;
BEGIN
  SELECT buyer_id, seller_id, car_title
    INTO STRICT buyer_user_id, seller_user_id, offer_title
    FROM public.car_offers
    WHERE id = NEW.offer_id;

  IF NEW.sender_id = buyer_user_id THEN
    recipient_id := seller_user_id;
  ELSE
    recipient_id := buyer_user_id;
  END IF;

  INSERT INTO public.activity_notifications
    (user_id, notification_type, offer_id, title, body)
  VALUES
    (recipient_id, 'new_message', NEW.offer_id, 'رسالة جديدة',
     'وصلتك رسالة بخصوص ' || offer_title);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS car_offer_message_activity_notification
  ON public.car_offer_messages;
CREATE TRIGGER car_offer_message_activity_notification
AFTER INSERT ON public.car_offer_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_offer_message_activity();

NOTIFY pgrst, 'reload schema';