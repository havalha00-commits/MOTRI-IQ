import assert from "node:assert/strict";
import test from "node:test";
import express from "express";
import { createStorageRouter } from "../routes/storage.js";
import { createObjectStorageService } from "../services/objectStorage.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function makeMockStorage(overrides = {}) {
  const calls = [];
  const checkOwnership = overrides.checkOwnership || (async () => true);
  return {
    calls,
    upload: overrides.upload || (async ({ bucket, key }) => {
      calls.push({ op: "upload", bucket, key });
      return { bucket, key, size: 100 };
    }),
    download: overrides.download || (async ({ bucket, key, userId }) => {
      if (userId) {
        const owned = await checkOwnership(userId, key, bucket);
        if (!owned) {
          const e = new Error("Forbidden");
          e.statusCode = 403;
          throw e;
        }
      }
      calls.push({ op: "download", bucket, key });
      return {
        bucket, key,
        body: { pipe: () => {} },
        contentType: "image/jpeg",
        size: 100,
        lastModified: new Date(),
      };
    }),
    deleteObject: overrides.deleteObject || (async ({ bucket, key, userId }) => {
      if (userId) {
        const owned = await checkOwnership(userId, key, bucket);
        if (!owned) {
          const e = new Error("Forbidden");
          e.statusCode = 403;
          throw e;
        }
      }
      calls.push({ op: "delete", bucket, key });
      return { deleted: true, bucket, key };
    }),
    getSignedUrl: overrides.getSignedUrl || (async ({ bucket, key, expiresIn, userId }) => {
      if (userId) {
        const owned = await checkOwnership(userId, key, bucket);
        if (!owned) {
          const e = new Error("Forbidden");
          e.statusCode = 403;
          throw e;
        }
      }
      calls.push({ op: "sign", bucket, key, expiresIn });
      return { url: `https://r2.example.test/signed/${key}?e=${expiresIn}`, expiresIn };
    }),
    checkOwnership,
  };
}

function mockReq(method, url, headers = {}, body = null) {
  const qIdx = url.indexOf("?");
  const path = qIdx !== -1 ? url.slice(0, qIdx) : url;
  const query = {};
  if (qIdx !== -1) {
    for (const pair of url.slice(qIdx + 1).split("&")) {
      const [k, v] = pair.split("=");
      if (k) query[k] = v ? decodeURIComponent(v) : "";
    }
  }
  return {
    method,
    url: path,
    headers: { ...headers },
    query,
    body: body != null ? body : undefined,
  };
}

function mockRes() {
  const res = {
    statusCode: 200,
    body: null,
    _headers: {},
    status(code) { this.statusCode = code; return this; },
    json(data) { this.body = data; this._headers["content-type"] = "application/json"; return this; },
    setHeader(k, v) { this._headers[k] = v; return this; },
    end() {},
    pipe() {},
  };
  return res;
}

function findHandler(router, method, path) {
  for (const layer of router.stack) {
    if (!layer.route) continue;
    if (layer.route.path !== path) continue;
    if (!layer.route.methods[method.toLowerCase()]) continue;
    return layer.route.stack.map((l) => l.handle);
  }
  return null;
}

async function runHandler(router, method, url, headers = {}, body = null, authenticate) {
  const path = url.split("?")[0];
  const relativePath = path.startsWith("/api/storage") ? path.slice("/api/storage".length) : path;
  const handlers = findHandler(router, method, relativePath);
  if (!handlers) {
    throw new Error(`No handler for ${method} ${relativePath}`);
  }

  const req = mockReq(method, url, headers, body);
  const res = mockRes();

  // Run authenticate middleware first
  if (authenticate) {
    authenticate(req, res, () => {});
  }

  // Run only the final route handler (last entry in layer.route.stack),
  // skipping middleware such as express.raw().
  const finalHandler = handlers[handlers.length - 1];

  if (finalHandler) {
    try {
      const result = finalHandler(req, res);
      if (result && typeof result.then === "function") {
        await result;
      }
    } catch (e) {
      // Handler already set res.statusCode/body on error
    }
  }
  return res;
}

