// Seed script: creates 12 completed sessions with realistic workout data
const CONVEX_URL = "https://wary-mockingbird-65.eu-west-1.convex.cloud";

async function callMutation(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/mutation`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(JSON.stringify(data));
  return data.value;
}

async function callQuery(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/query`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(JSON.stringify(data));
  return data.value;
}

const workouts = [
  {
    name: "Push Day",
    exercises: [
      { name: "Bench Press", muscleGroup: "Chest", sets: [{ r: 8, w: 80 }, { r: 8, w: 85 }, { r: 6, w: 90 }] },
      { name: "Overhead Press", muscleGroup: "Shoulders", sets: [{ r: 10, w: 40 }, { r: 8, w: 45 }, { r: 8, w: 45 }] },
      { name: "Incline Dumbbell Press", muscleGroup: "Chest", sets: [{ r: 10, w: 30 }, { r: 10, w: 32 }, { r: 8, w: 34 }] },
      { name: "Tricep Pushdown", muscleGroup: "Arms", sets: [{ r: 12, w: 25 }, { r: 12, w: 27 }, { r: 10, w: 30 }] },
    ],
  },
  {
    name: "Pull Day",
    exercises: [
      { name: "Deadlift", muscleGroup: "Back", sets: [{ r: 5, w: 120 }, { r: 5, w: 130 }, { r: 3, w: 140 }] },
      { name: "Barbell Row", muscleGroup: "Back", sets: [{ r: 8, w: 70 }, { r: 8, w: 75 }, { r: 6, w: 80 }] },
      { name: "Pull-ups", muscleGroup: "Back", sets: [{ r: 10, w: 0 }, { r: 8, w: 0 }, { r: 7, w: 0 }] },
      { name: "Bicep Curl", muscleGroup: "Arms", sets: [{ r: 12, w: 14 }, { r: 10, w: 16 }, { r: 10, w: 16 }] },
    ],
  },
  {
    name: "Leg Day",
    exercises: [
      { name: "Squat", muscleGroup: "Legs", sets: [{ r: 8, w: 100 }, { r: 6, w: 110 }, { r: 5, w: 120 }] },
      { name: "Romanian Deadlift", muscleGroup: "Legs", sets: [{ r: 10, w: 80 }, { r: 10, w: 85 }, { r: 8, w: 90 }] },
      { name: "Leg Press", muscleGroup: "Legs", sets: [{ r: 12, w: 150 }, { r: 10, w: 170 }, { r: 10, w: 180 }] },
      { name: "Calf Raise", muscleGroup: "Legs", sets: [{ r: 15, w: 60 }, { r: 15, w: 65 }, { r: 12, w: 70 }] },
    ],
  },
  {
    name: "Upper Body",
    exercises: [
      { name: "Dumbbell Bench Press", muscleGroup: "Chest", sets: [{ r: 10, w: 34 }, { r: 8, w: 36 }, { r: 8, w: 38 }] },
      { name: "Lat Pulldown", muscleGroup: "Back", sets: [{ r: 10, w: 55 }, { r: 10, w: 60 }, { r: 8, w: 65 }] },
      { name: "Lateral Raise", muscleGroup: "Shoulders", sets: [{ r: 12, w: 10 }, { r: 12, w: 12 }, { r: 10, w: 12 }] },
    ],
  },
];

async function seed() {
  const userId = await callMutation("users:getOrCreateDefaultUser", {});
  console.log("User ID:", userId);

  const now = Date.now();
  const DAY = 24 * 60 * 60 * 1000;
  const daysAgo = [1, 3, 5, 7, 9, 12, 14, 16, 19, 21, 23, 26];

  for (let i = 0; i < daysAgo.length; i++) {
    const workout = workouts[i % workouts.length];
    const sessionDate = now - daysAgo[i] * DAY;
    const variation = Math.random() * 0.1 - 0.05;

    const exercises = workout.exercises.map((ex, order) => ({
      name: ex.name,
      muscleGroup: ex.muscleGroup,
      order,
      sets: ex.sets.map((s, sOrder) => ({
        reps: Math.max(1, s.r + Math.floor(Math.random() * 3 - 1)),
        weight: Math.round(s.w * (1 + variation)),
        order: sOrder,
      })),
    }));

    const sessionId = await callMutation("sessions:create", {
      userId,
      date: sessionDate,
      status: "completed",
      exercises,
    });

    console.log(`Session ${i + 1}/12: ${workout.name} (${daysAgo[i]}d ago) → ${sessionId}`);
  }

  console.log("Done! 12 sessions seeded.");
}

seed().catch(console.error);
