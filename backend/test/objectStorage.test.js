import assert from "node:assert/strict";
import test from "node:test";
import {
  createObjectStorageService,
  validateObjectKey,
  validateSignedUrlSeconds,
  MAX_SIGNED_URL_SECONDS,
} from "../services/objectStorage.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const bucket = "motri-iq-test";
const key = `${userId}/receipts/receipt-001.jpg`;

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(data) {
      res.body = data;
      return res;
    },
    setHeader() {},
    pipe() {},
  };
  return res;
}

function mockS3Client(sendResult) {
  const sent = [];
  return {
    send(command) {
      sent.push(command);
      if (sendResult instanceof Error) throw sendResult;
      return sendResult;
    },
    get sent() {
      return sent;
    },
    reset() {
      sent.length = 0;
    },
  };
}

function mockCommand(input) {
  this.input = input;
}

function mockPresign(s3, command, { expiresIn }) {
  return `https://r2.example.test/signed/${command.input.Key}?expires=${expiresIn}`;
}

test("objectStorage: upload success", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    PutObjectCommand: mockCommand,
    bucket,
  });
  const result = await storage.upload({
    bucket,
    key,
    body: Buffer.from("fake-bytes"),
    contentType: "image/jpeg",
  });
  assert.equal(result.bucket, bucket);
  assert.equal(result.key, key);
  assert.equal(result.size, 10);
  assert.equal(s3.sent.length, 1);
});

test("objectStorage: B2 provider maps logical car bucket under isolated prefix", async () => {
  const s3 = mockS3Client({
    Body: Buffer.from("image-bytes"),
    ContentType: "image/png",
    ContentLength: 11,
  });
  const key = `${userId}/${userId}/${userId}.png`;
  const storage = createObjectStorageService({
    s3Client: s3,
    PutObjectCommand: mockCommand,
    GetObjectCommand: mockCommand,
    DeleteObjectCommand: mockCommand,
    HeadObjectCommand: mockCommand,
    ownershipChecker: async () => true,
    env: {
      STORAGE_PROVIDER: "b2",
      STORAGE_PREFIX: "motri-iq-test",
      B2_BUCKET: "motri-iq-isolated-test-2026",
    },
  });

  await storage.upload({ bucket: "cars", key, body: Buffer.from("image-bytes"), contentType: "image/png" });
  await storage.download({ bucket: "cars", key });
  await storage.downloadAuthorizedCarImage({ bucket: "cars", key });
  await storage.deleteObject({ bucket: "cars", key });

  assert.deepEqual(
    s3.sent.map((command) => [command.input.Bucket, command.input.Key]),
    Array.from({ length: 4 }, () => ["motri-iq-isolated-test-2026", `motri-iq-test/cars/${key}`])
  );
});

test("objectStorage: download success with ownership", async () => {
  const s3 = mockS3Client({
    Body: Buffer.from("image-bytes"),
    ContentType: "image/jpeg",
    ContentLength: 12,
    LastModified: new Date(),
  });
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    bucket,
    ownershipChecker: async () => true,
  });
  const result = await storage.download({ bucket, key, userId });
  assert.equal(result.contentType, "image/jpeg");
  assert.equal(result.size, 12);
  assert.equal(result.body.toString(), "image-bytes");
});

test("objectStorage: download denied when ownership fails", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    bucket,
    ownershipChecker: async () => false,
  });
  await assert.rejects(
    storage.download({ bucket, key, userId }),
    (err) => err.statusCode === 403 && err.message === "Forbidden"
  );
});

test("objectStorage: delete success", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    DeleteObjectCommand: mockCommand,
    bucket,
    ownershipChecker: async () => true,
  });
  const result = await storage.deleteObject({ bucket, key, userId });
  assert.equal(result.deleted, true);
  assert.equal(result.key, key);
});

test("objectStorage: delete denied when ownership fails", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    DeleteObjectCommand: mockCommand,
    bucket,
    ownershipChecker: async () => false,
  });
  await assert.rejects(
    storage.deleteObject({ bucket, key, userId }),
    (err) => err.statusCode === 403
  );
});

test("objectStorage: signed URL generated", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    getSignedUrl: mockPresign,
    bucket,
    ownershipChecker: async () => true,
  });
  const result = await storage.getSignedUrl({ bucket, key, userId, expiresIn: 60 });
  assert.equal(typeof result.url, "string");
  assert.equal(result.expiresIn, 60);
  assert.ok(result.url.startsWith("https://r2.example.test/signed/"));
});

