import { Router } from "express";
import express from "express";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";
import { createDbAuthStore } from "../services/dbAuthStore.js";
import crypto from "node:crypto";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// مفاتيح محظورة في جسم طلب /topups (إدارية أو خاصة برفع الإيصال المنفصل)
const FORBIDDEN_TOPUP_FIELDS = new Set([
  "receipt_image_url",
  "status",
  "admin_id",
  "confirmed_at",
  "admin_note",
  "user_id",
]);

// نمط مفتاح الكائن للإيصالات: userId/receipts/<transactionId>_<filename>
const RECEIPT_KEY_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/receipts\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}_[A-Za-z0-9._-]+\.[A-Za-z0-9]+$/;

// فترة صلاحية إذن الرفع بالثواني (5 دقائق)
const UPLOAD_AUTH_TTL_SECONDS = 300;

// taille max d'un fichier de reçu (10 Mo)
const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

// ---------------------------------------------------------------
// نظام تخزين أذونات الرفع (Upload Authorization Store)
// ---------------------------------------------------------------
// النسخة الإنتاجية تستخدم جدول upload_authorizations في Neon عبر dbAuthStore.
// - الأذونات تبقى محفوظة بعد إعادة تشغيل Backend.
// - تُشارك بين نسخ متعددة من Backend عبر قاعدة البيانات المشتركة.
// - الاستهلاك ذري: UPDATE ... SET used = TRUE WHERE used = FALSE AND expires_at > NOW(),
//   يضمن منع إعادة استخدام الإذن حتى مع طلبات متزامنة.
// - لا يوجد حل احتياطي (fallback) إلى Map في الذاكرة.
// - إذا كانت قاعدة البيانات أو الجدول غير جاهز، تُعيد المسارات خطأً واضحاً (503)
//   ولا تلجأ تلقائياً إلى تخزين مؤقت.
// ---------------------------------------------------------------

