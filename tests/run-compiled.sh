#!/bin/bash
# Simple test runner that compiles TypeScript and runs with node

set -e

echo "🔨 Compiling tests..."
npx tsc tests/session-flow-simple.test.ts --outDir dist/tests --module commonjs --moduleResolution node --esModuleInterop --resolveJsonModule --skipLibCheck --target ES2020 >/dev/null 2>&1

# Copy Convex generated files
mkdir -p dist/tests/convex
cp -r convex/_generated dist/tests/convex/

echo "🧪 Running Session Flow Integration Tests"
echo ""

# Load environment variables and run test
cd /home/node/.openclaw/workspace/opengym

# Load environment variables directly
export NEXT_PUBLIC_CONVEX_URL=$(grep NEXT_PUBLIC_CONVEX_URL .env.local | cut -d '=' -f2 | sed 's/#.*//' | tr -d ' ')

if [ -z "$NEXT_PUBLIC_CONVEX_URL" ]; then
  export NEXT_PUBLIC_CONVEX_URL=$(grep NEXT_PUBLIC_CONVEX_URL .env | cut -d '=' -f2 | sed 's/#.*//' | tr -d ' ')
fi

if [ -z "$NEXT_PUBLIC_CONVEX_URL" ]; then
  echo "❌ NEXT_PUBLIC_CONVEX_URL not found in .env.local or .env"
  exit 1
fi

NODE_ENV=test node dist/tests/tests/session-flow-simple.test.js

exit_code=$?

# Cleanup
rm -rf dist/tests

if [ $exit_code -eq 0 ]; then
  echo ""
  echo "✅ All tests passed!"
else
  echo ""
  echo "❌ Tests failed with code $exit_code"
fi

exit $exit_code
