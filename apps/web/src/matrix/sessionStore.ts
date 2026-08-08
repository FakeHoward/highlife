/** Persist Matrix session in IndexedDB instead of plain localStorage. */

const DB_NAME = "highlife.session";
const STORE = "sessions";
const SESSION_ID = "current";
const LEGACY_LOCAL_STORAGE_KEY = "highlife.matrix.session.v1";

export interface StoredSession {
  baseUrl: string;
  userId: string;
  accessToken: string;
  deviceId: string;
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB open failed"));
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
  });
}

function idbRequest<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed"));
    request.onsuccess = () => resolve(request.result);
  });
}

export async function saveSession(session: StoredSession): Promise<void> {
  const db = await openDb();
  try {
    const tx = db.transaction(STORE, "readwrite");
    await idbRequest(tx.objectStore(STORE).put(session, SESSION_ID));
  } finally {
    db.close();
  }
  try {
    localStorage.removeItem(LEGACY_LOCAL_STORAGE_KEY);
  } catch {
    /* ignore */
  }
}

export async function loadSession(): Promise<StoredSession | null> {
  try {
    const db = await openDb();
    try {
      const tx = db.transaction(STORE, "readonly");
      const value = await idbRequest(
        tx.objectStore(STORE).get(SESSION_ID) as IDBRequest<StoredSession | undefined>,
      );
      if (value?.baseUrl && value.userId && value.accessToken && value.deviceId) {
        return value;
      }
    } finally {
      db.close();
    }
  } catch {
    /* fall through to legacy */
  }

  try {
    const legacy = JSON.parse(
      localStorage.getItem(LEGACY_LOCAL_STORAGE_KEY) ?? "null",
    ) as Partial<StoredSession> | null;
    if (legacy?.baseUrl && legacy.userId && legacy.accessToken && legacy.deviceId) {
      const session = legacy as StoredSession;
      await saveSession(session);
      return session;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export async function clearSession(): Promise<void> {
  try {
    const db = await openDb();
    try {
      const tx = db.transaction(STORE, "readwrite");
      await idbRequest(tx.objectStore(STORE).delete(SESSION_ID));
    } finally {
      db.close();
    }
  } catch {
    /* ignore */
  }
  try {
    localStorage.removeItem(LEGACY_LOCAL_STORAGE_KEY);
  } catch {
    /* ignore */
  }
}

/** Delete Rust crypto IndexedDB databases for this device. */
export async function clearCryptoDatabases(userId: string, deviceId: string): Promise<void> {
  const prefix = `highlife-${userId}-${deviceId}`;
  const databases =
    typeof indexedDB.databases === "function" ? await indexedDB.databases() : [];
  await Promise.all(
    databases
      .map((entry) => entry.name)
      .filter((name): name is string => Boolean(name && name.includes(prefix)))
      .map(
        (name) =>
          new Promise<void>((resolve) => {
            const request = indexedDB.deleteDatabase(name);
            request.onsuccess = () => resolve();
            request.onerror = () => resolve();
            request.onblocked = () => resolve();
          }),
      ),
  );
}
