import { handle, jsonResponse } from "../../../lib/api/errors.js";

export const config = { mode: "app" };

export async function action() {
  return handle(async () => jsonResponse({ message: "Logged out successfully" }));
}
