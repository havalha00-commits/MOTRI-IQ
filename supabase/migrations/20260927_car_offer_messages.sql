CREATE TABLE IF NOT EXISTS public.car_offer_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES public.car_offers(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (length(trim(body)) > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS car_offer_messages_offer_created_idx
  ON public.car_offer_messages (offer_id, created_at);

ALTER TABLE public.car_offer_messages ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.car_offer_messages TO authenticated;

DROP POLICY IF EXISTS "participants read accepted offer messages"
  ON public.car_offer_messages;
CREATE POLICY "participants read accepted offer messages"
  ON public.car_offer_messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.car_offers AS offer
      WHERE offer.id = car_offer_messages.offer_id
        AND offer.status = 'accepted'
        AND auth.uid() IN (offer.buyer_id, offer.seller_id)
    )
  );

DROP POLICY IF EXISTS "participants send accepted offer messages"
  ON public.car_offer_messages;
CREATE POLICY "participants send accepted offer messages"
  ON public.car_offer_messages FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1
      FROM public.car_offers AS offer
      WHERE offer.id = car_offer_messages.offer_id
        AND offer.status = 'accepted'
        AND auth.uid() IN (offer.buyer_id, offer.seller_id)
    )
  );

NOTIFY pgrst, 'reload schema';