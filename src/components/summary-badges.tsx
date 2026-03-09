const trendLabels: Record<string, { label: string; className: string }> = {
  improving: { label: "Improving", className: "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300" },
  stable: { label: "Stable", className: "bg-blue-100 text-blue-700 dark:bg-blue-900/50 dark:text-blue-300" },
  declining: { label: "Declining", className: "bg-amber-100 text-amber-700 dark:bg-amber-900/50 dark:text-amber-300" },
  insufficient_data: { label: "New", className: "bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400" },
};

export function TrendBadge({ trend }: { trend: string }) {
  const info = trendLabels[trend] ?? trendLabels.insufficient_data;
  return (
    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${info.className}`}>
      {info.label}
    </span>
  );
}

export function ScorePill({ score }: { score: number }) {
  const s10 = Math.round(score / 10);
  let cls = "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300";
  if (s10 < 7) cls = "bg-amber-100 text-amber-700 dark:bg-amber-900/50 dark:text-amber-300";
  if (s10 < 4) cls = "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300";
  return (
    <span className={`text-sm font-semibold px-2 py-0.5 rounded-full ${cls}`}>
      {s10}/10
    </span>
  );
}
