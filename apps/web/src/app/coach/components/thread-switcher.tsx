"use client";

import { useState, useRef, useEffect } from "react";
import { Id } from "../../../../convex/_generated/dataModel";

interface Thread {
  _id: Id<"aiThreads">;
  title?: string;
  updatedAt: number;
}

interface Branch {
  branchId: string;
  createdAt: number;
  messageCount: number;
}

interface ThreadSwitcherProps {
  threads: Thread[];
  activeThreadId: Id<"aiThreads"> | null;
  branches?: Branch[];
  viewingBranchId?: string | null;
  onSwitch: (threadId: Id<"aiThreads">) => void;
  onNew: () => void;
  onArchive: (threadId: Id<"aiThreads">) => void;
  onViewBranch?: (branchId: string) => void;
}

function formatThreadLabel(thread: Thread): string {
  if (thread.title) return thread.title;
  const d = new Date(thread.updatedAt);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffDays = Math.floor(diffMs / 86_400_000);
  if (diffDays === 0) return `Today ${d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`;
  if (diffDays === 1) return "Yesterday";
  if (diffDays < 7) return d.toLocaleDateString([], { weekday: "long" });
  return d.toLocaleDateString([], { month: "short", day: "numeric" });
}

function formatBranchLabel(branch: Branch): string {
  const d = new Date(branch.createdAt);
  const dateStr = d.toLocaleDateString([], { month: "short", day: "numeric" });
  return `Branch · ${dateStr}`;
}

export function ThreadSwitcher({
  threads,
  activeThreadId,
  branches = [],
  viewingBranchId,
  onSwitch,
  onNew,
  onArchive,
  onViewBranch,
}: ThreadSwitcherProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Close on click outside
  useEffect(() => {
    if (!isOpen) return;
    function handleClick(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [isOpen]);

  const activeThread = threads.find((t) => t._id === activeThreadId);
  const label = activeThread ? formatThreadLabel(activeThread) : "New chat";

  return (
    <div className="relative" ref={containerRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800"
      >
        {/* Chat bubble icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="shrink-0 text-zinc-400"
        >
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        </svg>
        <span className="max-w-[180px] truncate">{label}</span>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={`shrink-0 transition-transform ${isOpen ? "rotate-180" : ""}`}
        >
          <path d="m6 9 6 6 6-6" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute left-0 top-full z-50 mt-1 w-72 rounded-lg border border-zinc-200 bg-white shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
          {/* New chat button at top */}
          <div className="border-b border-zinc-200 p-1 dark:border-zinc-700">
            <button
              onClick={() => {
                onNew();
                setIsOpen(false);
              }}
              className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-blue-600 hover:bg-blue-50 dark:text-blue-400 dark:hover:bg-blue-900/30"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M12 5v14" />
                <path d="M5 12h14" />
              </svg>
              New conversation
            </button>
          </div>

          <div className="max-h-72 overflow-y-auto p-1">
            {threads.length === 0 && (
              <p className="px-3 py-4 text-center text-xs text-zinc-400">
                No conversations yet
              </p>
            )}
            {threads.map((thread) => {
              const isActive = thread._id === activeThreadId;
              return (
                <div key={thread._id}>
                  <div
                    className={`group flex items-center justify-between rounded-md px-3 py-2 text-sm ${
                      isActive
                        ? "bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300"
                        : "text-zinc-700 hover:bg-zinc-50 dark:text-zinc-300 dark:hover:bg-zinc-800"
                    }`}
                  >
                    <button
                      onClick={() => {
                        onSwitch(thread._id);
                        setIsOpen(false);
                      }}
                      className="min-w-0 flex-1 truncate text-left"
                    >
                      {formatThreadLabel(thread)}
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onArchive(thread._id);
                      }}
                      className="shrink-0 opacity-0 group-hover:opacity-100 ml-2 text-zinc-400 hover:text-red-500 dark:hover:text-red-400"
                      title="Delete conversation"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        width="14"
                        height="14"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M3 6h18" />
                        <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" />
                      </svg>
                    </button>
                  </div>

                  {/* Branches for the active thread */}
                  {isActive && branches.length > 0 && (
                    <div className="ml-5 border-l border-zinc-200 dark:border-zinc-700">
                      {branches.map((branch) => (
                        <button
                          key={branch.branchId}
                          onClick={() => {
                            onViewBranch?.(branch.branchId);
                            setIsOpen(false);
                          }}
                          className={`flex w-full items-center gap-2 rounded-md px-3 py-1.5 text-xs ${
                            viewingBranchId === branch.branchId
                              ? "bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300"
                              : "text-zinc-500 hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
                          }`}
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="12"
                            height="12"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            className="shrink-0"
                          >
                            <line x1="6" y1="3" x2="6" y2="15" />
                            <circle cx="18" cy="6" r="3" />
                            <circle cx="6" cy="18" r="3" />
                            <path d="M18 9a9 9 0 0 1-9 9" />
                          </svg>
                          <span className="truncate">
                            {formatBranchLabel(branch)}
                          </span>
                          <span className="shrink-0 text-zinc-400">
                            {branch.messageCount}
                          </span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
