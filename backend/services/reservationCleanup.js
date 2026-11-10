export async function cleanupExpiredReservations({ database, batchSize = 100, logger = console } = {}) {
  if (!database) throw new Error("Database unavailable");
  const size = Math.min(Math.max(Number(batchSize) || 100, 1), 1000);
  const result = await database.query(
    `DELETE FROM public.car_image_upload_reservations
     WHERE id IN (
       SELECT id FROM public.car_image_upload_reservations
       WHERE consumed_at IS NULL AND expires_at <= NOW()
       ORDER BY expires_at
       LIMIT $1
       FOR UPDATE SKIP LOCKED
     )
     RETURNING id`,
    [size]
  );
  logger.info?.(`Expired reservation cleanup removed ${result.rows.length} rows`);
  return { deleted: result.rows.length };
}
