import type {
  AnalyticsPayload,
  AnalyticsStreaks,
  ArticleDetail,
  ArticleListItem,
  ArticleQuery,
  ArticleStateUpdate,
  AuthResponse,
  BatchArticleUpdate,
  Count,
  CreateFeedRequest,
  CreateFolderRequest,
  DiscoveryCategory,
  Feed,
  FeedStats,
  FeedSuggestion,
  FeedWithUnread,
  FolderFeed,
  FolderNode,
  LoginRequest,
  OpmlImportResult,
  Pagination,
  PasswordUpdateRequest,
  ProfileUpdateRequest,
  ReadingTimeStats,
  RegisterRequest,
  RegisterResponse,
  StatsHistory,
  StatsOverview,
  UpdateFeedRequest,
  UpdateFolderRequest,
  UserDetail,
  UserProfile,
} from "./api-types.js";

export const SESSION_EXPIRED_EVENT = "omi:session-expired";

export interface TokenPair {
  token: string;
  refreshToken: string;
}

export interface StorageArea {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

function createMemoryStorage(): StorageArea {
  const map = new Map<string, string>();
  return {
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => void map.set(key, value),
    removeItem: (key) => void map.delete(key),
  };
}

function resolveStorage(): StorageArea {
  try {
    if (typeof localStorage !== "undefined") return localStorage;
  } catch {
    return createMemoryStorage();
  }
  return createMemoryStorage();
}

const storage = resolveStorage();

const KEYS = {
  token: "omi.auth.token",
  refreshToken: "omi.auth.refreshToken",
  user: "omi.auth.user",
} as const;

export const tokenStore = {
  getTokens(): TokenPair | null {
    const token = storage.getItem(KEYS.token);
    const refreshToken = storage.getItem(KEYS.refreshToken);
    if (!token || !refreshToken) return null;
    return { token, refreshToken };
  },
  setTokens(tokens: TokenPair): void {
    storage.setItem(KEYS.token, tokens.token);
    storage.setItem(KEYS.refreshToken, tokens.refreshToken);
  },
  getUser(): UserProfile | null {
    const raw = storage.getItem(KEYS.user);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as UserProfile;
    } catch {
      return null;
    }
  },
  setUser(user: UserProfile): void {
    storage.setItem(KEYS.user, JSON.stringify(user));
  },
  clear(): void {
    storage.removeItem(KEYS.token);
    storage.removeItem(KEYS.refreshToken);
    storage.removeItem(KEYS.user);
  },
};

export class ApiError extends Error {
  status: number;
  payload: unknown;
  fieldErrors: Array<{ field: string; message: string }> | null;

  constructor(status: number, message: string, payload: unknown, fieldErrors: Array<{ field: string; message: string }> | null = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.payload = payload;
    this.fieldErrors = fieldErrors;
  }
}

interface RequestConfig {
  method?: string;
  body?: unknown;
  query?: Record<string, unknown>;
  signal?: AbortSignal;
  skipAuthRefresh?: boolean;
}

function buildUrl(path: string, query?: Record<string, unknown>): string {
  if (!query) return path;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== "") {
      params.set(key, String(value));
    }
  }
  const qs = params.toString();
  return qs ? `${path}?${qs}` : path;
}

async function rawRequest(path: string, config: RequestConfig): Promise<Response> {
  const headers: Record<string, string> = {};
  const tokens = tokenStore.getTokens();
  if (tokens?.token) {
    headers.Authorization = `Bearer ${tokens.token}`;
  }

  let body: BodyInit | undefined;
  if (config.body instanceof FormData) {
    body = config.body;
  } else if (config.body !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(config.body);
  }

  return fetch(buildUrl(path, config.query), {
    method: config.method ?? "GET",
    headers,
    body,
    signal: config.signal,
  });
}

let refreshInFlight: Promise<boolean> | null = null;

