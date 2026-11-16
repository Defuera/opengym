"use client";

import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Cell } from "recharts";
import { convertWeightForDisplay } from "@/lib/units";

type WeeklyTrend = {
  week: number;
  volume: number;
  sessionCount: number;
};

export function AnalyticsCharts({
  data,
  unit,
}: {
  data: WeeklyTrend[];
  unit: "metric" | "imperial";
}) {
  const chartData = data.map((item) => ({
    week: `W${item.week}`,
    volume: Math.round(convertWeightForDisplay(item.volume, unit)),
  }));

  const maxVolume = Math.max(...chartData.map((d) => d.volume), 1);

  return (
    <div className="h-48 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
          <XAxis
            dataKey="week"
            axisLine={false}
            tickLine={false}
            tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
          />
          <YAxis
            axisLine={false}
            tickLine={false}
            tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
            tickFormatter={(value) => `${value}`}
          />
          <Bar dataKey="volume" radius={[4, 4, 0, 0]}>
            {chartData.map((entry, index) => (
              <Cell
                key={`cell-${index}`}
                fill={index === chartData.length - 1 ? "hsl(var(--primary))" : "hsl(var(--muted))"}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
