"use client";

import { useState } from "react";
import { ComposedChart, Line, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend } from "recharts";
import { convertWeightForDisplay } from "@/lib/units";

type ExerciseProgressData = {
  date: number;
  weight: number;
  volume: number;
};

type TimeRange = "1M" | "3M" | "All";

export function ExerciseProgressChart({
  weightData,
  volumeData,
  unit,
}: {
  weightData: { date: number; weight: number }[];
  volumeData: { date: number; volume: number }[];
  unit: "metric" | "imperial";
}) {
  const [timeRange, setTimeRange] = useState<TimeRange>("3M");

  // Merge weight and volume data by date
  const dateMap = new Map<number, { weight: number; volume: number }>();

  for (const item of weightData) {
    dateMap.set(item.date, { weight: item.weight, volume: 0 });
  }
  for (const item of volumeData) {
    const existing = dateMap.get(item.date);
    if (existing) {
      existing.volume = item.volume;
    } else {
      dateMap.set(item.date, { weight: 0, volume: item.volume });
    }
  }

  const allChartData = Array.from(dateMap.entries())
    .sort(([a], [b]) => a - b)
    .map(([date, values]) => ({
      timestamp: date,
      date: new Date(date).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      weight: convertWeightForDisplay(values.weight, unit),
      volume: Math.round(convertWeightForDisplay(values.volume, unit)),
    }));

  // Filter data based on time range
  const now = Date.now();
  const cutoffTime =
    timeRange === "1M" ? now - 30 * 24 * 60 * 60 * 1000 :
    timeRange === "3M" ? now - 90 * 24 * 60 * 60 * 1000 :
    0;

  const chartData = timeRange === "All"
    ? allChartData
    : allChartData.filter(d => d.timestamp >= cutoffTime);

  const unitLabel = unit === "metric" ? "kg" : "lbs";
  const manyPoints = chartData.length > 12;

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <div className="inline-flex items-center rounded-full bg-zinc-100 dark:bg-zinc-800 p-1">
          {(["1M", "3M", "All"] as TimeRange[]).map((range) => (
            <button
              key={range}
              onClick={() => setTimeRange(range)}
              className={`px-3 py-1 text-xs font-medium rounded-full transition-colors ${
                timeRange === range
                  ? "bg-blue-500 text-white"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {range}
            </button>
          ))}
        </div>
      </div>

      <div className="h-64 w-full">
        <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 30 }}>
          <XAxis
            dataKey="date"
            axisLine={false}
            tickLine={false}
            tick={{ fill: "#9ca3af", fontSize: 10 }}
            angle={-35}
            textAnchor="end"
            interval={manyPoints ? Math.floor(chartData.length / 5) : "preserveStartEnd"}
            height={50}
          />
          <YAxis
            yAxisId="volume"
            orientation="right"
            axisLine={false}
            tickLine={false}
            tick={{ fill: "#d1d5db", fontSize: 10 }}
            tickFormatter={(v) => `${v}`}
          />
          <YAxis
            yAxisId="weight"
            orientation="left"
            axisLine={false}
            tickLine={false}
            tick={{ fill: "#9ca3af", fontSize: 11 }}
            tickFormatter={(v) => `${v}`}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: "#fff",
              border: "1px solid #e5e7eb",
              borderRadius: "8px",
              fontSize: 12,
            }}
            formatter={(value: number | undefined, name: string | undefined) => [
              `${value ?? 0} ${unitLabel}`,
              name === "weight" ? "Max Weight" : "Volume",
            ]}
          />
          <Legend
            wrapperStyle={{ fontSize: 11 }}
            formatter={(value) => (value === "weight" ? "Max Weight" : "Volume")}
          />
          <Bar
            yAxisId="volume"
            dataKey="volume"
            fill="#e0e7ff"
            radius={[4, 4, 0, 0]}
          />
          <Line
            yAxisId="weight"
            type="monotone"
            dataKey="weight"
            stroke="#3b82f6"
            strokeWidth={2}
            dot={manyPoints ? false : { fill: "#3b82f6", r: 4 }}
            activeDot={{ r: 6 }}
            connectNulls
          />
        </ComposedChart>
      </ResponsiveContainer>
      </div>
    </div>
  );
}
