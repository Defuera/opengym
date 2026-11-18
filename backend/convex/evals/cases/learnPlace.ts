import type { LearnCase } from "../types";

/** Sequences of sentences about one place. The note carries forward from step to step, as the server writes it. */
export const learnCases: LearnCase[] = [
  {
    id: "lp-adds", job: "learn_place", family: "add", persona: "mara", place: "Home",
    about: "A sentence that adds equipment changes the note and keeps what was there.",
    sentences: ["I also have a resistance band and a pull-up bar in the doorway", "I bought a 12 kg kettlebell"],
    gates: [{ kind: "claims", item: "dumbbell", value: true }, { kind: "claims", item: "band", value: true }, { kind: "claims", item: "pull up bar", value: true }],
    expect: [{ kind: "claims", item: "kettlebell", value: true }, { kind: "noteChanged" }],
  },
  {
    id: "lp-removes", job: "learn_place", family: "remove", persona: "mara", place: "Home",
    about: "A sentence that removes equipment takes it out of the note and keeps the rest.",
    sentences: ["The yoga mat is gone, I threw it away"],
    gates: [{ kind: "claims", item: "dumbbell", value: true }],
    expect: [{ kind: "claims", item: "mat", value: false }, { kind: "noteChanged" }],
  },
  {
    id: "lp-unrelated", job: "learn_place", family: "no_change", persona: "jonas", place: "Gym",
    about: "Sentences that say nothing about the equipment leave the note as it is.",
    sentences: ["My knee hurt on the stairs this morning and I slept badly", "What is a good warm-up for a legs day?"],
    gates: [{ kind: "noteUnchanged" }],
    expect: [],
  },
  {
    id: "lp-other-place", job: "learn_place", family: "other_place", persona: "mara", place: "Home",
    about: "A sentence about another place does not change the note of this place.",
    sentences: ["At the park there is also a rope swing and a sandpit"],
    gates: [{ kind: "noteUnchanged" }],
    expect: [],
  },
];
