export function logInfo(message: string, fields: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ level: "info", message, ...fields, at: new Date().toISOString() }));
}

export function logWarn(message: string, fields: Record<string, unknown> = {}): void {
  console.warn(JSON.stringify({ level: "warn", message, ...fields, at: new Date().toISOString() }));
}

export function logError(message: string, fields: Record<string, unknown> = {}): void {
  console.error(JSON.stringify({ level: "error", message, ...fields, at: new Date().toISOString() }));
}
