import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { DISCOVERY_CATEGORIES } from "../../../services/discovery.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function loader() {
  return handleLoader(async () => {
    return jsonResponse({
      success: true,
      data: DISCOVERY_CATEGORIES(),
    });
  });
}
