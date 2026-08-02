module.exports = {
  apps: [
    {
      name: "hexagon-realtime",
      script: "dist/index.js",
      instances: 1,
      exec_mode: "fork",
      max_memory_restart: "300M",
      env: {
        NODE_ENV: "production",
        HOST: "0.0.0.0",
        PORT: "8080",
        PING_INTERVAL_MS: "5000",
        ROOM_IDLE_TTL_MS: "60000",
        MAX_MESSAGE_BYTES: "65536",
        ALLOW_UNVERIFIED_DEV_TOKENS: "false",
        METRICS_TOKEN: ""
      }
    }
  ]
};