async function performRefresh(): Promise<boolean> {
  const tokens = tokenStore.getTokens();
  if (!tokens?.refreshToken) return false;
  try {
    const response = await fetch("/api/auth/refresh", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken: tokens.refreshToken }),
    });
    if (!response.ok) return false;
    const data = (await response.json()) as TokenPair;
    tokenStore.setTokens(data);
    return true;
  } catch {
    return false;
  }
}

function refreshTokens(): Promise<boolean> {
  if (!refreshInFlight) {
    refreshInFlight = performRefresh().finally(() => {
      refreshInFlight = null;
    });
  }
  return refreshInFlight;
}

function notifySessionExpired(): void {
  if (typeof dispatchEvent === "function" && typeof CustomEvent === "function") {
    dispatchEvent(new CustomEvent(SESSION_EXPIRED_EVENT));
  }
}

async function request(path: string, config: RequestConfig = {}): Promise<Response> {
  let response = await rawRequest(path, config);
  if (response.status === 401 && !config.skipAuthRefresh && tokenStore.getTokens()?.refreshToken) {
    const refreshed = await refreshTokens();
    if (refreshed) {
      response = await rawRequest(path, config);
    } else {
      tokenStore.clear();
      notifySessionExpired();
    }
  }
  return response;
}

async function parseErrorResponse(response: Response): Promise<ApiError> {
  let payload: unknown = null;
  let message = `Request failed with status ${response.status}`;
  let fieldErrors: Array<{ field: string; message: string }> | null = null;
  try {
    payload = await response.json();
    const body = payload as { error?: string; errors?: Array<{ field: string; message: string }> };
    if (typeof body.error === "string") message = body.error;
    if (Array.isArray(body.errors)) fieldErrors = body.errors;
  } catch {
    return new ApiError(response.status, message, null);
  }
  return new ApiError(response.status, message, payload, fieldErrors);
}

async function requestJson<T>(path: string, config: RequestConfig = {}): Promise<T> {
  const response = await request(path, config);
  if (!response.ok) {
    throw await parseErrorResponse(response);
  }
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}

async function requestBlob(path: string, config: RequestConfig = {}): Promise<Blob> {
  const response = await request(path, config);
  if (!response.ok) {
    throw await parseErrorResponse(response);
  }
  return response.blob();
}

export function toCount(value: Count | string): number {
  return typeof value === "number" ? value : parseInt(value, 10) || 0;
}

export function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export const authApi = {
  async login(body: LoginRequest): Promise<AuthResponse> {
    return requestJson<AuthResponse>("/api/auth/login", {
      method: "POST",
      body,
      skipAuthRefresh: true,
    });
  },
  async register(body: RegisterRequest): Promise<RegisterResponse> {
    return requestJson<RegisterResponse>("/api/auth/register", {
      method: "POST",
      body,
      skipAuthRefresh: true,
    });
  },
  async logout(): Promise<void> {
    await requestJson<{ message: string }>("/api/auth/logout", { method: "POST" }).catch(() => undefined);
  },
  async forgotPassword(email: string): Promise<{ message: string }> {
    return requestJson<{ message: string }>("/api/auth/forgot-password", {
      method: "POST",
      body: { email },
      skipAuthRefresh: true,
    });
  },
  async resetPassword(token: string, password: string): Promise<{ message: string }> {
    return requestJson<{ message: string }>("/api/auth/reset-password", {
      method: "POST",
      body: { token, password },
      skipAuthRefresh: true,
    });
  },
};

