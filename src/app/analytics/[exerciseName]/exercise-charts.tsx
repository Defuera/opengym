"use client";

import { ComposedChart, Line, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend } from "recharts";
import { convertWeightForDisplay } from "@/lib/units";

type ExerciseProgressData = {
  date: number;
  weight: number;
  volume: number;
};

export function ExerciseProgressChart({
  weightData,
  volumeData,
  unit,
}: {
  weightData: { date: number; weight: number }[];
  volumeData: { date: number; volume: number }[];
  unit: "metric" | "imperial";
}) {
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

  const chartData = Array.from(dateMap.entries())
    .sort(([a], [b]) => a - b)
    .map(([date, values]) => ({
      date: new Date(date).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      weight: convertWeightForDisplay(values.weight, unit),
      volume: Math.round(convertWeightForDisplay(values.volume, unit)),
    }));

  const unitLabel = unit === "metric" ? "kg" : "lbs";

  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 10 }}>
          <XAxis
            dataKey="date"
            axisLine={false}
            tickLine={false}
            tick={{ fill: "#9ca3af", fontSize: 11 }}
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
            formatter={(value: number, name: string) => [
              `${value} ${unitLabel}`,
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
            dot={{ fill: "#3b82f6", r: 4 }}
            activeDot={{ r: 6 }}
            connectNulls
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
