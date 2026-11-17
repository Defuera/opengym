const CONVEX_URL = "https://wary-mockingbird-65.eu-west-1.convex.cloud";

async function callMutation(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/mutation`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(`${name}: ${JSON.stringify(data)}`);
  return data.value;
}

const sessions = [
  {
    date: new Date("2026-02-19T12:00:00Z").getTime(),
    status: "completed",
    exercises: [
      { name: "Leg Press", muscleGroup: "Legs", order: 0, sets: [
        { reps: 12, weight: 60, order: 0 }, { reps: 12, weight: 80, order: 1 },
        { reps: 12, weight: 100, order: 2 }, { reps: 15, weight: 130, order: 3 },
      ]},
      { name: "Biceps Curl", muscleGroup: "Arms", order: 1, sets: [
        { reps: 12, weight: 15, order: 0 }, { reps: 12, weight: 15, order: 1 },
        { reps: 20, weight: 15, order: 2 }, { reps: 20, weight: 15, order: 3 },
      ]},
      { name: "Adductors", muscleGroup: "Legs", order: 2, sets: [
        { reps: 15, weight: 35, order: 0 }, { reps: 12, weight: 30, order: 1 },
        { reps: 15, weight: 25, order: 2 },
      ]},
      { name: "Low Row", muscleGroup: "Back", order: 3, sets: [
        { reps: 12, weight: 35, order: 0 }, { reps: 12, weight: 30, order: 1 },
        { reps: 12, weight: 30, order: 2 },
      ]},
    ],
  },
  {
    date: new Date("2026-02-20T12:00:00Z").getTime(),
    status: "completed",
    exercises: [
      { name: "Bench Press", muscleGroup: "Chest", order: 0, sets: [
        { reps: 8, weight: 20, order: 0 }, { reps: 6, weight: 40, order: 1 },
        { reps: 6, weight: 60, order: 2 }, { reps: 8, weight: 70, order: 3 },
        { reps: 8, weight: 65, order: 4 },
      ]},
      { name: "Triceps Rope Pull-Down", muscleGroup: "Arms", order: 1, sets: [
        { reps: 12, weight: 12.5, order: 0 }, { reps: 15, weight: 15, order: 1 },
        { reps: 15, weight: 17, order: 2 }, { reps: 15, weight: 12.5, order: 3 },
      ]},
      { name: "Lat Rope Pull-Down", muscleGroup: "Back", order: 2, sets: [
        { reps: 12, weight: 45, order: 0 }, { reps: 12, weight: 55, order: 1 },
        { reps: 12, weight: 60, order: 2 }, { reps: 12, weight: 50, order: 3 },
      ]},
      { name: "Dips", muscleGroup: "Chest", order: 3, sets: [
        { reps: 12, weight: 0, order: 0 }, { reps: 11, weight: 0, order: 1 },
        { reps: 9, weight: 0, order: 2 },
      ]},
    ],
  },
];

async function main() {
  const userId = await callMutation("users:getOrCreateDefaultUser", {});
  for (const s of sessions) {
    const id = await callMutation("sessions:create", { userId, ...s });
    const date = new Date(s.date).toISOString().slice(0, 10);
    console.log(`✓ ${date} — ${s.exercises.length} exercises → ${id}`);
  }
  console.log("Done.");
}

main().catch(console.error);