export const usersApi = {
  async getMe(): Promise<{ user: UserDetail }> {
    return requestJson<{ user: UserDetail }>("/api/users/me");
  },
  async updateProfile(body: ProfileUpdateRequest): Promise<{ user: Partial<UserProfile> }> {
    return requestJson<{ user: Partial<UserProfile> }>("/api/users/me", { method: "PUT", body });
  },
  async deleteAccount(password: string): Promise<void> {
    await requestJson<void>("/api/users/me", { method: "DELETE", body: { password } });
  },
  async updateSettings(settings: Record<string, unknown>): Promise<{ user: { id: string; settings: Record<string, unknown> }; settings: Record<string, unknown> }> {
    return requestJson("/api/users/me/settings", { method: "PUT", body: { settings } });
  },
  async updatePassword(body: PasswordUpdateRequest): Promise<{ message: string }> {
    return requestJson<{ message: string }>("/api/users/me/password", { method: "PUT", body });
  },
  async uploadAvatar(file: File): Promise<{ user: { id: string; avatarUrl: string }; avatarUrl: string }> {
    const form = new FormData();
    form.set("avatar", file);
    return requestJson("/api/users/me/avatar", { method: "POST", body: form });
  },
};

export const foldersApi = {
  async list(): Promise<{ folders: FolderNode[] }> {
    return requestJson<{ folders: FolderNode[] }>("/api/folders");
  },
  async create(body: CreateFolderRequest): Promise<{ folder: FolderNode }> {
    return requestJson<{ folder: FolderNode }>("/api/folders", { method: "POST", body });
  },
  async get(folderId: string): Promise<{ folder: FolderNode; feeds: FolderFeed[] }> {
    return requestJson<{ folder: FolderNode; feeds: FolderFeed[] }>(`/api/folders/${folderId}`);
  },
  async update(folderId: string, body: UpdateFolderRequest): Promise<{ folder: FolderNode }> {
    return requestJson<{ folder: FolderNode }>(`/api/folders/${folderId}`, { method: "PUT", body });
  },
  async remove(folderId: string): Promise<void> {
    await requestJson<void>(`/api/folders/${folderId}`, { method: "DELETE" });
  },
  async reorder(folderIds: string[]): Promise<{ message: string }> {
    return requestJson<{ message: string }>("/api/folders/reorder", { method: "PUT", body: { folderIds } });
  },
};

export const feedsApi = {
  async list(): Promise<{ feeds: FeedWithUnread[] }> {
    return requestJson<{ feeds: FeedWithUnread[] }>("/api/feeds");
  },
  async create(body: CreateFeedRequest): Promise<{ feed: Feed }> {
    return requestJson<{ feed: Feed }>("/api/feeds", { method: "POST", body });
  },
  async get(feedId: string): Promise<{ feed: Feed; stats: FeedStats }> {
    return requestJson<{ feed: Feed; stats: FeedStats }>(`/api/feeds/${feedId}`);
  },
  async update(feedId: string, body: UpdateFeedRequest): Promise<{ feed: Feed }> {
    return requestJson<{ feed: Feed }>(`/api/feeds/${feedId}`, { method: "PUT", body });
  },
  async remove(feedId: string): Promise<void> {
    await requestJson<void>(`/api/feeds/${feedId}`, { method: "DELETE" });
  },
  async refresh(feedId: string): Promise<{ message: string }> {
    return requestJson<{ message: string }>(`/api/feeds/${feedId}/refresh`, { method: "POST" });
  },
  async markAllRead(feedId: string): Promise<{ message: string; count: Count }> {
    return requestJson<{ message: string; count: Count }>(`/api/feeds/${feedId}/mark-all-read`, { method: "POST" });
  },
};

export const articlesApi = {
  async list(query: ArticleQuery = {}): Promise<{ articles: ArticleListItem[]; pagination: Pagination }> {
    const search: Record<string, unknown> = { ...query };
    if (query.isRead !== undefined) search.isRead = String(query.isRead);
    if (query.isStarred !== undefined) search.isStarred = String(query.isStarred);
    return requestJson<{ articles: ArticleListItem[]; pagination: Pagination }>("/api/articles", { query: search });
  },
  async get(articleId: string): Promise<{ article: ArticleDetail }> {
    return requestJson<{ article: ArticleDetail }>(`/api/articles/${articleId}`);
  },
  async updateState(articleId: string, updates: ArticleStateUpdate): Promise<{ message: string }> {
    return requestJson<{ message: string }>(`/api/articles/${articleId}/state`, { method: "PUT", body: updates });
  },
  async batchUpdate(body: BatchArticleUpdate): Promise<{ message: string; updatedCount: number }> {
    return requestJson<{ message: string; updatedCount: number }>("/api/articles/batch-update", { method: "PUT", body });
  },
  async markAllRead(filters: { feedId?: string; folderId?: string } = {}): Promise<{ message: string; count: Count }> {
    return requestJson<{ message: string; count: Count }>("/api/articles/mark-all-read", { method: "POST", query: filters });
  },
};

