export function publicUid(uid: string | undefined): string {
  if (!uid) return "";
  if (uid.length <= 10) return uid;
  return `${uid.slice(0, 4)}...${uid.slice(-4)}`;
}
