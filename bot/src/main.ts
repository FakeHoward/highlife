import "dotenv/config";
import { randomBytes } from "node:crypto";
import http from "node:http";

import {
  Bot,
  DeviceMismatchError,
  Dispatcher,
  RateLimitedError,
  autoMarkRead,
  diagnoseSession,
  logging,
  migrateStorage,
  rateLimitBackoff,
  relocateSession,
  throttle,
  typingIndicator,
  userFacingErrors,
} from "aiomatrix";
import {
  RedisStorage,
  createRedisSharedTokenStores,
  type RedisLike,
} from "aiomatrix/redis";
import { createClient } from "redis";

import { wrapMiniAppHandler } from "./formspace/http.js";
import { createFormSpaceRouter, tickDeadlines } from "./formspace/router.js";
import { FormSpaceStore } from "./formspace/store.js";

const dataDir = "./data";
const homeserver = process.env.MATRIX_HOMESERVER ?? "http://localhost:6167";
const userId = process.env.MATRIX_USER_ID ?? "@bot:localhost";
const password = process.env.MATRIX_PASSWORD ?? "bot-pass";
const miniAppUrl = process.env.MATRIX_MINIAPP_URL ?? "http://localhost:4173/";
const miniAppPort = Number(process.env.MINIAPP_HTTP_PORT ?? "8090");
const redisUrl = process.env.REDIS_URL?.trim() || "";
const rotateEveryMessageMaxPeers = Number(
  process.env.MATRIX_ROTATE_EVERY_MESSAGE_MAX_PEERS ?? "32",
);
const envFlag = (name: string, fallback: boolean): boolean =>
  (process.env[name] ?? String(fallback)).toLowerCase() === "true";

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** node-redis v4+ → {@link RedisLike} (`del` takes a rest list in the adapter). */
function asRedisLike(client: ReturnType<typeof createClient>): RedisLike {
  return {
    get: (key) => client.get(key),
    set: async (key, value, options) => {
      const result = await client.set(key, value, options);
      return result as "OK" | null;
    },
    del: (...keys) => client.del(keys),
  };
}

/** Prefer typed DeviceMismatchError / diagnoseSession — not message scraping. */
function needsSessionRelocation(error: unknown): boolean {
  if (error instanceof DeviceMismatchError) return true;
  return diagnoseSession(dataDir).suggestedAction === "wipe_crypto_and_relogin";
}

async function recoverSession(error: unknown): Promise<void> {
  const diagnosis = diagnoseSession(dataDir);
  console.error("Bot session recovery", diagnosis, error);
  const mismatch = error instanceof DeviceMismatchError ? error : null;
  if (mismatch) {
    console.error(
      "DeviceMismatch recovery",
      mismatch.recovery.suggested,
      mismatch.recovery.steps,
    );
  }
  await relocateSession({
    storagePath: dataDir,
    homeserverUrl: homeserver,
    user: userId,
    password,
    deviceId: mismatch?.recovery.keepDeviceId ?? undefined,
    wipeCrypto: true,
    clearExistingSession: true,
    allowInsecure: envFlag("ALLOW_INSECURE_HOMESERVER", true),
    pruneOtherDevices: true,
  });
}

async function connectRedis(): Promise<{
  redis?: RedisLike;
  quit?: () => Promise<void>;
}> {
  if (!redisUrl) {
    console.warn(
      "REDIS_URL unset — signed callback/query tokens use durable file stores under ./data (single replica)",
    );
    return {};
  }
  const client = createClient({ url: redisUrl });
  client.on("error", (err) => console.error("Redis error", err));
  await client.connect();
  console.log("Redis connected for multi-instance MiniApp/callback token stores");
  return {
    redis: asRedisLike(client),
    quit: async () => {
      await client.quit();
    },
  };
}