export const discoveryApi = {
  async categories(): Promise<{ success: boolean; data: DiscoveryCategory[] }> {
    return requestJson<{ success: boolean; data: DiscoveryCategory[] }>("/api/discovery/categories");
  },
  async discover(options: { categories?: string; limit?: number; language?: string } = {}): Promise<{ success: boolean; data: FeedSuggestion[] }> {
    return requestJson<{ success: boolean; data: FeedSuggestion[] }>("/api/discovery/discover", { query: options });
  },
  async search(query: string, options: { category?: string; language?: string; limit?: number } = {}): Promise<{ success: boolean; data: FeedSuggestion[] }> {
    return requestJson<{ success: boolean; data: FeedSuggestion[] }>("/api/discovery/search", {
      query: { q: query, ...options },
    });
  },
  async validate(url: string): Promise<{ success: boolean; data: { valid: boolean; metadata?: Partial<FeedSuggestion> | null; error?: string } }> {
    return requestJson("/api/discovery/validate", { method: "POST", body: { url } });
  },
  async related(feedId: string, limit?: number): Promise<{ success: boolean; data: FeedSuggestion[] }> {
    return requestJson<{ success: boolean; data: FeedSuggestion[] }>(`/api/discovery/related/${feedId}`, { query: { limit } });
  },
  async importOpml(file: File): Promise<{ success: boolean; data?: OpmlImportResult; error?: string }> {
    const form = new FormData();
    form.set("file", file);
    return requestJson("/api/discovery/import/opml", { method: "POST", body: form });
  },
  async exportOpml(): Promise<Blob> {
    return requestBlob("/api/discovery/export/opml");
  },
};

export const statsApi = {
  async overview(): Promise<StatsOverview> {
    return requestJson<StatsOverview>("/api/stats/overview");
  },
  async history(options: { startDate?: string; endDate?: string; period?: "day" | "week" | "month" | "year" } = {}): Promise<StatsHistory> {
    return requestJson<StatsHistory>("/api/stats/history", { query: options });
  },
  async readingTime(): Promise<ReadingTimeStats> {
    return requestJson<ReadingTimeStats>("/api/stats/reading-time");
  },
  async recordReadingTime(articleId: string, timeSpent: number): Promise<{ message: string }> {
    return requestJson<{ message: string }>("/api/stats/reading-time", { method: "POST", body: { articleId, timeSpent } });
  },
};

export const analyticsApi = {
  async summary(timeframe: "day" | "week" | "month" | "year" | "all" = "month"): Promise<AnalyticsPayload> {
    return requestJson<AnalyticsPayload>("/api/analytics", { query: { timeframe } });
  },
  async streaks(): Promise<AnalyticsStreaks> {
    return requestJson<AnalyticsStreaks>("/api/analytics/streaks");
  },
  async trackArticleRead(body: { articleId: string; scrollDepth: number; interactionTime: number; completed: boolean }): Promise<{ success: boolean }> {
    return requestJson<{ success: boolean }>("/api/analytics/article-read", { method: "POST", body });
  },
  async trackFeedInteraction(body: { feedId: string; action: "subscribe" | "unsubscribe" | "mute" | "favorite" }): Promise<{ success: boolean }> {
    return requestJson<{ success: boolean }>("/api/analytics/feed-interaction", { method: "POST", body });
  },
  async exportData(): Promise<Blob> {
    return requestBlob("/api/analytics/export");
  },
};
