# AI Session Planning

This document describes the AI-powered session planning feature in OpenGym.

## Overview

The AI session planner uses OpenAI to generate personalized workout sessions based on:
- User profile and preferences
- Recent workout history
- AI memories (preferences, constraints, injuries, etc.)
- Specified training goal

## Architecture

The AI planner is wired into the session creation flow with the following components:

1. **AI Module** (`src/lib/ai/`)
   - Provider-agnostic AI interface
   - OpenAI client implementation
   - Planner, chat, and memory manager services

2. **Server Helper** (`src/server/aiSessionPlanner.ts`)
   - Server-side orchestration (not currently used, kept for future patterns)
   - Fetches user context and calls AI planner

3. **Convex Action** (`convex/aiSessionPlanner.ts`)
   - Serverless action that runs in Node.js environment
   - Fetches user context from Convex
   - Calls AI planner with user data
   - Creates session with proposed exercises

4. **API Route** (`src/app/api/sessions/propose/route.ts`)
   - Entry point for session creation
   - Uses AI planner when `NEXT_PUBLIC_AI_ENABLED=true`
   - Falls back to rule-based proposer on failure or when disabled

## Enabling AI Planning

To enable AI-powered session planning, set the following environment variables:

```bash
# Enable AI features
NEXT_PUBLIC_AI_ENABLED=true

# OpenAI API key (required when AI is enabled)
OPENAI_API_KEY=sk-...

# Convex URL (should already be set)
NEXT_PUBLIC_CONVEX_URL=https://your-deployment.convex.cloud
```

## Flow

1. User clicks "Start New Session" button
2. Client calls `/api/sessions/propose` endpoint
3. If AI is enabled:
   - API route calls Convex action `aiSessionPlanner.planAndCreateSession`
   - Action fetches user context (profile, recent sessions, memories)
   - Action calls AI planner with context
   - Action creates session with AI-proposed exercises
   - Returns session to client
4. If AI is disabled or fails:
   - Falls back to rule-based session proposer
   - Uses simple push/pull/legs rotation logic

## Testing

To test the AI planner:

1. Set environment variables in `.env.local`
2. Ensure Convex is running (`npx convex dev`)
3. Start the Next.js dev server (`npm run dev`)
4. Click "Start New Session" on the home page
5. Check console logs to see if AI planner was used

## Limitations

- AI planner requires valid OpenAI API key
- Muscle group inference is basic (uses keyword matching)
- No exercise database yet - relies on AI to know exercises
- No UI for editing plans via chat (future enhancement)

## Future Enhancements

- Exercise database with muscle groups and equipment
- Chat interface for adjusting session plans
- Session summary with AI-generated insights
- Memory extraction from chat conversations
- Progressive overload recommendations
