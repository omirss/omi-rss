#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building Omi RSS web UI..."

(cd app && flutter build web --release --no-wasm-dry-run)

echo "Copying build output to server/web-ui..."
rm -rf server/web-ui
mkdir -p server/web-ui
cp -R app/build/web/. server/web-ui/

echo "Done."
echo "Next steps:"
echo "  dev:  docker compose -f server/docker-compose.yml up --build"
echo "  prod: docker compose -f server/docker-compose.prod.yml up -d"
echo "  The web UI is served by nginx at / (bind-mounted into /var/www/html);"
echo "  the API stays at /api and /health."