async function runBot(): Promise<void> {
  const migrated = migrateStorage(dataDir);
  if (migrated.actions.length > 0 || migrated.warnings.length > 0) {
    console.log("aiomatrix migrateStorage", migrated);
  }

  const redisConn = await connectRedis();
  const shared = redisConn.redis
    ? createRedisSharedTokenStores(redisConn.redis, { prefix: "fs:" })
    : null;

  const bot = await Bot.create({
    homeserverUrl: homeserver,
    userId,
    password,
    allowInsecureHomeserver: envFlag("ALLOW_INSECURE_HOMESERVER", true),
    storagePath: dataDir,
    autoReloginOnAuthFailure: true,
    // HighLife web + Flutter render structured aiomatrix fields natively.
    clientProfile: "aware",
    advertiseCapabilities: true,
    // 0.8: durable send retry for transient HS failures.
    outbox: true,
    crypto: envFlag("MATRIX_CRYPTO", false),
    cryptoStorePassphrase: process.env.MATRIX_CRYPTO_STORE_PASSPHRASE || undefined,
    keyBackup: envFlag("MATRIX_KEY_BACKUP", false),
    keyBackupRecoveryKey: process.env.MATRIX_KEY_BACKUP_RECOVERY_KEY || undefined,
    bootstrapCrossSigning: envFlag("MATRIX_BOOTSTRAP_CROSS_SIGNING", false),
    handlerTimeoutMs: Number(process.env.MATRIX_HANDLER_TIMEOUT_MS ?? "0") || 0,
    encryption: {
      onlyAllowTrustedDevices: envFlag("MATRIX_ONLY_TRUSTED_DEVICES", false),
      rotateEveryMessage: envFlag("MATRIX_ROTATE_EVERY_MESSAGE", true),
      rotateEveryMessageMaxPeers: Number.isFinite(rotateEveryMessageMaxPeers)
        ? rotateEveryMessageMaxPeers
        : 32,
      reshareOnDeviceChange: true,
    },
    ...(shared
      ? {
          callbackAsyncUsedStore: shared.callbackAsyncUsedStore,
          callbackAliasStore: shared.callbackAliasStore,
          callbackBindStore: shared.callbackBindStore,
        }
      : {}),
    miniApp: {
      defaultUrl: miniAppUrl,
      allowedOrigins: [new URL(miniAppUrl).origin],
      secret: process.env.MATRIX_MINIAPP_SECRET || undefined,
      // Aware profile already leans MiniApps; keep launch keyboard off so the
      // card is the reopen affordance (AWARE default still enables it).
      includeLaunchKeyboard: false,
      ...(shared
        ? {
            asyncQueryUsedStore: shared.miniAppAsyncQueryUsedStore,
            asyncNonceStore: shared.asyncNonceStore,
          }
        : {}),
    },
    onSyncStale: (health) => {
      console.warn("FormSpace sync stale", health);
    },
    onRateLimited: (error) => {
      console.warn("FormSpace rate-limited", error);
    },
    onFatal: (err) => {
      console.error("FormSpace bot fatal", err, diagnoseSession(dataDir));
    },
  });

  const anonymitySalt = process.env.FORMSPACE_ANONYMITY_SALT?.trim();
  if (!anonymitySalt) {
    console.warn(
      "FORMSPACE_ANONYMITY_SALT unset; using ephemeral salt — anonymous identity hashes will not survive restart",
    );
  }
  const store = new FormSpaceStore(
    dataDir,
    anonymitySalt || randomBytes(32).toString("hex"),
  );
  const router = createFormSpaceRouter({ bot, store, miniAppUrl });

  const dispatcher = new Dispatcher({
    fsmStrategy: "user_in_room",
    fsmNamespace: "formspace",
    ...(redisConn.redis
      ? { storage: new RedisStorage(redisConn.redis, { prefix: "fs:fsm:" }) }
      : {}),
  });
  dispatcher.use(logging());
  dispatcher.use(autoMarkRead());
  dispatcher.use(rateLimitBackoff());
  dispatcher.use(throttle({ limit: 20, windowMs: 10_000 }));
  dispatcher.use(typingIndicator());
  dispatcher.use(userFacingErrors());
  dispatcher.include(router);
  dispatcher.errors(async (error, ctx) => {
    console.error("FormSpace handler failed", error);
    if (ctx?.updateType === "message" && !ctx.signal.aborted) {
      const detail = error instanceof Error ? error.message : "unknown error";
      await ctx.reply(`FormSpace could not complete that action: ${detail}`);
    }
    return true;
  });
  dispatcher.fallback(async (ctx) => {
    if (ctx.updateType === "message" && !ctx.signal.aborted) {
      await ctx.reply("No FormSpace route matched. Try /help or /form help.");
    }
  });

  const resolveRoomAuth = (uid: string, roomId: string) => ({
    membership: bot.client.rooms.membershipOf(roomId, uid) ?? null,
    powerLevel: bot.client.rooms.powerLevelOf(roomId, uid),
  });

  const miniServer = bot.createMiniAppServer({
    allowedOrigins: [new URL(miniAppUrl).origin, "https://testhighlife.strangled.net"],
    basePath: "/",
    includeRoomAuthInSession: true,
    resolveRoomAuth,
    ...(shared ? { asyncNonceStore: shared.asyncNonceStore } : {}),
  });
  const httpServer = http.createServer(
    wrapMiniAppHandler(miniServer, store, resolveRoomAuth),
  );
  await new Promise<void>((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(miniAppPort, "0.0.0.0", () => resolve());
  });
  console.log(`FormSpace MiniApp API on :${miniAppPort}`);

  bot.scheduler.every(30_000, async () => {
    try {
      await tickDeadlines(bot, store);
    } catch (error) {
      console.error("FormSpace scheduler tick failed", error);
    }
  }, { name: "formspace-deadlines" });

  console.log(`FormSpace as ${bot.selfId} → ${homeserver}`, diagnoseSession(dataDir));
  try {
    await bot.run(dispatcher);
  } finally {
    httpServer.close();
    await redisConn.quit?.();
  }
}

async function main(): Promise<void> {
  for (;;) {
    try {
      await runBot();
      return;
    } catch (error) {
      if (needsSessionRelocation(error)) {
        console.error("Relocating bot session via aiomatrix relocateSession");
        await recoverSession(error);
        await sleep(3_000);
        continue;
      }
      if (error instanceof RateLimitedError) {
        const waitMs = Math.min(Math.max(error.retryAfterMs + 2_000, 5_000), 600_000);
        console.error(`Homeserver rate-limited ${error.method} ${error.path}; sleeping ${waitMs}ms`);
        await sleep(waitMs);
        continue;
      }
      throw error;
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
