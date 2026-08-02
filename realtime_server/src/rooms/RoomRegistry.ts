import type WebSocket from "ws";
import { BattleRoom, type RoomSnapshot } from "./BattleRoom.js";

export class RoomRegistry {
  private readonly rooms = new Map<string, BattleRoom>();

  get size(): number {
    return this.rooms.size;
  }

  getOrCreate(roomId: string): BattleRoom {
    const existing = this.rooms.get(roomId);
    if (existing) return existing;

    const room = new BattleRoom(roomId);
    this.rooms.set(roomId, room);
    return room;
  }

  snapshots(limit = 20): RoomSnapshot[] {
    const now = Date.now();
    return Array.from(this.rooms.values())
      .map((room) => room.snapshot(now))
      .sort((a, b) => b.totalRelays - a.totalRelays)
      .slice(0, limit);
  }

  aggregateMetrics(): RoomAggregateMetrics {
    const snapshots = this.snapshots(Number.MAX_SAFE_INTEGER);
    const relaysByType: Record<string, number> = {};
    let connectedClients = 0;
    let totalRelays = 0;
    let totalDeliveredRelays = 0;
    let totalInboundRelayBytes = 0;
    let totalOutboundRelayBytes = 0;
    let totalClientMetricBytes = 0;
    const inboundRelayBytesByType: Record<string, number> = {};
    const outboundRelayBytesByType: Record<string, number> = {};
    const clientMetricsByName: Record<string, number> = {};

    for (const snapshot of snapshots) {
      connectedClients += snapshot.size;
      totalRelays += snapshot.totalRelays;
      totalDeliveredRelays += snapshot.totalDeliveredRelays;
      totalInboundRelayBytes += snapshot.totalInboundRelayBytes;
      totalOutboundRelayBytes += snapshot.totalOutboundRelayBytes;
      totalClientMetricBytes += snapshot.totalClientMetricBytes;
      for (const [type, count] of Object.entries(snapshot.relayCountsByType)) {
        relaysByType[type] = (relaysByType[type] ?? 0) + count;
      }
      for (const [type, bytes] of Object.entries(snapshot.inboundRelayBytesByType)) {
        inboundRelayBytesByType[type] = (inboundRelayBytesByType[type] ?? 0) + bytes;
      }
      for (const [type, bytes] of Object.entries(snapshot.outboundRelayBytesByType)) {
        outboundRelayBytesByType[type] = (outboundRelayBytesByType[type] ?? 0) + bytes;
      }
      for (const [name, value] of Object.entries(snapshot.clientMetricsByName)) {
        clientMetricsByName[name] = (clientMetricsByName[name] ?? 0) + value;
      }
    }

    return {
      rooms: this.rooms.size,
      connectedClients,
      totalRelays,
      totalDeliveredRelays,
      totalInboundRelayBytes,
      totalOutboundRelayBytes,
      totalClientMetricBytes,
      relaysByType,
      inboundRelayBytesByType,
      outboundRelayBytesByType,
      clientMetricsByName
    };
  }

  leave(socket: WebSocket): void {
    for (const room of this.rooms.values()) {
      room.leave(socket);
    }
  }

  sweepIdleRooms(roomIdleTtlMs: number): number {
    const now = Date.now();
    let removed = 0;
    for (const [roomId, room] of this.rooms.entries()) {
      if (room.isEmpty && room.idleSince !== null && now - room.idleSince >= roomIdleTtlMs) {
        this.rooms.delete(roomId);
        removed += 1;
      }
    }
    return removed;
  }
}

export type RoomAggregateMetrics = {
  rooms: number;
  connectedClients: number;
  totalRelays: number;
  totalDeliveredRelays: number;
  totalInboundRelayBytes: number;
  totalOutboundRelayBytes: number;
  totalClientMetricBytes: number;
  relaysByType: Record<string, number>;
  inboundRelayBytesByType: Record<string, number>;
  outboundRelayBytesByType: Record<string, number>;
  clientMetricsByName: Record<string, number>;
};
