"use client";

import { Card } from "@/components/ui/card";
import { Id } from "../../../../convex/_generated/dataModel";

interface ActionCardProps {
  actionId: Id<"aiActions">;
  description: string;
  toolName: string;
  status: "pending" | "confirmed" | "rejected";
  onConfirm: (actionId: Id<"aiActions">) => void;
  onReject: (actionId: Id<"aiActions">) => void;
}

const statusStyles = {
  pending: "border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20",
  confirmed: "border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-900/20",
  rejected: "border-zinc-300 bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800",
};

const statusLabels = {
  pending: "Awaiting confirmation",
  confirmed: "Confirmed",
  rejected: "Rejected",
};

export function ActionCard({
  actionId,
  description,
  toolName,
  status,
  onConfirm,
  onReject,
}: ActionCardProps) {
  return (
    <Card className={`p-3 border ${statusStyles[status]}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-zinc-900 dark:text-zinc-100">
            {description}
          </p>
          <p className="mt-0.5 text-xs text-zinc-500 dark:text-zinc-400">
            {toolName} &middot; {statusLabels[status]}
          </p>
        </div>

        {status === "pending" && (
          <div className="flex shrink-0 gap-2">
            <button
              onClick={() => onReject(actionId)}
              className="rounded px-3 py-1.5 text-xs font-medium text-zinc-600 hover:bg-zinc-200 dark:text-zinc-400 dark:hover:bg-zinc-700"
            >
              Reject
            </button>
            <button
              onClick={() => onConfirm(actionId)}
              className="rounded bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700"
            >
              Confirm
            </button>
          </div>
        )}
      </div>
    </Card>
  );
}