function validJpegBytes() {
  return Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
}

test("storage route: PUT upload success", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=market_items&path=" + userId + "/img.jpg", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 201);
  assert.equal(storage.calls.length, 1);
  assert.equal(storage.calls[0].op, "upload");
});

test("storage route: PUT upload unauthenticated", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = req.headers.authorization ? { id: userId } : undefined;
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    "content-type": "image/jpeg",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = req.headers.authorization ? { id: userId } : undefined;
    next();
  });
  assert.equal(res.statusCode, 401);
});

test("storage route: PUT upload path traversal rejected", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=cars&path=../etc/passwd", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: PUT upload invalid extension rejected", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=cars&path=" + userId + "/img.exe", {
    "content-type": "application/octet-stream",
    authorization: "Bearer token",
  }, Buffer.from("not an image"), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: PUT upload magic bytes mismatch rejected", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, Buffer.from("not a jpeg file at all"), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: GET download success", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 200);
  assert.equal(storage.calls.length, 1);
  assert.equal(storage.calls[0].op, "download");
});

test("storage route: GET download path traversal rejected", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/object?bucket=cars&path=../secret", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: DELETE success", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "DELETE", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 200);
  assert.equal(storage.calls.length, 1);
  assert.equal(storage.calls[0].op, "delete");
});

test("storage route: DELETE path traversal rejected", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "DELETE", "/api/storage/object?bucket=cars&path=../../etc/passwd", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: GET sign success with default expiry", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/sign?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 200);
  assert.equal(storage.calls.length, 1);
  assert.equal(storage.calls[0].op, "sign");
  assert.equal(storage.calls[0].expiresIn, 300);
});

test("storage route: GET sign respects max expiry", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/sign?bucket=cars&path=" + userId + "/img.jpg&expires_in=7200", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: GET sign rejects non-numeric expiry", async () => {
  const storage = makeMockStorage();
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/sign?bucket=cars&path=" + userId + "/img.jpg&expires_in=abc", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 400);
  assert.equal(storage.calls.length, 0);
});

test("storage route: ownership denied on PUT", async () => {
  const storage = makeMockStorage({ checkOwnership: async () => false });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=market_items&path=" + userId + "/img.jpg", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 403);
  assert.equal(storage.calls.length, 0);
});

test("storage route: private wallet_receipts download denied without ownership", async () => {
  const storage = makeMockStorage({ checkOwnership: async () => false });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/object?bucket=wallet_receipts&path=" + userId + "/receipts/r.jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 403);
  assert.equal(storage.calls.length, 0);
});

test("storage route: service throws network error => 503", async () => {
  const storage = makeMockStorage({
    upload: async () => { throw new Error("ECONNREFUSED"); },
  });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=market_items&path=" + userId + "/img.jpg", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "Object storage is unavailable");
});

test("storage route: service throws 403 => 403", async () => {
  const storage = makeMockStorage({
    download: async () => { const e = new Error("Forbidden"); e.statusCode = 403; throw e; },
  });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 403);
});

test("storage route: service throws 404 => 404", async () => {
  const storage = makeMockStorage({
    download: async () => { const e = new Error("Not Found"); e.statusCode = 404; throw e; },
  });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "GET", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    authorization: "Bearer token",
  }, null, (req, _res, next) => {
    req.user = { id: userId };
    next();
  });
  assert.equal(res.statusCode, 404);
});

test("storage route: missing config => service not configured error", async () => {
  const storage = createObjectStorageService({
    ownershipChecker: async () => true,
  });
  const router = createStorageRouter({
    authenticate: (req, _res, next) => {
      req.user = { id: userId };
      next();
    },
    storage,
  });
  const res = await runHandler(router, "PUT", "/api/storage/object?bucket=cars&path=" + userId + "/" + userId + "/" + userId + ".jpg", {
    "content-type": "image/jpeg",
    authorization: "Bearer token",
  }, validJpegBytes(), (req, _res, next) => {
    req.user = { id: userId };
    next();
  }, async () => true);
  assert.equal(res.statusCode, 503);
});

