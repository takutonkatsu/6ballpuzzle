import "dotenv/config";
import http from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { verifyPlayerToken } from "./auth/firebaseAuth.js";
import { logError, logInfo, logWarn } from "./logger.js";
import {
  parseJsonMessage,
  isClientMetricMessage,
  isHelloMessage,
  isRelayMessage,
  serverError
} from "./protocol/messages.js";
import { RoomRegistry } from "./rooms/RoomRegistry.js";

type ClientState = {
  isAlive: boolean;
  roomId?: string;
};

const host = process.env.HOST ?? "0.0.0.0";
const port = Number.parseInt(process.env.PORT ?? "8080", 10);
const maxMessageBytes = Number.parseInt(process.env.MAX_MESSAGE_BYTES ?? "65536", 10);
const roomIdleTtlMs = Number.parseInt(process.env.ROOM_IDLE_TTL_MS ?? "60000", 10);
const pingIntervalMs = Number.parseInt(process.env.PING_INTERVAL_MS ?? "5000", 10);
const metricsToken = process.env.METRICS_TOKEN?.trim() ?? "";

const rooms = new RoomRegistry();
const states = new WeakMap<WebSocket, ClientState>();

const server = http.createServer((request, response) => {
  const pathname = requestPathname(request);
  if (request.method === "GET" && pathname === "/health") {
    const metrics = rooms.aggregateMetrics();
    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        ok: true,
        service: "hexagon-realtime",
        rooms: metrics.rooms,
        connectedClients: metrics.connectedClients,
        totalRelays: metrics.totalRelays,
        totalDeliveredRelays: metrics.totalDeliveredRelays,
        uptimeSeconds: Math.round(process.uptime()),
        serverAt: Date.now()
      })
    );
    return;
  }

  if (request.method === "GET" && pathname === "/metrics") {
    if (!isMetricsRequestAllowed(request)) {
      response.writeHead(403, { "content-type": "application/json" });
      response.end(JSON.stringify({ ok: false, error: "forbidden" }));
      return;
    }
    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        ok: true,
        service: "hexagon-realtime",
        aggregate: rooms.aggregateMetrics(),
        rooms: rooms.snapshots(50),
        uptimeSeconds: Math.round(process.uptime()),
        serverAt: Date.now()
      })
    );
    return;
  }

  response.writeHead(404, { "content-type": "application/json" });
  response.end(JSON.stringify({ ok: false, error: "not_found" }));
});

function requestPathname(request: http.IncomingMessage): string {
  try {
    return new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`).pathname;
  } catch {
    return request.url ?? "/";
  }
}

function isMetricsRequestAllowed(request: http.IncomingMessage): boolean {
  if (!metricsToken) {
    return process.env.NODE_ENV !== "production";
  }
  const headerToken = request.headers["x-metrics-token"];
  if (headerToken === metricsToken) {
    return true;
  }
  try {
    const url = new URL(request.url ?? "", `http://${request.headers.host ?? "localhost"}`);
    return url.searchParams.get("token") === metricsToken;
  } catch {
    return false;
  }
}

const wss = new WebSocketServer({ server, maxPayload: maxMessageBytes });

wss.on("connection", (socket, request) => {
  states.set(socket, { isAlive: true });
  logInfo("WebSocket connected", {
    remoteAddress: request.socket.remoteAddress
  });

  const helloTimeout = setTimeout(() => {
    const state = states.get(socket);
    if (!state?.roomId) {
      socket.send(JSON.stringify(serverError("hello_timeout", "Initial hello message was not received.")));
      socket.close(4408, "hello_timeout");
    }
  }, 5000);

  socket.on("pong", () => {
    const state = states.get(socket);
    if (state) state.isAlive = true;
  });

  socket.on("message", async (raw) => {
    try {
      const inboundBytes = Buffer.isBuffer(raw) ? raw.byteLength : Buffer.byteLength(raw.toString());
      const decoded = parseJsonMessage(raw, maxMessageBytes);
      const state = states.get(socket);
      if (!state) {
        socket.close(1011, "missing_client_state");
        return;
      }

      if (!state.roomId) {
        if (!isHelloMessage(decoded)) {
          socket.send(JSON.stringify(serverError("invalid_hello", "First message must be a valid hello.")));
          socket.close(4400, "invalid_hello");
          return;
        }

        let player;
        try {
          player = await verifyPlayerToken(decoded.token);
        } catch (error) {
          logWarn("Realtime auth failed", {
            error: error instanceof Error ? error.message : String(error)
          });
          socket.send(JSON.stringify(serverError("auth_failed", "Firebase authentication failed.")));
          socket.close(4401, "auth_failed");
          return;
        }
        const room = rooms.getOrCreate(decoded.roomId);
        state.roomId = decoded.roomId;
        clearTimeout(helloTimeout);
        room.join({
          uid: player.uid,
          role: decoded.role,
          displayName: decoded.displayName ?? player.displayName,
          socket,
          joinedAt: Date.now()
        });
        return;
      }

      if (isClientMetricMessage(decoded)) {
        rooms.getOrCreate(state.roomId).handleClientMetric(socket, decoded, inboundBytes);
        return;
      }

      if (!isRelayMessage(decoded)) {
        socket.send(JSON.stringify(serverError("invalid_message", "Unsupported message type.")));
        return;
      }

      rooms.getOrCreate(state.roomId).handleRelay(socket, decoded, inboundBytes);
    } catch (error) {
      logWarn("Failed to handle message", {
        error: error instanceof Error ? error.message : String(error)
      });
      socket.send(JSON.stringify(serverError("bad_message", "Message could not be processed.")));
    }
  });

  socket.on("close", () => {
    clearTimeout(helloTimeout);
    rooms.leave(socket);
  });

  socket.on("error", (error) => {
    logWarn("WebSocket error", {
      error: error.message
    });
  });
});

setInterval(() => {
  for (const socket of wss.clients) {
    const state = states.get(socket);
    if (!state) continue;
    if (!state.isAlive) {
      socket.terminate();
      continue;
    }
    state.isAlive = false;
    socket.ping();
  }
}, pingIntervalMs);

setInterval(() => {
  const removed = rooms.sweepIdleRooms(roomIdleTtlMs);
  if (removed > 0) {
    logInfo("Swept idle rooms", { removed, rooms: rooms.size });
  }
}, 30000);

setInterval(() => {
  const metrics = rooms.aggregateMetrics();
  if (metrics.rooms === 0 && metrics.totalRelays === 0) {
    return;
  }
  logInfo("Realtime metrics", {
    ...metrics,
    topRooms: rooms.snapshots(5)
  });
}, 60000);

server.listen(port, host, () => {
  logInfo("Hexagon realtime server started", {
    host,
    port,
    allowUnverifiedDevTokens: process.env.ALLOW_UNVERIFIED_DEV_TOKENS === "true",
    maxMessageBytes,
    roomIdleTtlMs,
    pingIntervalMs,
    metricsProtected: metricsToken.length > 0 || process.env.NODE_ENV === "production"
  });
});

process.on("uncaughtException", (error) => {
  logError("Uncaught exception", { error: error.stack ?? error.message });
});

process.on("unhandledRejection", (reason) => {
  logError("Unhandled rejection", { reason: reason instanceof Error ? reason.stack ?? reason.message : String(reason) });
});
