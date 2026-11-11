// /u/<public id>/… routes belong to one phone. An unknown or malformed id is a plain 404.
import { userHashForPublicId } from "./account";
import { PUBLIC_ID } from "./identity";

export async function phone(publicId: string | undefined): Promise<{ publicId: string; userHash: string } | null> {
  if (!publicId || !PUBLIC_ID.test(publicId)) return null;
  const userHash = await userHashForPublicId(publicId);
  return userHash ? { publicId, userHash } : null;
}
