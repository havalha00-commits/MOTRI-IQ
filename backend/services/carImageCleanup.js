export async function cleanupOrphanCarImages({ storage, database, bucket = "cars", prefix = "", retentionDays = 7, batchSize = 100, logger = console } = {}) {
  if (!storage || !database) throw new Error("Storage or database unavailable");
  const cutoff = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
  const carKeyPattern = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$/i;
  let continuationToken;
  let scanned = 0;
  let deleted = 0;
  do {
    const page = await storage.listObjects({ bucket, prefix, continuationToken, maxKeys: batchSize });
    for (const object of page.objects || []) {
      scanned += 1;
      if (!object?.key || !object.lastModified || new Date(object.lastModified).getTime() > cutoff) continue;
      // Only manage car image keys of the known shape; never touch unrelated objects.
      if (!carKeyPattern.test(object.key)) continue;
      const reserved = await database.query(
        `SELECT 1 FROM public.car_image_upload_reservations
         WHERE object_key = $1
           AND (consumed_at IS NULL AND expires_at > NOW())
         LIMIT 1`,
        [object.key]
      );
      if (reserved.rows.length > 0) continue;
      // Preserve any image referenced by a car (exact key match in image_url or images text/jsonb via cast).
      const referenced = await database.query(
        `SELECT 1 FROM public.cars
         WHERE image_url = $1
            OR (images IS NOT NULL AND images::text LIKE ('%' || $1 || '%'))
         LIMIT 1`,
        [object.key]
      );
      if (referenced.rows.length > 0) continue;
      try {
        await storage.deleteObject({ bucket, key: object.key });
        deleted += 1;
      } catch (error) {
        logger.error?.(`Failed to delete orphan ${object.key}: ${error.message}`);
      }
    }
    continuationToken = page.nextContinuationToken;
  } while (continuationToken);
  logger.info?.(`Orphan car image cleanup scanned ${scanned}, deleted ${deleted}`);
  return { scanned, deleted };
}
