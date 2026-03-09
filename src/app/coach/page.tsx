"use client";

import { useRef, useEffect } from "react";
import { useQuery } from "convex/react";
import { api } from "../../../convex/_generated/api";
import { Card } from "@/components/ui/card";
import { useCoachChat } from "@/hooks/use-coach-chat";
import { ChatMessage } from "./components/chat-message";
import { ActionCard } from "./components/action-card";
import { ThreadSwitcher } from "./components/thread-switcher";
import { ChatInput } from "./components/chat-input";

export default function CoachPage() {
  const user = useQuery(api.users.getDefaultUser, {});
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const {
    activeThreadId,
    threads,
    messages,
    actions,
    branches,
    branchMessages,
    viewingBranchId,
    isLoading,
    error,
    sendMessage,
    editMessage,
    startNewThread,
    switchThread,
    archiveThread,
    viewBranch,
    closeBranch,
    confirmAction,
    rejectAction,
    ensureThread,
  } = useCoachChat(user?._id);

  // Auto-initialize thread when user loads
  useEffect(() => {
    if (user && !activeThreadId) {
      ensureThread();
    }
  }, [user, activeThreadId, ensureThread]);

  // Scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, actions]);

  // Group actions by messageId for inline rendering
  const actionsByMessage = new Map<string, typeof actions>();
  for (const action of actions) {
    const key = action.messageId as string;
    const existing = actionsByMessage.get(key) ?? [];
    existing.push(action);
    actionsByMessage.set(key, existing);
  }

  return (
    <div className="flex h-full flex-col bg-zinc-50 dark:bg-zinc-950">
      {/* Header with thread switcher — pinned */}
      <div className="shrink-0 border-b bg-white/95 px-4 py-2 backdrop-blur-lg dark:bg-zinc-900/95">
        <div className="mx-auto flex max-w-2xl items-center justify-between">
          <ThreadSwitcher
            threads={threads}
            activeThreadId={activeThreadId}
            branches={branches}
            viewingBranchId={viewingBranchId}
            onSwitch={switchThread}
            onNew={startNewThread}
            onArchive={archiveThread}
            onViewBranch={viewBranch}
          />
        </div>
      </div>

      {viewingBranchId && (
        <div className="shrink-0 border-b border-amber-200 bg-amber-50 px-4 py-2 dark:border-amber-800 dark:bg-amber-900/20">
          <div className="mx-auto flex max-w-2xl items-center justify-between">
            <p className="text-sm text-amber-700 dark:text-amber-300">
              Viewing previous version
            </p>
            <button
              onClick={closeBranch}
              className="rounded-md px-3 py-1 text-sm font-medium text-amber-700 hover:bg-amber-100 dark:text-amber-300 dark:hover:bg-amber-800/40"
            >
              Back to current
            </button>
          </div>
        </div>
      )}

      <main className="flex-1 overflow-y-auto px-4 py-4">
        <div className="mx-auto max-w-2xl space-y-4">
          {!viewingBranchId && messages.length === 0 && !isLoading && (
            <Card className="p-6 text-center">
              <p className="text-zinc-600 dark:text-zinc-400">
                Ask your AI coach anything about your training, form, nutrition,
                or recovery.
              </p>
            </Card>
          )}

          {viewingBranchId
            ? branchMessages.map((msg) => (
                <div key={msg._id}>
                  <ChatMessage
                    id={msg._id}
                    role={msg.role}
                    content={msg.content}
                  />
                </div>
              ))
            : messages.map((msg) => (
                <div key={msg._id}>
                  <ChatMessage
                    id={msg._id}
                    role={msg.role}
                    content={msg.content}
                    onEdit={msg.role === "user" ? editMessage : undefined}
                  />

                  {/* Render actions inline after their assistant message */}
                  {msg.role === "assistant" &&
                    actionsByMessage.get(msg._id as string)?.map((action) => (
                      <div key={action._id} className="mt-2 ml-0">
                        <ActionCard
                          actionId={action._id}
                          description={action.description}
                          toolName={action.toolName}
                          status={action.status}
                          onConfirm={confirmAction}
                          onReject={rejectAction}
                        />
                      </div>
                    ))}
                </div>
              ))}

          {!viewingBranchId && isLoading && (
            <div className="flex justify-start">
              <Card className="max-w-[85%] p-4 bg-white dark:bg-zinc-800">
                <p className="text-sm text-zinc-500 dark:text-zinc-400">
                  Coach is thinking...
                </p>
              </Card>
            </div>
          )}

          {!viewingBranchId && error && (
            <Card className="p-4 bg-red-50 border-red-200 dark:bg-red-900/20 dark:border-red-800">
              <p className="text-sm text-red-700 dark:text-red-400">{error}</p>
            </Card>
          )}

          <div ref={messagesEndRef} />
        </div>
      </main>

      {!viewingBranchId && (
        <div className="shrink-0 border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
          <div className="mx-auto max-w-2xl">
            <ChatInput onSend={sendMessage} disabled={isLoading} />
          </div>
        </div>
      )}
    </div>
  );
}
