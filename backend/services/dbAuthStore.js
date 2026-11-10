import crypto from "node:crypto";

const DEFAULT_TTL_SECONDS = 300;

// طبقة مستقلة لإدارة upload_authorizations في Neon.
// لا تستخدم Map كحل إنتاجي. الاستهلاك ذري عبر UPDATE مشروط.
export function createDbAuthStore({ database } = {}) {
  if (!database || typeof database.query !== "function") {
    throw new Error("dbAuthStore: a database instance with a query method is required");
  }

  async function create({
    userId,
    txId,
    objectKey,
    bucket = "wallet_receipts",
    ttlSeconds = DEFAULT_TTL_SECONDS,
  } = {}) {
    if (!userId || !txId || !objectKey || !bucket) {
      throw new Error("dbAuthStore.create: userId, txId, objectKey, and bucket are required");
    }
    const id = crypto.randomBytes(16).toString("hex");
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();

    const result = await database.query(
      `INSERT INTO public.upload_authorizations
         (id, user_id, tx_id, object_key, bucket, expires_at, used)
       VALUES ($1, $2, $3, $4, $5, $6, FALSE)
       RETURNING id, object_key, bucket, expires_at`,
      [id, userId, txId, objectKey, bucket, expiresAt]
    );

    if (result.rows.length !== 1) {
      throw new Error("dbAuthStore.create: failed to insert upload authorization");
    }

    const row = result.rows[0];
    return {
      id: row.id,
      objectKey: row.object_key,
      bucket: row.bucket,
      expiresAt: new Date(row.expires_at).getTime(),
    };
  }

  // استهلاك ذري: يُنجح مرة واحدة فقط حتى مع طلبات متزامنة.
  // يُعيد سجلاً واحداً فقط عند النجاح، null في حال عدم التطابق أو الانتهاء أو الاستخدام المسبق.
  async function consume(id, { txId, userId, objectKey } = {}) {
    if (!id || !txId || !userId || !objectKey) {
      return null;
    }

    const result = await database.query(
      `UPDATE public.upload_authorizations
         SET used = TRUE
       WHERE id = $1
         AND user_id = $2
         AND tx_id = $3
         AND object_key = $4
         AND used = FALSE
         AND expires_at > NOW()
       RETURNING user_id, tx_id, object_key, bucket, expires_at`,
      [id, userId, txId, objectKey]
    );

    if (result.rows.length === 0) {
      return null;
    }
    if (result.rows.length > 1) {
      throw new Error("dbAuthStore.consume: returned more than one row");
    }

    const row = result.rows[0];
    return {
      userId: row.user_id,
      txId: row.tx_id,
      objectKey: row.object_key,
      bucket: row.bucket,
      expiresAt: new Date(row.expires_at).getTime(),
      used: true,
    };
  }

  async function revoke(id) {
    if (!id) return;
    await database.query(
      `DELETE FROM public.upload_authorizations WHERE id = $1`,
      [id]
    );
  }

  async function get(id) {
    if (!id) return null;
    const result = await database.query(
      `SELECT id, user_id, tx_id, object_key, bucket, expires_at, used
       FROM public.upload_authorizations
       WHERE id = $1`,
      [id]
    );
    if (result.rows.length === 0) return null;
    const row = result.rows[0];
    return {
      id: row.id,
      userId: row.user_id,
      txId: row.tx_id,
      objectKey: row.object_key,
      bucket: row.bucket,
      expiresAt: new Date(row.expires_at).getTime(),
      used: row.used,
    };
  }

  return { create, consume, revoke, get };
}
