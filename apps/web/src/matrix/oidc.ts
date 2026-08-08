/**
 * OAuth2 / SSO login for HighLife web.
 *
 * Uses matrix-js-sdk OAuth2 helpers when homeserver exposes auth metadata.
 * Falls back to classic m.login.sso redirect (`/login/sso/redirect`).
 *
 * Legacy `matrix-js-sdk/lib/oidc` helpers (generateOidcAuthorizationUrl, etc.)
 * were removed in SDK v42 in favor of `lib/oauth`; this module follows that API.
 */

import { createClient } from "matrix-js-sdk";
import { OAuth2, type ValidatedAuthMetadata } from "matrix-js-sdk/lib/oauth";
import {
  loginWithAccessToken,
  loginWithSsoToken,
  resolveHomeserver,
} from "./service";

const OAUTH_STORAGE_KEY = "highlife.oauth.v1";
const SSO_STORAGE_KEY = "highlife.sso.v1";
const CLIENT_NAME = "HighLife";

type StoredOauth = {
  kind: "oauth2";
  homeserver: string;
  state: string;
  clientId: string;
  redirectUri: string;
  codeVerifier: string;
  deviceId: string;
  metadata: ValidatedAuthMetadata;
};

type StoredSso = {
  kind: "sso";
  homeserver: string;
};

function redirectUri(): string {
  const url = new URL(window.location.href);
  url.search = "";
  url.hash = "";
  const base = url.toString().replace(/\/$/, "");
  return base || `${window.location.origin}/`;
}

function clearAuthQuery(): void {
  const url = new URL(window.location.href);
  ["code", "state", "loginToken", "error", "error_description"].forEach((key) => {
    url.searchParams.delete(key);
  });
  if (url.hash.includes("code=") || url.hash.includes("loginToken=")) {
    url.hash = "";
  }
  window.history.replaceState({}, document.title, `${url.pathname}${url.search}${url.hash}`);
}

async function beginOauth2(homeserver: string): Promise<void> {
  const guest = createClient({ baseUrl: homeserver });
  const metadata = await guest.getAuthMetadata();
  const redirect = redirectUri();
  const clientId = await OAuth2.registerClient(metadata, {
    client_name: CLIENT_NAME,
    client_uri: `${window.location.origin}/`,
    redirect_uris: [redirect] as [string, ...string[]],
    application_type: "web",
  });
  const state = crypto.randomUUID();
  const oauth = new OAuth2(metadata, {
    clientId,
    redirectUri: redirect,
  });
  const stored: StoredOauth = {
    kind: "oauth2",
    homeserver,
    state,
    clientId: oauth.context.clientId,
    redirectUri: oauth.context.redirectUri,
    codeVerifier: oauth.context.codeVerifier,
    deviceId: oauth.context.deviceId,
    metadata,
  };
  sessionStorage.setItem(OAUTH_STORAGE_KEY, JSON.stringify(stored));
  const url = await oauth.generateAuthorizationCodeGrantUrl(state, "query", "login");
  window.location.assign(url);
}

async function beginSsoRedirect(homeserver: string): Promise<void> {
  const guest = createClient({ baseUrl: homeserver });
  try {
    const flows = await guest.loginFlows();
    const hasSso = flows.flows?.some(
      (flow) => flow.type === "m.login.sso" || flow.type === "m.login.cas",
    );
    if (!hasSso) {
      // Still attempt redirect — some servers omit flows but support SSO.
    }
  } catch {
    // Continue — getSsoLoginUrl still builds a valid redirect.
  }
  const redirect = redirectUri();
  // Spec path: /_matrix/client/v3/login/sso/redirect?redirectUrl=...
  const ssoUrl = guest.getSsoLoginUrl(redirect, "sso");
  const stored: StoredSso = { kind: "sso", homeserver };
  sessionStorage.setItem(SSO_STORAGE_KEY, JSON.stringify(stored));
  window.location.assign(ssoUrl);
}

/** Start SSO / OAuth2 login for the given homeserver (redirects away). */
export async function beginOidcOrSsoLogin(homeserverInput: string): Promise<void> {
  const homeserver = resolveHomeserver(homeserverInput);
  if (!homeserver) throw new Error("Homeserver is required");

  try {
    await beginOauth2(homeserver);
    return;
  } catch {
    // Fall through to classic SSO redirect.
  }

  await beginSsoRedirect(homeserver);
}

function readCodeAndState(): { code: string; state: string } | null {
  const query = new URLSearchParams(window.location.search);
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const code = query.get("code") ?? hash.get("code");
  const state = query.get("state") ?? hash.get("state");
  if (!code || !state) return null;
  return { code, state };
}

function readLoginToken(): string | null {
  const query = new URLSearchParams(window.location.search);
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  return query.get("loginToken") ?? hash.get("loginToken");
}

/** Complete an in-flight OAuth/SSO callback if present. Returns whether a callback was handled. */
export async function maybeCompleteAuthCallback(): Promise<{
  handled: boolean;
  error: string | null;
}> {
  const loginToken = readLoginToken();
  if (loginToken) {
    try {
      const raw = sessionStorage.getItem(SSO_STORAGE_KEY);
      const stored = raw ? (JSON.parse(raw) as StoredSso) : null;
      sessionStorage.removeItem(SSO_STORAGE_KEY);
      const homeserver = stored?.homeserver;
      if (!homeserver) throw new Error("Missing SSO homeserver context");
      await loginWithSsoToken({ homeserver, token: loginToken });
      clearAuthQuery();
      return { handled: true, error: null };
    } catch (error) {
      clearAuthQuery();
      return {
        handled: true,
        error: error instanceof Error ? error.message : "SSO sign-in failed",
      };
    }
  }

  const grant = readCodeAndState();
  if (!grant) return { handled: false, error: null };

  try {
    const raw = sessionStorage.getItem(OAUTH_STORAGE_KEY);
    sessionStorage.removeItem(OAUTH_STORAGE_KEY);
    if (!raw) throw new Error("Missing OAuth context");

    const oauthStored = JSON.parse(raw) as StoredOauth;
    if (oauthStored.kind !== "oauth2") throw new Error("Unsupported OAuth context");
    if (oauthStored.state !== grant.state) {
      throw new Error("OAuth state mismatch");
    }
    const oauth = new OAuth2(oauthStored.metadata, {
      clientId: oauthStored.clientId,
      redirectUri: oauthStored.redirectUri,
      codeVerifier: oauthStored.codeVerifier,
      deviceId: oauthStored.deviceId,
    });
    const tokens = await oauth.completeAuthorizationCodeGrant(grant.code);
    await loginWithAccessToken({
      homeserver: oauthStored.homeserver,
      accessToken: tokens.access_token,
      deviceId: oauthStored.deviceId || undefined,
    });
    clearAuthQuery();
    return { handled: true, error: null };
  } catch (error) {
    clearAuthQuery();
    return {
      handled: true,
      error: error instanceof Error ? error.message : "SSO sign-in failed",
    };
  }
}

/** True when the current URL looks like an auth callback. */
export function isAuthCallbackUrl(): boolean {
  return Boolean(readLoginToken() || readCodeAndState());
}
