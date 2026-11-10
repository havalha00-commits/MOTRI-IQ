import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve("..");
function read(rel) { return fs.readFileSync(path.resolve(root, rel), "utf8"); }
function must(rel, re, msg) { const s=read(rel); assert.match(s,re,msg||`${rel} missing ${re}`); }
function mustNot(rel, re, msg) { const s=read(rel); assert.doesNotMatch(s,re,msg||`${rel} must not match ${re}`); }

test("G10.54 M1E market UI isolation - static: market upload/edit flow avoids guarded Supabase getter", () => {
  // Market upload uses backend-only in local test mode.
  must("lib/market_images.dart", /backendApi\s*\n?\s*\.putBytes\([\s\S]*?backendOnly:\s*kMotriLocalTest/s, "market_images upload must pass backendOnly in local test mode");
  must("lib/market_images.dart", /'market\/uploads'/, "market upload must target market/uploads");
  mustNot("lib/market_images.dart", /\bsupabase\.auth\b|\bSupabase\.instance\b/, "market_images.dart must not access Supabase directly");

  // Generic ad editor uses backendApi/backendAuthSession only for market/jobs flow.
  mustNot("lib/ui/generic_ad_editor_dialog.dart", /\bsupabase\.auth\b|\bSupabase\.instance\b/, "generic_ad_editor_dialog.dart must not access Supabase directly");

  // BackendApi supports global backendOnly isolation and never falls back when effectiveBackendOnly.
  must("lib/backend_api.dart", /final bool _backendOnly/, "BackendApi must support backendOnly isolation flag");
  must("lib/backend_api.dart", /effectiveBackendOnly = backendOnly \|\| _backendOnly/, "BackendApi must honor global backendOnly");

  // main.dart guards startup and global backendApi in local test mode.
  must("lib/main.dart", /kMotriLocalTest[\s\S]*?if \(!kMotriLocalTest\)\s*\{\s*await Supabase\.initialize/s, "main.dart must skip Supabase.initialize in local test mode");
  must("lib/main.dart", /backendOnly:\s*kMotriLocalTest/, "global backendApi must be backendOnly in local test mode");
  must("lib/main.dart", /Future<void> addGenericAd\(\) async \{[\s\S]*?kMotriLocalTest\s*\?\s*backendAuthSession\.user != null/s, "addGenericAd must not touch guarded supabase getter in local test mode");

  // Middleware blocks Supabase fallback in local test mode.
  must("backend/middleware/current_user.js", /disableSupabaseFallback[\s\S]*?MOTRI_LOCAL_TEST|DISABLE_SUPABASE_AUTH_FALLBACK/, "current_user must support local-test Supabase fallback disable");
  must("backend/middleware/current_user.js", /if \(disableSupabaseFallback\)\s*\{[\s\S]*?Invalid or expired session/, "current_user must fail closed without Supabase fallback when isolated");
});
