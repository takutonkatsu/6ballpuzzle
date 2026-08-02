import type WebSocket from "ws";
import { logInfo, logWarn } from "../logger.js";
import type { ClientMetricMessage, ClientRole, RelayMessage, ServerMessage } from "../protocol/messages.js";
import { serverError } from "../protocol/messages.js";
import { publicUid } from "../safeLog.js";

export type RoomClient = {
  uid: string;
  role: ClientRole;
  displayName?: string;
  socket: WebSocket;
  joinedAt: number;
};

export class BattleRoom {
  readonly roomId: string;
  private readonly clientsByRole = new Map<ClientRole, RoomClient>();
  private readonly relayCountsByType = new Map<string, number>();
  private emptySince: number | null = null;
  private createdAt = Date.now();
  private lastRelayAt: number | null = null;
  private totalRelays = 0;
  private totalDeliveredRelays = 0;
  private totalInboundRelayBytes = 0;
  private totalOutboundRelayBytes = 0;
  private readonly inboundRelayBytesByType = new Map<string, number>();
  private readonly outboundRelayBytesByType = new Map<string, number>();
  private totalClientMetricBytes = 0;
  private readonly clientMetricsByName = new Map<string, number>();

  constructor(roomId: string) {
    this.roomId = roomId;
  }

  get size(): number {
    return this.clientsByRole.size;
  }

  get isEmpty(): boolean {
    return this.clientsByRole.size === 0;
  }

  get idleSince(): number | null {
    return this.emptySince;
  }

  snapshot(now = Date.now()): RoomSnapshot {
    return {
      roomId: this.roomId,
      size: this.size,
      roles: Array.from(this.clientsByRole.keys()).sort(),
      ageSeconds: Math.round((now - this.createdAt) / 1000),
      idleSeconds: this.emptySince === null ? null : Math.round((now - this.emptySince) / 1000),
      totalRelays: this.totalRelays,
      totalDeliveredRelays: this.totalDeliveredRelays,
      totalInboundRelayBytes: this.totalInboundRelayBytes,
      totalOutboundRelayBytes: this.totalOutboundRelayBytes,
      relayCountsByType: Object.fromEntries(this.relayCountsByType.entries()),
      inboundRelayBytesByType: Object.fromEntries(this.inboundRelayBytesByType.entries()),
      outboundRelayBytesByType: Object.fromEntries(this.outboundRelayBytesByType.entries()),
      totalClientMetricBytes: this.totalClientMetricBytes,
      clientMetricsByName: Object.fromEntries(this.clientMetricsByName.entries()),
      lastRelayAgoSeconds: this.lastRelayAt === null ? null : Math.round((now - this.lastRelayAt) / 1000)
    };
  }

  join(client: RoomClient): void {
    const existing = this.clientsByRole.get(client.role);
    if (existing && existing.uid !== client.uid) {
      sendJson(client.socket, serverError("role_taken", `${client.role} is already connected.`));
      client.socket.close(4409, "role_taken");
      logWarn("Rejected room join because role is already taken", {
        roomId: this.roomId,
        role: client.role,
        existingUid: publicUid(existing.uid),
        uid: publicUid(client.uid)
      });
      return;
    }

    if (existing) {
      existing.socket.close(4000, "replaced_by_new_connection");
    }

    this.clientsByRole.set(client.role, client);
    this.emptySince = null;
    sendJson(client.socket, {
      type: "helloAck",
      roomId: this.roomId,
      role: client.role,
      uid: client.uid,
      transportVersion: 1,
      serverAt: Date.now()
    });
    this.broadcastPresence();
    logInfo("Client joined room", {
      roomId: this.roomId,
      role: client.role,
      uid: publicUid(client.uid),
      size: this.size
    });
  }

