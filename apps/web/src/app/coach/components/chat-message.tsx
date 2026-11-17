"use client";

import { useState } from "react";
import ReactMarkdown from "react-markdown";
import { Card } from "@/components/ui/card";
import { Id } from "../../../../convex/_generated/dataModel";

interface ChatMessageProps {
  id: Id<"aiMessages">;
  role: "user" | "assistant";
  content: string;
  onEdit?: (messageId: Id<"aiMessages">, newContent: string) => void;
}

export function ChatMessage({ id, role, content, onEdit }: ChatMessageProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [editContent, setEditContent] = useState(content);

  const handleSubmitEdit = () => {
    if (editContent.trim() && onEdit) {
      onEdit(id, editContent.trim());
      setIsEditing(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmitEdit();
    }
    if (e.key === "Escape") {
      setIsEditing(false);
      setEditContent(content);
    }
  };

  if (role === "user" && isEditing) {
    return (
      <div className="flex justify-end">
        <div className="max-w-[85%] space-y-2">
          <textarea
            value={editContent}
            onChange={(e) => setEditContent(e.target.value)}
            onKeyDown={handleKeyDown}
            className="w-full resize-none rounded-lg border border-blue-400 bg-white px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 dark:border-blue-600 dark:bg-zinc-800 dark:text-zinc-50"
            rows={3}
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <button
              onClick={() => {
                setIsEditing(false);
                setEditContent(content);
              }}
              className="rounded px-3 py-1 text-xs text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmitEdit}
              className="rounded bg-blue-600 px-3 py-1 text-xs text-white hover:bg-blue-700"
            >
              Save & resend
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={`flex ${role === "user" ? "justify-end" : "justify-start"}`}>
      <Card
        className={`group relative max-w-[85%] p-4 ${
          role === "user"
            ? "bg-blue-600 text-white"
            : "bg-white dark:bg-zinc-800"
        }`}
      >
        {role === "user" && onEdit && (
          <button
            onClick={() => setIsEditing(true)}
            className="absolute -left-8 top-1/2 -translate-y-1/2 opacity-0 transition-opacity group-hover:opacity-100 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300"
            title="Edit message"
          >
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
            >
              <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
              <path d="m15 5 4 4" />
            </svg>
          </button>
        )}

        {role === "assistant" ? (
          <div
            className="prose prose-sm dark:prose-invert max-w-none text-sm"
            style={{ lineHeight: "1.6" }}
          >
            <ReactMarkdown
              components={{
                p: ({ children }) => (
                  <p className="mb-2 last:mb-0">{children}</p>
                ),
                ul: ({ children }) => (
                  <ul className="mb-2 list-disc pl-4">{children}</ul>
                ),
                ol: ({ children }) => (
                  <ol className="mb-2 list-decimal pl-4">{children}</ol>
                ),
                li: ({ children }) => (
                  <li className="mb-0.5">{children}</li>
                ),
                strong: ({ children }) => (
                  <strong className="font-semibold">{children}</strong>
                ),
                h1: ({ children }) => (
                  <h1 className="mb-2 mt-3 text-base font-bold first:mt-0">
                    {children}
                  </h1>
                ),
                h2: ({ children }) => (
                  <h2 className="mb-2 mt-3 text-sm font-bold first:mt-0">
                    {children}
                  </h2>
                ),
                h3: ({ children }) => (
                  <h3 className="mb-1 mt-2 text-sm font-semibold first:mt-0">
                    {children}
                  </h3>
                ),
                code: ({ children }) => (
                  <code className="rounded bg-zinc-100 px-1 py-0.5 text-xs dark:bg-zinc-700">
                    {children}
                  </code>
                ),
                blockquote: ({ children }) => (
                  <blockquote className="border-l-2 border-zinc-300 pl-3 italic dark:border-zinc-600">
                    {children}
                  </blockquote>
                ),
              }}
            >
              {content}
            </ReactMarkdown>
          </div>
        ) : (
          <p className="whitespace-pre-wrap text-sm">{content}</p>
        )}
      </Card>
    </div>
  );
}
