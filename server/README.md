# Omi RSS Server (Node.js)

A powerful RSS reader backend server built with Node.js, Express, and TypeScript, providing a comprehensive API for the Omi RSS Reader application.

## Features

- **Feed Management**: Subscribe, manage, and sync RSS/Atom feeds
- **User Authentication**: JWT-based auth with refresh tokens
- **Real-time Updates**: Socket.IO for live notifications
- **Background Jobs**: Feed updates with Bull queue
- **Database**: PostgreSQL with Drizzle ORM
- **Caching**: Redis for performance
- **File Storage**: Avatar uploads with Sharp
- **Rate Limiting**: Protect API endpoints
- **AI Integration**: Prepared for GPT/Claude/Gemini (Phase 8)
- **Market Data**: Ready for financial feeds (Phase 9)

## Tech Stack

- **Runtime**: Node.js 18+
- **Framework**: Express.js with TypeScript
- **Database**: PostgreSQL with Drizzle ORM
- **Cache**: Redis
- **Queue**: Bull for background jobs
- **WebSocket**: Socket.IO
- **Authentication**: JWT with bcrypt
- **Validation**: Zod
- **Logging**: Winston

## Prerequisites

- Node.js >= 18.0.0
- PostgreSQL >= 14
- Redis >= 6
- npm or yarn

## Quick Start

### 1. Clone and Install

```bash
cd omi_rss_server
npm install
```

### 2. Environment Setup

Create a `.env` file:

```env
# Server
NODE_ENV=development
PORT=3000

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/omi_rss_db

# Redis
REDIS_URL=redis://localhost:6379

# Authentication
JWT_SECRET=your-super-secret-jwt-key
JWT_REFRESH_SECRET=your-super-secret-refresh-key
BCRYPT_ROUNDS=10

# Email (for notifications)
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USER=your-email@gmail.com
EMAIL_PASS=your-app-password
EMAIL_FROM=noreply@omirss.com

# CORS
CORS_ORIGIN=http://localhost:3001

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# Logging
LOG_LEVEL=info
LOG_DIR=./logs

# Uploads
UPLOAD_DIR=./uploads
```

### 3. Database Setup

```bash
# Run migrations
npm run db:generate
npm run db:push
npm run db:migrate

# Seed demo data (optional)
npm run db:seed
```

### 4. Start Development Server

```bash
npm run dev
```

The server will start on http://localhost:3000

## Docker Development

Use Docker Compose for a complete development environment:

```bash
docker-compose up -d
```

This starts:
- PostgreSQL on port 5432
- Redis on port 6379
- Node.js server on port 3000
- pgAdmin on port 5050
- Redis Commander on port 8081

## API Documentation

### Authentication

```http
POST /api/auth/register
POST /api/auth/login
POST /api/auth/logout
POST /api/auth/refresh
POST /api/auth/verify-email
POST /api/auth/forgot-password
POST /api/auth/reset-password
```

### User Management

```http
GET    /api/users/me
PUT    /api/users/me
PUT    /api/users/me/password
POST   /api/users/me/avatar
PUT    /api/users/me/settings
DELETE /api/users/me
```

### Feed Management

```http
GET    /api/feeds
GET    /api/feeds/:feedId
POST   /api/feeds
PUT    /api/feeds/:feedId
DELETE /api/feeds/:feedId
POST   /api/feeds/:feedId/refresh
POST   /api/feeds/:feedId/mark-all-read
```

### Article Management

```http
GET    /api/articles
GET    /api/articles/:articleId
PUT    /api/articles/:articleId/state
POST   /api/articles/batch-update
POST   /api/articles/mark-all-read
```

### Folder Management

```http
GET    /api/folders
GET    /api/folders/:folderId
POST   /api/folders
PUT    /api/folders/:folderId
DELETE /api/folders/:folderId
POST   /api/folders/reorder
```

### Sync & Devices

```http
GET    /api/sync/devices
POST   /api/sync/devices
DELETE /api/sync/devices/:deviceId
GET    /api/sync/status
POST   /api/sync/sync
GET    /api/sync/history
```

### Statistics

```http
GET    /api/stats/overview
GET    /api/stats/history
GET    /api/stats/reading-time
GET    /api/stats/tags
POST   /api/stats/reading-time
```

### Notifications

```http
GET    /api/notifications
GET    /api/notifications/preferences
PUT    /api/notifications/preferences
POST   /api/notifications/mark-read
DELETE /api/notifications/:notificationId
POST   /api/notifications/test-push
```

### AI Features (Phase 8)

```http
POST   /api/ai/summarize
POST   /api/ai/analyze
POST   /api/ai/generate
GET    /api/ai/usage
GET    /api/ai/models
```

### Market Data (Phase 9)

```http
GET    /api/market/overview
GET    /api/market/watchlist
PUT    /api/market/watchlist
GET    /api/market/alerts
POST   /api/market/alerts
DELETE /api/market/alerts/:alertId
GET    /api/market/symbols/:symbol
GET    /api/market/search
```

## WebSocket Events

Connect to `ws://localhost:3000` with Socket.IO client.

### Events

- `notification` - Real-time notifications
- `sync:changes` - Cross-device sync updates
- `feed:updated` - Feed refresh notifications
- `market:update` - Market data updates (Phase 9)

## Background Jobs

The server runs background workers for:

- **Feed Updates**: Periodic RSS feed fetching
- **Email Sending**: Async email delivery
- **Notifications**: Push notification delivery
- **Data Cleanup**: Old data purging

## Project Structure

```
omi_rss_server/
├── src/
│   ├── routes/          # API route handlers
│   ├── middleware/      # Express middleware
│   ├── services/        # Business logic
│   ├── database/        # Database schema & migrations
│   ├── workers/         # Background job processors
│   ├── utils/           # Helper utilities
│   └── server.ts        # Main server file
├── drizzle/             # Database migrations
├── uploads/             # User uploads
├── logs/                # Application logs
├── docker-compose.yml   # Docker development setup
├── package.json         # Dependencies
└── tsconfig.json        # TypeScript config
```

## Scripts

```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm run lint         # Run ESLint
npm run test         # Run tests
npm run db:generate  # Generate migrations
npm run db:push      # Push schema changes
npm run db:migrate   # Run migrations
npm run db:seed      # Seed demo data
npm run db:studio    # Open Drizzle Studio
```

## Security

- JWT tokens with refresh mechanism
- Password hashing with bcrypt
- Rate limiting per IP
- Input validation with Zod
- SQL injection protection via Drizzle ORM
- XSS protection with Helmet
- CORS configuration

## Performance

- Database connection pooling
- Redis caching for hot data
- Indexed database queries
- Lazy loading for large datasets
- Background job processing
- Response compression

## Monitoring

- Structured logging with Winston
- Request ID tracking
- Error reporting
- Performance metrics
- Health check endpoint at `/health`

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT