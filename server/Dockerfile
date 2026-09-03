# Build stage
FROM node:18-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy source code
COPY src ./src
COPY drizzle ./drizzle

# Install dev dependencies for building
RUN npm ci && \
    npm run build && \
    npm prune --production

# Production stage
FROM node:18-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    redis \
    curl \
    tzdata

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy built application
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Copy additional files
COPY --chown=nodejs:nodejs drizzle ./drizzle

# Create required directories
RUN mkdir -p uploads/avatars uploads/exports logs && \
    chown -R nodejs:nodejs uploads logs

# Switch to non-root user
USER nodejs

# Environment variables
ENV NODE_ENV=production \
    PORT=3000

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "dist/server.js"]