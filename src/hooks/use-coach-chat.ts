"use client";

import { useState, useCallback } from "react";
import { useQuery, useMutation, useAction } from "convex/react";
import { api } from "../../convex/_generated/api";
import { Id } from "../../convex/_generated/dataModel";

export function useCoachChat(userId: Id<"users"> | undefined) {
  const [activeThreadId, setActiveThreadId] = useState<Id<"aiThreads"> | null>(
    null
  );
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const getOrCreateThread = useMutation(api.aiThreads.getOrCreateThread);
  const createThread = useMutation(api.aiThreads.createThread);
  const archiveThreadMut = useMutation(api.aiThreads.archiveThread);
  const softDeleteFrom = useMutation(api.aiMessages.softDeleteFrom);
  const confirmActionFn = useAction(api.aiActions.confirmAction);
  const rejectActionFn = useAction(api.aiActions.rejectAction);

  const threads = useQuery(
    api.aiThreads.listThreads,
    userId ? { userId } : "skip"
  );

  const messages = useQuery(
    api.aiMessages.listMessages,
    activeThreadId ? { threadId: activeThreadId } : "skip"
  );

  const actions = useQuery(
    api.aiActions.listByThread,
    activeThreadId ? { threadId: activeThreadId } : "skip"
  );

  const ensureThread = useCallback(async (): Promise<Id<"aiThreads">> => {
    if (activeThreadId) return activeThreadId;
    if (!userId) throw new Error("No user");
    const threadId = await getOrCreateThread({ userId });
    setActiveThreadId(threadId);
    return threadId;
  }, [activeThreadId, userId, getOrCreateThread]);

  const sendMessage = useCallback(
    async (content: string) => {
      if (!content.trim() || isLoading) return;
      setIsLoading(true);
      setError(null);

      try {
        const threadId = await ensureThread();

        const response = await fetch("/api/coach/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ threadId, message: content.trim() }),
        });

        if (!response.ok) {
          const errorData = await response.json();
          throw new Error(errorData.error || "Failed to get response");
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "Something went wrong");
      } finally {
        setIsLoading(false);
      }
    },
    [isLoading, ensureThread]
  );

  const editMessage = useCallback(
    async (messageId: Id<"aiMessages">, newContent: string) => {
      if (!activeThreadId) return;
      setError(null);

      try {
        // Soft-delete from the edited message onward
        await softDeleteFrom({ messageId });

        // Re-send with new content
        await sendMessage(newContent);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Something went wrong");
      }
    },
    [activeThreadId, softDeleteFrom, sendMessage]
  );

  const startNewThread = useCallback(async () => {
    if (!userId) return;
    const threadId = await createThread({ userId });
    setActiveThreadId(threadId);
  }, [userId, createThread]);

  const switchThread = useCallback((threadId: Id<"aiThreads">) => {
    setActiveThreadId(threadId);
  }, []);

  const archiveThread = useCallback(
    async (threadId: Id<"aiThreads">) => {
      await archiveThreadMut({ threadId });
      if (activeThreadId === threadId) {
        setActiveThreadId(null);
      }
    },
    [activeThreadId, archiveThreadMut]
  );

  const confirmAction = useCallback(
    async (actionId: Id<"aiActions">) => {
      try {
        await confirmActionFn({ actionId });
      } catch (err) {
        setError(err instanceof Error ? err.message : "Action failed");
      }
    },
    [confirmActionFn]
  );

  const rejectAction = useCallback(
    async (actionId: Id<"aiActions">) => {
      try {
        await rejectActionFn({ actionId });
      } catch (err) {
        setError(err instanceof Error ? err.message : "Rejection failed");
      }
    },
    [rejectActionFn]
  );

  return {
    activeThreadId,
    threads: threads ?? [],
    messages: messages ?? [],
    actions: actions ?? [],
    isLoading,
    error,
    sendMessage,
    editMessage,
    startNewThread,
    switchThread,
    archiveThread,
    confirmAction,
    rejectAction,
    ensureThread,
  };
}
