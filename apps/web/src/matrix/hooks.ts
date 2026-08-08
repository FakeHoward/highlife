import { useEffect, useState, useSyncExternalStore } from "react";
import { isAuthCallbackUrl, maybeCompleteAuthCallback } from "./oidc";
import {
  getSnapshot,
  getHistoryState,
  listRooms,
  publishAuthError,
  restoreSession,
  roomTimeline,
  subscribe,
} from "./service";

export function useMatrix() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export function useRooms(query = "") {
  useMatrix();
  return listRooms(query);
}

export function useTimeline(roomId: string | null) {
  useMatrix();
  return roomId ? roomTimeline(roomId) : [];
}

export function useHistoryState(roomId: string | null) {
  useMatrix();
  return roomId
    ? getHistoryState(roomId)
    : { loading: false, exhausted: true, error: null };
}

export function useBootstrap(): boolean {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    let alive = true;
    void (async () => {
      try {
        if (isAuthCallbackUrl()) {
          const result = await maybeCompleteAuthCallback();
          if (result.error) publishAuthError(result.error);
          if (result.handled) return;
        }
        await restoreSession();
      } finally {
        if (alive) setReady(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);
  return ready;
}
