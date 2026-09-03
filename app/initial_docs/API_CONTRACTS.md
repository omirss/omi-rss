# API Contracts Documentation

## Base Configuration

### Base URL
- Production: `https://api.rss-reader.app/v1`
- Staging: `https://staging-api.rss-reader.app/v1`
- Local: `http://localhost:3000/v1`

### Authentication
All authenticated endpoints require JWT token in Authorization header:
```
Authorization: Bearer <token>
```

### Common Headers
```
Content-Type: application/json
Accept: application/json
X-Client-Version: 1.0.0
X-Device-ID: <uuid>
```

## REST API Endpoints

### Authentication

#### POST /auth/register
Register new user account.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "securePassword123!",
  "displayName": "John Doe",
  "inviteCode": "OPTIONAL123"
}
```

**Response (201):**
```json
{
  "user": {
    "id": "usr_abc123",
    "email": "user@example.com",
    "displayName": "John Doe",
    "createdAt": "2024-01-15T10:00:00Z"
  },
  "tokens": {
    "access": "eyJhbGc...",
    "refresh": "eyJhbGc...",
    "expiresIn": 3600
  }
}
```

#### POST /auth/login
Authenticate existing user.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "securePassword123!",
  "deviceId": "device_123",
  "deviceName": "iPhone 15 Pro"
}
```

**Response (200):**
```json
{
  "user": {
    "id": "usr_abc123",
    "email": "user@example.com",
    "displayName": "John Doe",
    "lastLoginAt": "2024-01-15T10:00:00Z"
  },
  "tokens": {
    "access": "eyJhbGc...",
    "refresh": "eyJhbGc...",
    "expiresIn": 3600
  }
}
```

### Feeds

#### GET /feeds
Get user's subscribed feeds.

**Query Parameters:**
- `category` (string): Filter by category ID
- `active` (boolean): Filter active/inactive
- `search` (string): Search in title/description
- `page` (number): Page number (default: 1)
- `limit` (number): Items per page (default: 20)

**Response (200):**
```json
{
  "feeds": [
    {
      "id": "feed_123",
      "url": "https://example.com/feed.xml",
      "title": "Example Blog",
      "description": "A blog about examples",
      "type": "rss",
      "categoryId": "cat_456",
      "icon": "https://example.com/favicon.ico",
      "isActive": true,
      "unreadCount": 5,
      "errorCount": 0,
      "lastFetchedAt": "2024-01-15T09:00:00Z",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 45,
    "hasNext": true
  }
}
```

#### POST /feeds
Subscribe to a new feed.

**Request:**
```json
{
  "url": "https://example.com/feed.xml",
  "categoryId": "cat_456",
  "customTitle": "My Custom Title",
  "isActive": true
}
```

**Response (201):**
```json
{
  "feed": {
    "id": "feed_789",
    "url": "https://example.com/feed.xml",
    "title": "My Custom Title",
    "description": "Discovered description",
    "type": "rss",
    "categoryId": "cat_456",
    "isActive": true,
    "articles": 25
  }
}
```

#### PUT /feeds/{feedId}
Update feed settings.

**Request:**
```json
{
  "title": "Updated Title",
  "categoryId": "cat_789",
  "isActive": false,
  "updateFrequency": 7200
}
```

#### DELETE /feeds/{feedId}
Unsubscribe from feed.

**Response (204):** No content

#### POST /feeds/discover
Discover feeds from URL.

**Request:**
```json
{
  "url": "https://example.com"
}
```

**Response (200):**
```json
{
  "feeds": [
    {
      "url": "https://example.com/feed.xml",
      "title": "Main RSS Feed",
      "type": "rss"
    },
    {
      "url": "https://example.com/feed.json",
      "title": "JSON Feed",
      "type": "json"
    }
  ]
}
```

### Articles

#### GET /articles
Get articles from subscribed feeds.

**Query Parameters:**
- `feedId` (string): Filter by feed
- `categoryId` (string): Filter by category
- `unread` (boolean): Filter unread only
- `starred` (boolean): Filter starred only
- `search` (string): Full-text search
- `before` (ISO date): Articles before date
- `after` (ISO date): Articles after date
- `page` (number): Page number
- `limit` (number): Items per page

**Response (200):**
```json
{
  "articles": [
    {
      "id": "art_123",
      "feedId": "feed_456",
      "guid": "https://example.com/post-123",
      "title": "Article Title",
      "summary": "Article summary...",
      "content": "<p>Full content...</p>",
      "url": "https://example.com/post-123",
      "author": "John Doe",
      "publishedAt": "2024-01-15T08:00:00Z",
      "isRead": false,
      "isStarred": false,
      "readAt": null,
      "tags": ["tech", "news"],
      "aiSummary": "AI generated summary...",
      "sentiment": 0.8,
      "perspectives": {
        "liberal": "Liberal perspective...",
        "conservative": "Conservative perspective..."
      }
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "hasNext": true
  }
}
```

#### GET /articles/{articleId}
Get single article with full content.

