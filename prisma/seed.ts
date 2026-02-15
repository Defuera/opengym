import { PrismaClient } from "@prisma/client";
import { PrismaLibSql } from "@prisma/adapter-libsql";

const adapter = new PrismaLibSql({
  url: "file:./dev.db",
});

const prisma = new PrismaClient({ adapter });

async function main() {

  // Create default user
  const user = await prisma.user.upsert({
    where: { id: "default-user" },
    update: {},
    create: {
      id: "default-user",
      name: "Default User",
    },
  });

  console.log("Created user:", user);

  // Create past session 1 (3 days ago)
  const pastDate1 = new Date();
  pastDate1.setDate(pastDate1.getDate() - 3);

  const session1 = await prisma.session.create({
    data: {
      userId: user.id,
      date: pastDate1,
      status: "completed",
      exercises: {
        create: [
          {
            name: "Bench Press",
            muscleGroup: "chest",
            order: 1,
            sets: {
              create: [
                { reps: 8, weight: 135, order: 1 },
                { reps: 8, weight: 135, order: 2 },
                { reps: 7, weight: 135, order: 3 },
              ],
            },
          },
          {
            name: "Incline Dumbbell Press",
            muscleGroup: "chest",
            order: 2,
            sets: {
              create: [
                { reps: 10, weight: 50, order: 1 },
                { reps: 10, weight: 50, order: 2 },
                { reps: 9, weight: 50, order: 3 },
              ],
            },
          },
          {
            name: "Tricep Dips",
            muscleGroup: "triceps",
            order: 3,
            sets: {
              create: [
                { reps: 12, weight: 0, order: 1 },
                { reps: 11, weight: 0, order: 2 },
                { reps: 10, weight: 0, order: 3 },
              ],
            },
          },
        ],
      },
    },
  });

  console.log("Created session 1:", session1);

  // Create past session 2 (1 day ago)
  const pastDate2 = new Date();
  pastDate2.setDate(pastDate2.getDate() - 1);

  const session2 = await prisma.session.create({
    data: {
      userId: user.id,
      date: pastDate2,
      status: "completed",
      exercises: {
        create: [
          {
            name: "Squats",
            muscleGroup: "legs",
            order: 1,
            sets: {
              create: [
                { reps: 10, weight: 185, order: 1 },
                { reps: 10, weight: 185, order: 2 },
                { reps: 8, weight: 185, order: 3 },
              ],
            },
          },
          {
            name: "Romanian Deadlift",
            muscleGroup: "legs",
            order: 2,
            sets: {
              create: [
                { reps: 12, weight: 135, order: 1 },
                { reps: 12, weight: 135, order: 2 },
                { reps: 10, weight: 135, order: 3 },
              ],
            },
          },
          {
            name: "Leg Curls",
            muscleGroup: "legs",
            order: 3,
            sets: {
              create: [
                { reps: 15, weight: 70, order: 1 },
                { reps: 14, weight: 70, order: 2 },
                { reps: 12, weight: 70, order: 3 },
              ],
            },
          },
        ],
      },
    },
  });

  console.log("Created session 2:", session2);

  // Create today's session (active)
  const today = new Date();

  const session3 = await prisma.session.create({
    data: {
      userId: user.id,
      date: today,
      status: "active",
      exercises: {
        create: [
          {
            name: "Pull-ups",
            muscleGroup: "back",
            order: 1,
            sets: {
              create: [
                { reps: 8, weight: 0, order: 1 },
                { reps: 7, weight: 0, order: 2 },
                { reps: 6, weight: 0, order: 3 },
              ],
            },
          },
          {
            name: "Barbell Rows",
            muscleGroup: "back",
            order: 2,
            sets: {
              create: [
                { reps: 10, weight: 135, order: 1 },
                { reps: 9, weight: 135, order: 2 },
                { reps: 8, weight: 135, order: 3 },
              ],
            },
          },
          {
            name: "Bicep Curls",
            muscleGroup: "biceps",
            order: 3,
            sets: {
              create: [
                { reps: 12, weight: 30, order: 1 },
                { reps: 11, weight: 30, order: 2 },
                { reps: 10, weight: 30, order: 3 },
              ],
            },
          },
        ],
      },
    },
  });

  console.log("Created session 3 (today):", session3);
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
