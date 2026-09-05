export type IsoDateString = string;
export type Count = number;

export interface UserProfile {
  id: string;
  email: string;
  username: string;
  firstName: string | null;
  lastName: string | null;
  avatarUrl: string | null;
  role: string;
  emailVerified: boolean;
  settings: Record<string, unknown>;
}

export interface UserDetail extends UserProfile {
  createdAt: IsoDateString;
  updatedAt: IsoDateString;
  lastLoginAt: IsoDateString | null;
}

export interface Folder {
  id: string;
  name: string;
  parentId: string | null;
  color: string | null;
  icon: string | null;
  position: number;
  createdAt: IsoDateString;
  updatedAt: IsoDateString;
}

export interface FolderNode extends Folder {
  feedCount: Count;
  unreadCount: Count;
  children: FolderNode[];
}

export interface Feed {
  id: string;
  folderId: string | null;
  url: string;
  title: string;
  description: string | null;
  siteUrl: string | null;
  favicon: string | null;
  imageUrl: string | null;
  customTitle: string | null;
  updateInterval: number;
  lastFetchedAt: IsoDateString | null;
  lastFetchError: string | null;
  errorCount: number;
  isActive: boolean;
  settings: Record<string, unknown>;
  fullTextEnabled: boolean;
  sourceType: "rss" | "page";
  pageUrl: string | null;
  pageSelector: string | null;
  createdAt: IsoDateString;
  updatedAt: IsoDateString;
}

export interface FeedWithUnread extends Feed {
  unreadCount: Count;
}

export interface FolderFeed {
  id: string;
  title: string;
  customTitle: string | null;
  favicon: string | null;
  unreadCount: Count;
}

export interface FeedStats {
  totalArticles: Count;
  unreadArticles: Count;
}

export interface ArticleListItem {
  id: string;
  feedId: string;
  title: string;
  url: string;
  summary: string | null;
  content: string | null;
  author: string | null;
  publishedAt: IsoDateString | null;
  imageUrl: string | null;
  enclosures: unknown[];
  isRead: boolean;
  isStarred: boolean;
  readAt: IsoDateString | null;
  feedTitle: string;
  feedFavicon: string | null;
}

// Detail payload adds the (up to 256KB) extracted full text — list payloads
// deliberately omit it; the reader fetches it on open.
export interface ArticleDetail extends ArticleListItem {
  contentExtracted: string | null;
}

export interface Pagination {
  page: number;
  limit: number;
  total: Count;
  totalPages: number;
}

export interface ArticleQuery {
  page?: number;
  limit?: number;
  sortBy?: "publishedAt" | "title" | "feedTitle";
  sortOrder?: "asc" | "desc";
  feedId?: string;
  folderId?: string;
  isRead?: boolean;
  isStarred?: boolean;
  search?: string;
}

export interface FeedSuggestion {
  url: string;
  title: string;
  description?: string;
  category?: string;
  language?: string;
  popularity?: number;
  relevanceScore?: number;
  reason?: string;
  favicon?: string;
  lastUpdated?: IsoDateString;
}

export interface DiscoveryCategory {
  id: string;
  name: string;
  description: string;
}

export interface ReadingStreakInfo {
  currentStreak: number;
  longestStreak: number;
  lastReadDate: IsoDateString | null;
}

export interface StatsOverview {
  totals: {
    totalArticles: Count;
    readArticles: Count;
    starredArticles: Count;
    totalFeeds: Count;
    totalFolders: Count;
    readPercentage: number;
  };
  velocity: {
    averagePerDay: number;
  };
  topFeeds: Array<{
    feedId: string;
    feedTitle: string;
    feedFavicon: string | null;
    readCount: Count;
  }>;
  readingStreak: ReadingStreakInfo;
}

export interface StatsHistory {
  period: "day" | "week" | "month" | "year";
  startDate: IsoDateString;
  endDate: IsoDateString;
  data: Array<{ period: string; count: Count }>;
}

export interface ReadingTimeStats {
  totalReadingTime: number;
  articlesRead: Count;
  averageReadingTime: number;
  estimatedWordsPerMinute: number;
  readingByHour: Array<{ hour: number; count: Count }>;
  readingByDayOfWeek: Array<{ dayOfWeek: number; count: Count }>;
}

export interface AnalyticsReading {
  totalArticlesRead: number;
  totalReadingTime: number;
  averageReadingTime: number;
  articlesPerDay: number;
  mostActiveHour: number;
  mostActiveDay: string;
  readingStreak: number;
  longestStreak: number;
}

export interface AnalyticsPreferences {
  topCategories: Array<{ category: string; count: number; percentage: number }>;
  topAuthors: Array<{ author: string; count: number; articles: number }>;
  topSources: Array<{ source: string; feedId: string; count: number }>;
  preferredLength: "short" | "medium" | "long";
  readingSpeed: number;
  topKeywords: Array<{ keyword: string; frequency: number }>;
}

export interface AnalyticsPatterns {
  dailyDistribution: Array<{ hour: number; count: number }>;
  weeklyDistribution: Array<{ day: string; count: number }>;
  monthlyTrend: Array<{ date: string; count: number }>;
  categoryTrends: Array<{ category: string; trend: "rising" | "falling" | "stable"; change: number }>;
  velocityTrend: "increasing" | "decreasing" | "stable";
}

export interface AnalyticsEngagement {
  averageTimePerParagraph: number;
  bookmarkRate: number;
  interactionScore: number;
}

export interface AnalyticsPayload {
  reading: AnalyticsReading;
  preferences: AnalyticsPreferences;
  patterns: AnalyticsPatterns;
  engagement: AnalyticsEngagement;
  insights: string[];
}

export interface AnalyticsStreaks {
  currentStreak: number;
  longestStreak: number;
  dailyHistory: Array<{ date: string; articlesRead: number }>;
}

export interface OpmlImportResult {
  imported: number;
  failed: number;
  skipped: number;
  capped: boolean;
  reasons: { invalidUrl: number; duplicate: number; overLimit: number };
  errors: string[];
}

export interface LoginRequest {
  emailOrUsername: string;
  password: string;
}

export interface AuthResponse {
  token: string;
  refreshToken: string;
  user: UserProfile;
}

export interface RegisterRequest {
  email: string;
  username: string;
  password: string;
  firstName?: string;
  lastName?: string;
}

export interface RegisterResponse {
  token: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
    username: string;
  };
}

export interface CreateFolderRequest {
  name: string;
  color?: string;
  icon?: string;
  parentId?: string | null;
}

export interface UpdateFolderRequest {
  name?: string;
  color?: string;
  icon?: string;
  parentId?: string | null;
}

export interface CreateFeedRequest {
  url: string;
  folderId?: string;
  customTitle?: string;
  updateInterval?: number;
}

export interface UpdateFeedRequest {
  customTitle?: string;
  folderId?: string | null;
  updateInterval?: number;
  isActive?: boolean;
  fullTextEnabled?: boolean;
}

export interface CreatePageFeedRequest {
  pageUrl: string;
  pageSelector: string;
  title?: string;
  folderId?: string;
  updateInterval?: number;
}

export interface ArticleStateUpdate {
  isRead?: boolean;
  isStarred?: boolean;
}

export interface BatchArticleUpdate {
  articleIds: string[];
  updates: ArticleStateUpdate;
}

export interface ProfileUpdateRequest {
  firstName?: string;
  lastName?: string;
  username?: string;
}

export interface PasswordUpdateRequest {
  currentPassword: string;
  newPassword: string;
}