  leave(socket: WebSocket): void {
    for (const [role, client] of this.clientsByRole.entries()) {
      if (client.socket === socket) {
        this.clientsByRole.delete(role);
        logInfo("Client left room", {
          roomId: this.roomId,
          role,
          uid: publicUid(client.uid),
          size: this.size,
          connectedSeconds: Math.round((Date.now() - client.joinedAt) / 1000),
          room: this.snapshot()
        });
        if (this.clientsByRole.size === 0) {
          this.emptySince = Date.now();
        } else {
          this.broadcastPresence();
        }
        return;
      }
    }
  }

  handleRelay(senderSocket: WebSocket, message: RelayMessage, inboundBytes: number): void {
    const sender = this.findClient(senderSocket);
    if (!sender) {
      sendJson(senderSocket, serverError("not_joined", "Client has not joined this room."));
      return;
    }

    const envelope: ServerMessage = {
      type: "relay",
      roomId: this.roomId,
      from: { uid: sender.uid, role: sender.role },
      messageType: message.type,
      seq: message.seq,
      sentAt: message.sentAt,
      serverAt: Date.now(),
      payload: message.payload
    };

    const encodedEnvelope = JSON.stringify(envelope);
    const outboundBytesPerDelivery = Buffer.byteLength(encodedEnvelope);
    let delivered = 0;
    for (const client of this.clientsByRole.values()) {
      if (client.socket !== senderSocket && client.socket.readyState === client.socket.OPEN) {
        client.socket.send(encodedEnvelope);
        delivered += 1;
      }
    }

    this.totalRelays += 1;
    this.totalDeliveredRelays += delivered;
    this.totalInboundRelayBytes += inboundBytes;
    this.totalOutboundRelayBytes += outboundBytesPerDelivery * delivered;
    this.lastRelayAt = Date.now();
    this.relayCountsByType.set(message.type, (this.relayCountsByType.get(message.type) ?? 0) + 1);
    this.inboundRelayBytesByType.set(
      message.type,
      (this.inboundRelayBytesByType.get(message.type) ?? 0) + inboundBytes
    );
    this.outboundRelayBytesByType.set(
      message.type,
      (this.outboundRelayBytesByType.get(message.type) ?? 0) + outboundBytesPerDelivery * delivered
    );
  }

  handleClientMetric(senderSocket: WebSocket, message: ClientMetricMessage, inboundBytes: number): void {
    const sender = this.findClient(senderSocket);
    if (!sender) {
      sendJson(senderSocket, serverError("not_joined", "Client has not joined this room."));
      return;
    }

    const value = Number.isFinite(message.value) ? message.value ?? 1 : 1;
    this.totalClientMetricBytes += inboundBytes;
    this.clientMetricsByName.set(message.name, (this.clientMetricsByName.get(message.name) ?? 0) + value);
  }

  private findClient(socket: WebSocket): RoomClient | undefined {
    for (const client of this.clientsByRole.values()) {
      if (client.socket === socket) return client;
    }
    return undefined;
  }

  private broadcastPresence(): void {
    const players = Array.from(this.clientsByRole.values()).map((client) => ({
      uid: client.uid,
      role: client.role,
      displayName: client.displayName
    }));
    const message: ServerMessage = {
      type: "presence",
      roomId: this.roomId,
      players,
      serverAt: Date.now()
    };
    for (const client of this.clientsByRole.values()) {
      sendJson(client.socket, message);
    }
  }
}

export type RoomSnapshot = {
  roomId: string;
  size: number;
  roles: string[];
  ageSeconds: number;
  idleSeconds: number | null;
  totalRelays: number;
  totalDeliveredRelays: number;
  totalInboundRelayBytes: number;
  totalOutboundRelayBytes: number;
  relayCountsByType: Record<string, number>;
  inboundRelayBytesByType: Record<string, number>;
  outboundRelayBytesByType: Record<string, number>;
  totalClientMetricBytes: number;
  clientMetricsByName: Record<string, number>;
  lastRelayAgoSeconds: number | null;
};

export function sendJson(socket: WebSocket, message: ServerMessage): void {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}
