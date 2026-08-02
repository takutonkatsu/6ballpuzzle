import admin from "firebase-admin";
import fs from "node:fs";

export type AuthenticatedPlayer = {
  uid: string;
  displayName?: string;
};

let initialized = false;

export async function verifyPlayerToken(token: string | undefined): Promise<AuthenticatedPlayer> {
  if (process.env.ALLOW_UNVERIFIED_DEV_TOKENS === "true") {
    if (token?.startsWith("dev:")) {
      return { uid: token.slice("dev:".length) || "dev-player" };
    }
    const decoded = decodeUnverifiedFirebaseToken(token);
    return { uid: decoded.uid, displayName: decoded.displayName };
  }

  if (!token) {
    throw new Error("missing_firebase_id_token");
  }

  initializeFirebaseAdmin();
  const decoded = await admin.auth().verifyIdToken(token, true);
  return {
    uid: decoded.uid,
    displayName: typeof decoded.name === "string" ? decoded.name : undefined
  };
}

function initializeFirebaseAdmin(): void {
  if (initialized) return;

  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (serviceAccountPath) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8")) as admin.ServiceAccount;
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
  } else {
    admin.initializeApp();
  }

  initialized = true;
}

function decodeUnverifiedFirebaseToken(token: string | undefined): AuthenticatedPlayer {
  if (!token) {
    return { uid: "dev-player" };
  }

  const parts = token.split(".");
  if (parts.length < 2) {
    return { uid: token.length <= 128 ? token : `token-${shortTokenHash(token)}` };
  }

  try {
    const payload = JSON.parse(Buffer.from(base64UrlToBase64(parts[1]), "base64").toString("utf8")) as {
      user_id?: unknown;
      sub?: unknown;
      name?: unknown;
    };
    const uid = typeof payload.user_id === "string" && payload.user_id
      ? payload.user_id
      : typeof payload.sub === "string" && payload.sub
        ? payload.sub
        : `token-${shortTokenHash(token)}`;
    return {
      uid,
      displayName: typeof payload.name === "string" ? payload.name : undefined
    };
  } catch {
    return { uid: `token-${shortTokenHash(token)}` };
  }
}

function base64UrlToBase64(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  return normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
}

function shortTokenHash(value: string): string {
  let hash = 0x811c9dc5;
  for (const unit of value) {
    hash ^= unit.charCodeAt(0);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36);
}