export function createWalletRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
  uploadAuthStore = createDbAuthStore({ database }),
  storageBucket = "wallet_receipts",
} = {}) {
  const router = Router();
  router.use(authenticate);

  // ---------------------------------------------------------------
  // POST /topups — إنشاء معاملة شحن جديدة (pending، بدون إيصال)
  // ---------------------------------------------------------------
  router.post("/topups", async (req, res) => {
    const body = req.body ?? {};

    for (const field of FORBIDDEN_TOPUP_FIELDS) {
      if (Object.prototype.hasOwnProperty.call(body, field)) {
        return res.status(400).json({
          error: `Field "${field}" is not allowed in top-up request`,
        });
      }
    }

    const amount = Number.parseInt(body?.amount, 10);
    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: "Invalid amount" });
    }

    try {
      const result = await database.query(
        `INSERT INTO public.wallet_transactions
           (user_id, amount, status, payment_method, receipt_image_url)
         VALUES ($1, $2, 'pending', 'kcard', NULL)
         RETURNING id`,
        [req.user.id, amount]
      );
      return res.status(201).json({ success: true, data: { id: result.rows[0].id } });
    } catch (error) {
      console.error("Wallet topup creation failed:", error.message);
      return res.status(500).json({ error: "Failed to create topup request" });
    }
  });

  // ---------------------------------------------------------------
  // GET /topups/pending — استرجاع معاملة معلقّة للمستخدم فقط
  // ---------------------------------------------------------------
  router.get("/topups/pending", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT id, status
           FROM public.wallet_transactions
          WHERE user_id = $1 AND status = 'pending'
          ORDER BY created_at DESC
          LIMIT 1`,
        [req.user.id]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: "No pending transaction" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Wallet pending lookup failed:", error.message);
      return res.status(500).json({ error: "Failed to load pending transaction" });
    }
  });

  // ---------------------------------------------------------------
  // GET /admin/pending — قائمة المعاملات المعلقة للأدمن (مراجعة)
  // ---------------------------------------------------------------
  router.get("/admin/pending", async (req, res) => {
    try {
      const adminCheck = await database.query(
        `SELECT 1 FROM public.app_admins WHERE user_id = $1`,
        [req.user.id]
      );
      if (adminCheck.rows.length === 0) {
        return res.status(403).json({ error: "Admin access required" });
      }
      const result = await database.query(
        `SELECT
           wt.id,
           wt.user_id,
           wt.amount,
           wt.payment_method,
           wt.receipt_image_url,
           wt.created_at,
           wt.status,
           p.full_name AS requester_name
         FROM public.wallet_transactions wt
         LEFT JOIN public.profiles p ON p.id = wt.user_id
         WHERE wt.status = 'pending'
         ORDER BY wt.created_at DESC
         LIMIT 100`
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Wallet admin pending failed:", error.message);
      return res.status(500).json({ error: "Failed to load pending transactions" });
    }
  });

  // ---------------------------------------------------------------
  // GET /settings/:key — قراءة إعداد محفظة (مُصادَق عليه)
  // ---------------------------------------------------------------
  router.get("/settings/:key", async (req, res) => {
    const key = typeof req.params.key === "string" ? req.params.key.trim() : "";
    if (!/^[a-z0-9_]{1,64}$/.test(key)) {
      return res.status(400).json({ error: "Invalid setting key" });
    }
    try {
      const result = await database.query(
        `SELECT key, value FROM public.wallet_settings WHERE key = $1 LIMIT 1`,
        [key]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: "Setting not found" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Wallet setting read failed:", error.message);
      return res.status(500).json({ error: "Failed to load wallet setting" });
    }
  });

  // ---------------------------------------------------------------
  // PUT /settings/:key — تحديث إعداد محفظة (أدمن فقط)
  // ---------------------------------------------------------------
  router.put("/settings/:key", async (req, res) => {
    const key = typeof req.params.key === "string" ? req.params.key.trim() : "";
    if (!/^[a-z0-9_]{1,64}$/.test(key)) {
      return res.status(400).json({ error: "Invalid setting key" });
    }
    const value = typeof req.body?.value === "string" ? req.body.value.trim() : "";
    if (value.length === 0 || value.length > 256) {
      return res.status(400).json({ error: "Invalid setting value" });
    }
    try {
      const adminCheck = await database.query(
        `SELECT 1 FROM public.app_admins WHERE user_id = $1`,
        [req.user.id]
      );
      if (adminCheck.rows.length === 0) {
        return res.status(403).json({ error: "Admin access required" });
      }
      const result = await database.query(
        `INSERT INTO public.wallet_settings (key, value, updated_at, updated_by)
         VALUES ($1, $2, NOW(), $3)
         ON CONFLICT (key) DO UPDATE
           SET value = EXCLUDED.value,
               updated_at = NOW(),
               updated_by = EXCLUDED.updated_by
         RETURNING key, value`,
        [key, value, req.user.id]
      );
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Wallet setting update failed:", error.message);
      return res.status(500).json({ error: "Failed to update wallet setting" });
    }
  });

  // ---------------------------------------------------------------
  // POST /topups/:txId/receipt/authorize — إصدار إذن رفع إيصال
  // الخادم يحدّد object_key؛ العميل لا يرسل ولا يغيّر المفتاح.
  // الإذن قصير الصلاحية ويُستخدم مرة واحدة.
  // ---------------------------------------------------------------
  router.post("/topups/:txId/receipt/authorize", async (req, res) => {
    const txId = req.params.txId;
    if (!uuidPattern.test(txId ?? "")) {
      return res.status(400).json({ error: "Invalid transaction id" });
    }

    try {
      const current = await database.query(
        `SELECT status, user_id
           FROM public.wallet_transactions
          WHERE id = $1`,
        [txId]
      );
      if (current.rows.length === 0) {
        return res.status(404).json({ error: "Transaction not found" });
      }
      const row = current.rows[0];
      if (row.user_id !== req.user.id) {
        return res.status(403).json({ error: "Transaction belongs to another user" });
      }
      if (row.status !== "pending") {
        return res.status(409).json({ error: "Transaction already decided" });
      }
      if (row.receipt_image_url != null) {
        return res.status(409).json({ error: "Receipt already linked" });
      }

      const objectKey = `${req.user.id}/receipts/${txId}_${crypto.randomBytes(8).toString("hex")}.jpg`;
      const auth = await uploadAuthStore.create({
        userId: req.user.id,
        txId,
        objectKey,
        bucket: storageBucket,
      });

      return res.json({
        success: true,
        data: {
          authorizationId: auth.id,
          objectKey: auth.objectKey,
          bucket: auth.bucket,
          expiresAt: auth.expiresAt,
          ttlSeconds: UPLOAD_AUTH_TTL_SECONDS,
        },
      });
    } catch (error) {
      console.error("Wallet receipt authorize failed:", error.message);
      return res.status(500).json({ error: "Failed to authorize receipt upload" });
    }
  });

  // ---------------------------------------------------------------
  // POST /topups/:txId/receipt/upload — رفع ملف الإيصال عبر Backend proxy
  // nécessite authorizationId valide. Le client ne choisit ni bucket ni object_key.
  // ---------------------------------------------------------------
  router.post(
    "/topups/:txId/receipt/upload",
    express.raw({ type: "*/*", limit: MAX_RECEIPT_BYTES }),
    async (req, res) => {
      const txId = req.params.txId;
      const authorizationId = typeof req.query.authorizationId === "string" ? req.query.authorizationId : "";

      if (!uuidPattern.test(txId ?? "")) {
        return res.status(400).json({ error: "Invalid transaction id" });
      }
      if (authorizationId.length === 0) {
        return res.status(400).json({ error: "Authorization ID is required" });
      }

      const bytes = req.body;
      if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MAX_RECEIPT_BYTES) {
        return res.status(400).json({ error: "Invalid file" });
      }

      try {
        // Vérifier la transaction avant tout
        const current = await database.query(
          `SELECT status, user_id, receipt_image_url
             FROM public.wallet_transactions
            WHERE id = $1
            FOR UPDATE`,
          [txId]
        );
        if (current.rows.length === 0) {
          return res.status(404).json({ error: "Transaction not found" });
        }
        const row = current.rows[0];
        if (row.user_id !== req.user.id) {
          return res.status(403).json({ error: "Transaction belongs to another user" });
        }
        if (row.status !== "pending") {
          return res.status(409).json({ error: "Transaction already decided" });
        }
        if (row.receipt_image_url != null) {
          return res.status(409).json({ error: "Receipt already linked" });
        }

        // Récupérer l'autorisation pour connaître objectKey et bucket (générés par le backend)
        const auth = await uploadAuthStore.get(authorizationId);
        if (!auth) {
          return res.status(403).json({ error: "Invalid, expired, or already used upload authorization" });
        }
        if (auth.used) {
          return res.status(403).json({ error: "Authorization already used" });
        }
        if (auth.txId !== txId) {
          return res.status(403).json({ error: "Authorization does not match transaction" });
        }
        if (auth.userId !== req.user.id) {
          return res.status(403).json({ error: "Authorization belongs to another user" });
        }

        // Consommation atomique (une seule fois, même en cas de requêtes simultanées)
        const consumed = await uploadAuthStore.consume(authorizationId, {
          txId,
          userId: req.user.id,
          objectKey: auth.objectKey,
        });
        if (!consumed) {
          return res.status(403).json({ error: "Invalid, expired, or already used upload authorization" });
        }

        // Uploader vers R2 avec l'object_key généré par le backend
        const { storageService } = req.app.locals || {};
        if (!storageService) {
          return res.status(503).json({ error: "Storage service not configured" });
        }

        const contentType = req.headers["content-type"]?.split(";")[0] || "image/jpeg";
        const ext = auth.objectKey.split(".").pop().toLowerCase();
        const expectedType = ext === "jpg" || ext === "jpeg" ? "image/jpeg" : `image/${ext}`;
        if (contentType !== expectedType) {
          return res.status(400).json({ error: "Content-Type does not match file extension" });
        }

        await storageService.upload({
          bucket: auth.bucket,
          key: auth.objectKey,
          body: bytes,
          contentType,
        });

        return res.json({
          success: true,
          data: { objectKey: auth.objectKey, bucket: auth.bucket },
        });
      } catch (error) {
        console.error("Wallet receipt upload failed:", error.message);
        return res.status(500).json({ error: "Failed to upload receipt" });
      }
    }
  );

  // ---------------------------------------------------------------
  // POST /topups/:txId/receipt — ربط الإيصال بالمعاملة بعد الرفع الناجح
  // ---------------------------------------------------------------
  // POST /topups/:txId/receipt — ربط الإيصال بالمعاملة بعد الرفع الناجح
  // يتطلب Authorization ID صالحاً وغير مستخدم ومنتهي الصلاحية.
  // يتم التحقق من وجود الملف في التخزين قبل الربط.
  // ---------------------------------------------------------------
  router.post("/topups/:txId/receipt", async (req, res) => {
    const txId = req.params.txId;
    const { authorizationId } = req.body ?? {};

    if (!uuidPattern.test(txId ?? "")) {
      return res.status(400).json({ error: "Invalid transaction id" });
    }
    if (typeof authorizationId !== "string" || authorizationId.length === 0) {
      return res.status(400).json({ error: "Authorization ID is required" });
    }

    try {
      // التحقق من وجود المعاملة وملكيتها وحالتها
      const current = await database.query(
        `SELECT status, user_id, receipt_image_url
           FROM public.wallet_transactions
          WHERE id = $1
          FOR UPDATE`,
        [txId]
      );
      if (current.rows.length === 0) {
        return res.status(404).json({ error: "Transaction not found" });
      }
      const row = current.rows[0];
      if (row.user_id !== req.user.id) {
        return res.status(403).json({ error: "Transaction belongs to another user" });
      }
      if (row.status !== "pending") {
        return res.status(409).json({ error: "Transaction already decided" });
      }
      if (row.receipt_image_url != null) {
        return res.status(409).json({ error: "Receipt already linked" });
      }

      // استهلاك إذن الرفع (مرة واحدة فقط، غير منتهٍ الصلاحية)
      let auth = null;
      if (typeof uploadAuthStore.get === "function") {
        const pending = await uploadAuthStore.get(authorizationId);
        if (!pending) {
          return res.status(403).json({ error: "Invalid, expired, or already used upload authorization" });
        }
        if (pending.used) {
          return res.status(403).json({ error: "Invalid, expired, or already used upload authorization" });
        }
        if (pending.txId !== txId) {
          return res.status(403).json({ error: "Authorization does not match transaction" });
        }
        if (pending.userId !== req.user.id) {
          return res.status(403).json({ error: "Authorization belongs to another user" });
        }
        auth = await uploadAuthStore.consume(authorizationId, {
          txId,
          userId: req.user.id,
          objectKey: pending.objectKey,
        });
      } else {
        auth = await uploadAuthStore.consume(authorizationId);
      }
      if (!auth) {
        return res.status(403).json({ error: "Invalid, expired, or already used upload authorization" });
      }
      if (auth.txId !== txId) {
        return res.status(403).json({ error: "Authorization does not match transaction" });
      }
      if (auth.userId !== req.user.id) {
        return res.status(403).json({ error: "Authorization belongs to another user" });
      }

      // التحقق من وجود الملف فعلياً في التخزين قبل الربط
      const { storageService } = req.app.locals || {};
      if (!storageService) {
        return res.status(503).json({ error: "Storage service not configured" });
      }
      let downloadResult;
      try {
        downloadResult = await storageService.download({
          bucket: auth.bucket,
          key: auth.objectKey,
          userId: req.user.id,
        });
      } catch (downloadError) {
        if (downloadError.statusCode === 404) {
          return res.status(409).json({ error: "Receipt file not found in storage" });
        }
        if (downloadError.statusCode === 403) {
          return res.status(403).json({ error: "Receipt file access denied" });
        }
        console.error("Receipt file verification failed:", downloadError.message);
        return res.status(503).json({ error: "Failed to verify receipt file" });
      }
      // رفض الملف الفارغ (size 0) - لا يُعتبر إيصالاً صالحاً
      if (!downloadResult || (downloadResult.size != null && downloadResult.size <= 0)) {
        return res.status(409).json({ error: "Receipt file is empty or invalid" });
      }

      const updated = await database.query(
        `UPDATE public.wallet_transactions
           SET receipt_image_url = $1
         WHERE id = $2 AND user_id = $3 AND status = 'pending'
         RETURNING id`,
        [auth.objectKey, txId, req.user.id]
      );
      if (updated.rows.length === 0) {
        return res.status(409).json({ error: "Transaction already decided or not owned" });
      }

      return res.json({ success: true, data: { id: updated.rows[0].id, receipt_image_url: auth.objectKey } });
    } catch (error) {
      console.error("Wallet receipt linking failed:", error.message);
      return res.status(500).json({ error: "Failed to link receipt" });
    }
  });

  // ---------------------------------------------------------------
  // GET /topups/:txId/receipt/sign — إنشاء رابط مؤقت لقراءة الإيصال
  // المستخدم يقرأ إيصالات معاملاته فقط؛ الأدمن يقرأ إيصالات المعاملات للمراجعة.
  // ---------------------------------------------------------------
  router.get("/topups/:txId/receipt/sign", async (req, res) => {
    const txId = req.params.txId;
    if (!uuidPattern.test(txId ?? "")) {
      return res.status(400).json({ error: "Invalid transaction id" });
    }

    try {
      const current = await database.query(
        `SELECT receipt_image_url, user_id, status
           FROM public.wallet_transactions
          WHERE id = $1`,
        [txId]
      );
      if (current.rows.length === 0) {
        return res.status(404).json({ error: "Transaction not found" });
      }
      const row = current.rows[0];
      if (!row.receipt_image_url) {
        return res.status(404).json({ error: "No receipt linked to this transaction" });
      }

      const isOwner = row.user_id === req.user.id;
      const isAdmin = req.user.is_admin === true;
      if (!isOwner && !isAdmin) {
        return res.status(403).json({ error: "Access denied to this receipt" });
      }

      const { storageService } = req.app.locals || {};
      if (!storageService) {
        return res.status(503).json({ error: "Storage service not configured" });
      }

      const expiresIn = Number.parseInt(req.query?.expires_in ?? "300", 10);
      const signed = await storageService.getSignedUrl({
        bucket: storageBucket,
        key: row.receipt_image_url,
        userId: req.user.id,
        expiresIn,
      });

      return res.json({
        success: true,
        data: {
          url: signed.url,
          expiresIn: signed.expiresIn,
        },
      });
    } catch (error) {
      if (error.statusCode === 403) {
        return res.status(403).json({ error: "Access denied to this receipt" });
      }
      if (error.statusCode === 404) {
        return res.status(404).json({ error: "Receipt not found" });
      }
      console.error("Wallet receipt sign failed:", error.message);
      return res.status(500).json({ error: "Failed to generate receipt link" });
    }
  });

  // ---------------------------------------------------------------
  // POST /decide — تأكيد أو رفض معاملة (أدمن فقط)
  // ---------------------------------------------------------------
  router.post("/decide", async (req, res) => {
    const id = req.body?.id;
    const status = req.body?.status;
    if (!uuidPattern.test(id ?? "")) {
      return res.status(400).json({ ok: false, reason: "bad_id", status: null });
    }
    if (status !== "confirmed" && status !== "rejected") {
      return res.status(400).json({ ok: false, reason: "bad_status", status: null });
    }
    try {
      const adminCheck = await database.query(
        `SELECT 1 FROM public.app_admins WHERE user_id = $1`,
        [req.user.id]
      );
      if (adminCheck.rows.length === 0) {
        return res.status(403).json({ ok: false, reason: "not_admin", status: null });
      }
      const current = await database.query(
        `SELECT status FROM public.wallet_transactions WHERE id = $1`,
        [id]
      );
      if (current.rows.length === 0) {
        return res.status(404).json({ ok: false, reason: "not_found", status: null });
      }
      const vCurrent = current.rows[0].status;
      if (vCurrent !== "pending") {
        return res.status(409).json({ ok: false, reason: "already_decided", status: vCurrent });
      }
      const vStatus = status === "confirmed" ? "confirmed" : "rejected";
      await database.query(
        `UPDATE public.wallet_transactions
            SET status = $1,
                admin_id = $2,
                confirmed_at = CASE WHEN $1 = 'confirmed' THEN now() ELSE NULL END
          WHERE id = $3 AND status = 'pending'`,
        [vStatus, req.user.id, id]
      );
      return res.json({ ok: true, reason: null, status: vStatus });
    } catch (error) {
      console.error("Wallet decision failed:", error.message);
      return res.status(500).json({ ok: false, reason: "error", status: null });
    }
  });

  return router;
}

// ------------------------------
// createUploadAuthStore (اختبارات فقط — ليس للإنتاج)
// تخزين في الذاكرة يُستخدم فقط من قبل الاختبارات القائمة.
// الإصدار الإنتاجي يستخدم createDbAuthStore من ../services/dbAuthStore.js.
// ------------------------------
function createUploadAuthStore() {
  const store = new Map();
  return {
    create({ userId, txId, objectKey, bucket, ttlSeconds = UPLOAD_AUTH_TTL_SECONDS }) {
      const id = crypto.randomBytes(16).toString("hex");
      const expiresAt = Date.now() + ttlSeconds * 1000;
      const entry = { userId, txId, objectKey, bucket, expiresAt, used: false };
      store.set(id, entry);
      return { id, objectKey, bucket, expiresAt };
    },
    consume(id) {
      const entry = store.get(id);
      if (!entry) return null;
      if (Date.now() > entry.expiresAt) {
        store.delete(id);
        return null;
      }
      if (entry.used) return null;
      entry.used = true;
      return entry;
    },
    revoke(id) {
      store.delete(id);
    },
    get(id) {
      return store.get(id);
    },
    cleanupExpired() {
      const now = Date.now();
      for (const [id, entry] of store) {
        if (now > entry.expiresAt) store.delete(id);
      }
    },
    get size() {
      return store.size;
    },
  };
}

export default createWalletRouter;

export { createUploadAuthStore, UPLOAD_AUTH_TTL_SECONDS };