**Response (200):**
```json
{
  "article": {
    "id": "art_123",
    "feedId": "feed_456",
    "title": "Article Title",
    "content": "<p>Full extracted content...</p>",
    "fullContent": "<p>Complete article with images...</p>",
    "extractedAt": "2024-01-15T08:30:00Z",
    "readingTime": 5,
    "wordCount": 1200,
    "mainImage": "https://example.com/image.jpg",
    "videos": [],
    "links": [
      {
        "url": "https://example.com",
        "text": "Example Link"
      }
    ]
  }
}
```

#### PUT /articles/{articleId}/read
Mark article as read/unread.

**Request:**
```json
{
  "isRead": true
}
```

#### PUT /articles/{articleId}/star
Star/unstar article.

**Request:**
```json
{
  "isStarred": true
}
```

#### POST /articles/{articleId}/extract
Extract full content from article.

**Response (200):**
```json
{
  "content": "<p>Extracted full content...</p>",
  "title": "Extracted Title",
  "author": "Detected Author",
  "publishedAt": "2024-01-15T08:00:00Z",
  "mainImage": "https://example.com/hero.jpg",
  "success": true
}
```

### Categories

#### GET /categories
Get user's categories.

**Response (200):**
```json
{
  "categories": [
    {
      "id": "cat_123",
      "name": "Technology",
      "parentId": null,
      "color": "#1E40AF",
      "icon": "laptop",
      "sortOrder": 1,
      "feedCount": 15,
      "unreadCount": 45
    }
  ]
}
```

#### POST /categories
Create new category.

**Request:**
```json
{
  "name": "Technology",
  "parentId": "cat_parent",
  "color": "#1E40AF",
  "icon": "laptop"
}
```

### AI Analysis

#### POST /ai/analyze
Analyze article with AI.

**Request:**
```json
{
  "articleId": "art_123",
  "analyses": ["summary", "perspectives", "sentiment", "bias", "factCheck"]
}
```

**Response (200):**
```json
{
  "summary": "Concise AI summary...",
  "perspectives": {
    "liberal": "Liberal viewpoint...",
    "conservative": "Conservative viewpoint...",
    "centrist": "Centrist viewpoint..."
  },
  "sentiment": {
    "score": 0.7,
    "label": "positive"
  },
  "bias": {
    "score": 0.3,
    "direction": "left",
    "confidence": 0.8
  },
  "factCheck": {
    "claims": [
      {
        "text": "GDP grew by 3%",
        "verdict": "true",
        "source": "https://data.gov/gdp"
      }
    ]
  }
}
```

### Market Data

#### GET /market/quotes
Get real-time market quotes.

**Query Parameters:**
- `symbols` (comma-separated): Stock symbols
- `interval` (string): 1m, 5m, 15m, 1h, 1d

**Response (200):**
```json
{
  "quotes": [
    {
      "symbol": "AAPL",
      "price": 185.92,
      "change": 2.15,
      "changePercent": 1.17,
      "volume": 58749382,
      "high": 186.10,
      "low": 184.41,
      "open": 184.41,
      "previousClose": 183.77,
      "timestamp": "2024-01-15T16:00:00Z"
    }
  ]
}
```

### Feed Generation

#### POST /generate/preview
Preview feed generation from URL.

**Request:**
```json
{
  "url": "https://twitter.com/elonmusk",
  "includeFullText": true
}
```

**Response (200):**
```json
{
  "feed": {
    "title": "Elon Musk (@elonmusk)",
    "description": "Twitter feed",
    "url": "https://api.rss-reader.app/generated/twitter-elonmusk.xml"
  },
  "articles": [
    {
      "title": "Recent tweet...",
      "content": "Tweet content...",
      "publishedAt": "2024-01-15T12:00:00Z"
    }
  ],
  "generationTime": 1250
}
```

## WebSocket Events

### Connection
```javascript
const ws = new WebSocket('wss://api.rss-reader.app/v1/ws');
ws.send(JSON.stringify({
  type: 'auth',
  token: 'Bearer eyJhbGc...'
}));
```

### Events

#### article.new
New article in subscribed feed.
```json
{
  "type": "article.new",
  "data": {
    "article": { /* article object */ },
    "feedId": "feed_123"
  }
}
```

#### feed.updated
Feed refresh completed.
```json
{
  "type": "feed.updated",
  "data": {
    "feedId": "feed_123",
    "newArticles": 5,
    "updatedAt": "2024-01-15T10:00:00Z"
  }
}
```

#### sync.conflict
Sync conflict detected.
```json
{
  "type": "sync.conflict",
  "data": {
    "type": "article.read",
    "localValue": true,
    "remoteValue": false,
    "articleId": "art_123"
  }
}
```

## Rate Limits

| Endpoint | Limit | Window |
|----------|-------|--------|
| Authentication | 5 | 15 min |
| Feed Operations | 100 | 1 hour |
| Article Operations | 1000 | 1 hour |
| AI Analysis | 100 | 1 hour |
| Feed Generation | 20 | 1 hour |
| Market Data | 500 | 1 min |

## Error Responses

### 400 Bad Request
```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Validation failed",
    "details": {
      "email": "Invalid email format"
    }
  }
}
```

### 401 Unauthorized
```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid or expired token"
  }
}
```

### 429 Too Many Requests
```json
{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Rate limit exceeded",
    "retryAfter": 3600
  }
}
```

### 500 Internal Server Error
```json
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "An unexpected error occurred",
    "requestId": "req_abc123"
  }
}
```