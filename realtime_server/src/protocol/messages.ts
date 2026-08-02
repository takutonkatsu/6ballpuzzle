import type { RawData } from "ws";

export const TRANSPORT_VERSION = 1;

export type ClientRole = "host" | "guest";

export type HelloMessage = {
  type: "hello";
  token?: string;
  roomId: string;
  role: ClientRole;
  transportVersion?: number;
  clientBuild?: string;
  displayName?: string;
};

export type RelayMessageType =
  | "activePiece"
  | "board"
  | "attack"
  | "stamp"
  | "ojamaSpawn"
  | "gameOver"
  | "rematchRequest"
  | "rematchReady"
  | "snapshotRequest"
  | "snapshot"
  | "resultCommit";

export type RelayMessage = {
  type: RelayMessageType;
  seq?: number;
  sentAt?: number;
  payload?: unknown;
};

export type ClientMetricMessage = {
  type: "metric";
  name: string;
  value?: number;
  sentAt?: number;
  payload?: unknown;
};

export type ServerMessage =
  | {
      type: "helloAck";
      roomId: string;
      role: ClientRole;
      uid: string;
      transportVersion: number;
      serverAt: number;
    }
  | {
      type: "presence";
      roomId: string;
      players: Array<{ uid: string; role: ClientRole; displayName?: string }>;
      serverAt: number;
    }
  | {
      type: "relay";
      roomId: string;
      from: { uid: string; role: ClientRole };
      messageType: RelayMessageType;
      seq?: number;
      sentAt?: number;
      serverAt: number;
      payload?: unknown;
    }
  | {
      type: "error";
      code: string;
      message: string;
      serverAt: number;
    };

const relayTypes = new Set<RelayMessageType>([
  "activePiece",
  "board",
  "attack",
  "stamp",
  "ojamaSpawn",
  "gameOver",
  "rematchRequest",
  "rematchReady",
  "snapshotRequest",
  "snapshot",
  "resultCommit"
]);

export function parseJsonMessage(raw: RawData, maxBytes: number): unknown {
  const bytes = Buffer.isBuffer(raw) ? raw.byteLength : Buffer.byteLength(raw.toString());
  if (bytes > maxBytes) {
    throw new Error(`message_too_large:${bytes}`);
  }
  return JSON.parse(raw.toString());
}

export function isHelloMessage(value: unknown): value is HelloMessage {
  if (!isRecord(value)) return false;
  return (
    value.type === "hello" &&
    typeof value.roomId === "string" &&
    value.roomId.length > 0 &&
    value.roomId.length <= 160 &&
    (value.role === "host" || value.role === "guest") &&
    (value.token === undefined || typeof value.token === "string") &&
    (value.displayName === undefined || typeof value.displayName === "string")
  );
}

export function isRelayMessage(value: unknown): value is RelayMessage {
  if (!isRecord(value)) return false;
  return typeof value.type === "string" && relayTypes.has(value.type as RelayMessageType);
}

export function isClientMetricMessage(value: unknown): value is ClientMetricMessage {
  if (!isRecord(value)) return false;
  return (
    value.type === "metric" &&
    typeof value.name === "string" &&
    value.name.length > 0 &&
    value.name.length <= 80 &&
    (value.value === undefined || typeof value.value === "number")
  );
}

export function serverError(code: string, message: string): ServerMessage {
  return { type: "error", code, message, serverAt: Date.now() };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