test("objectStorage: signed URL denied when ownership fails", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    getSignedUrl: mockPresign,
    bucket,
    ownershipChecker: async () => false,
  });
  await assert.rejects(
    storage.getSignedUrl({ bucket, key, userId }),
    (err) => err.statusCode === 403
  );
});

test("objectStorage: public URL denied for private bucket", async () => {
  const storage = createObjectStorageService({
    s3Client: mockS3Client({}),
    bucket: "wallet_receipts",
    privateBuckets: new Set(["wallet_receipts"]),
  });
  await assert.rejects(
    storage.getPublicUrl({ bucket: "wallet_receipts", key }),
    (err) => err.statusCode === 403 && err.message.includes("Private bucket")
  );
});

test("objectStorage: missing config throws without printing secrets", async () => {
  const storage = createObjectStorageService({});
  await assert.rejects(
    storage.upload({ bucket, key, body: Buffer.from("x"), contentType: "image/jpeg" }),
    (err) => err.message.includes("not configured")
  );
});

test("objectStorage: default ownershipChecker denies all (fail closed)", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    bucket,
  });
  const owned = await storage.checkOwnership(userId, key, bucket);
  assert.equal(owned, false);
});

test("objectStorage: validateObjectKey rejects absolute path", () => {
  assert.throws(() => validateObjectKey("/etc/passwd"), (err) =>
    err.message.includes("absolute paths")
  );
});

test("objectStorage: validateObjectKey rejects backslash", () => {
  assert.throws(() => validateObjectKey("folder\\file.jpg"), (err) =>
    err.message.includes("backslashes")
  );
});

test("objectStorage: validateObjectKey rejects dot segment", () => {
  assert.throws(() => validateObjectKey("a/./b.jpg"), (err) =>
    err.message.includes("dot segments")
  );
});

test("objectStorage: validateObjectKey rejects double dot", () => {
  assert.throws(() => validateObjectKey("a/../b.jpg"), (err) =>
    err.message.includes("dot segments")
  );
});

test("objectStorage: validateObjectKey rejects empty segment", () => {
  assert.throws(() => validateObjectKey("a//b.jpg"), (err) =>
    err.message.includes("empty segment")
  );
});

test("objectStorage: validateObjectKey rejects too long", () => {
  assert.throws(() => validateObjectKey("a".repeat(2000)), (err) =>
    err.message.includes("key too long")
  );
});

test("objectStorage: validateObjectKey rejects too many segments", () => {
  assert.throws(
    () => validateObjectKey("a/b/c/d/e/f/g/h/i/j/k.jpg"),
    (err) => err.message.includes("too many segments")
  );
});

test("objectStorage: validateObjectKey accepts valid key", () => {
  assert.equal(validateObjectKey("user123/receipts/file.jpg"), true);
});

test("objectStorage: validateSignedUrlSeconds rejects non-numeric", () => {
  assert.throws(() => validateSignedUrlSeconds("abc"), (err) =>
    err.message.includes("integer")
  );
});

test("objectStorage: validateSignedUrlSeconds rejects negative", () => {
  assert.throws(() => validateSignedUrlSeconds(-10), (err) =>
    err.message.includes("positive")
  );
});

test("objectStorage: validateSignedUrlSeconds rejects zero", () => {
  assert.throws(() => validateSignedUrlSeconds(0), (err) =>
    err.message.includes("positive")
  );
});

test("objectStorage: validateSignedUrlSeconds rejects over max", () => {
  assert.throws(() => validateSignedUrlSeconds(MAX_SIGNED_URL_SECONDS + 1), (err) =>
    err.message.includes("maximum")
  );
});

test("objectStorage: validateSignedUrlSeconds accepts default", () => {
  assert.equal(validateSignedUrlSeconds(300), 300);
});

test("objectStorage: upload rejects invalid key before S3", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    PutObjectCommand: mockCommand,
    bucket,
  });
  await assert.rejects(
    storage.upload({
      bucket,
      key: "../etc/passwd",
      body: Buffer.from("x"),
      contentType: "image/jpeg",
    }),
    (err) => err.message.includes("dot segments")
  );
  assert.equal(s3.sent.length, 0);
});

test("objectStorage: getSignedUrl rejects invalid key", async () => {
  const s3 = mockS3Client({});
  const storage = createObjectStorageService({
    s3Client: s3,
    GetObjectCommand: mockCommand,
    getSignedUrl: mockPresign,
    bucket,
    ownershipChecker: async () => true,
  });
  await assert.rejects(
    storage.getSignedUrl({ bucket, key: "a/../b.jpg", userId }),
    (err) => err.message.includes("dot segments")
  );
});
