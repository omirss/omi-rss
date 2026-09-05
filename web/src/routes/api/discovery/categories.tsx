import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function loader() {
  return handleLoader(async () => {
    const categories = [
      { id: "technology", name: "Technology", description: "Latest tech news and developments" },
      { id: "science", name: "Science", description: "Scientific discoveries and research" },
      { id: "business", name: "Business & Finance", description: "Business news and market analysis" },
      { id: "programming", name: "Programming & Development", description: "Software development and programming" },
      { id: "ai", name: "AI & Machine Learning", description: "Artificial Intelligence and ML news" },
      { id: "news", name: "World News", description: "Global news and current events" },
    ];

    return jsonResponse({
      success: true,
      data: categories,
    });
  });
}
