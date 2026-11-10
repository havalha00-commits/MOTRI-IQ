import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { loadExplicitEnvFile, applyIsolatedEnv, validateIsolatedLocalTestEnv } from "../config/localTestRuntimeBootstrap.js";

function failClosed(code) {
  console.error(`LOCAL_TEST_RUNTIME_REFUSED: ${code || "LOCAL_TEST_RUNTIME_INVALID"}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { envFile: null, prepared: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--env-file") args.envFile = argv[++i] || "";
    else if (a.startsWith("--env-file=")) args.envFile = a.slice("--env-file=".length);
    else if (a === "--prepared-env") args.prepared = true;
  }
  return args;
}

async function main() {
  try {
    const args = parseArgs(process.argv);
    if (args.prepared) {
      applyIsolatedEnv({}, process.env);
    } else {
      const source = loadExplicitEnvFile(args.envFile);
      applyIsolatedEnv(source, process.env);
    }
    // A-D: validate explicit isolated env before importing modules that create pool/storage.
    await validateIsolatedLocalTestEnv(process.env);
    // Keep cleanup disabled by default for isolated runtime; do not schedule before verification.
    if (process.env.RESERVATION_CLEANUP_INTERVAL_MS == null || process.env.RESERVATION_CLEANUP_INTERVAL_MS === "") {
      process.env.RESERVATION_CLEANUP_INTERVAL_MS = "0";
    }

    // E: create DB pool and storage service only after A-D validation.
    const { createPool } = await import("../config/database.js");
    const { createObjectStorageService } = await import("../services/objectStorage.js");
    const pool = createPool(process.env);
    const storageService = createObjectStorageService({ env: process.env });

    // F-H delegated to guarded server startup: verifies actual DB identity before listen;
    // schedules permitted post-verification callbacks only after success.
    const { createApp, startIsolatedLocalTestServer } = await import("../server.js");
    const app = await createApp({ pool, storageService, env: process.env });
    await startIsolatedLocalTestServer({ app, pool, env: process.env });
  } catch (err) {
    failClosed(err?.code || "LOCAL_TEST_RUNTIME_INVALID");
  }
}

main();
