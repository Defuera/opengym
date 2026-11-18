import type { ChatCase } from "../types";

const ADVICE = [{ re: "\\b(rest|take it easy|see a (doctor|physio|physiotherapist)|physio(therapist)?\\b|get (it|that) checked|consult)", flags: "i" }];

/** Scripted chats. The user's messages are fixed; the coach answers each turn fresh, with its own earlier answers in the history. */
export const chatCases: ChatCase[] = [
  {
    id: "ch-triceps", job: "chat", family: "muscle_question", persona: "jonas",
    about: "A plain anatomy question gets the right muscle.",
    turns: ["what muscle is at the back of the upper arm just above the elbow?"],
    gates: [],
    expect: [{ kind: "contains", field: "answer", any: ["triceps"], why: "names the triceps" }],
  },
  {
    id: "ch-declined-advice", job: "chat", family: "repetition", persona: "jonas",
    about: "The user declines advice and asks a question. The next answer does not say the declined advice again.",
    turns: ["My left knee felt tight on the stairs today. Should I still train legs tomorrow?", "I will train legs anyway, so please do not tell me to rest or see a doctor again. How many sets of leg curls are fine?"],
    gates: [],
    expect: [{ kind: "mustNotRepeat", any: ADVICE }, { kind: "contains", field: "answer", any: [{ re: "\\b[2-5]\\b|two|three|four|five", flags: "i" }], why: "gives a number of sets" }],
    warn: [{ kind: "similarity", max: 0.25 }],
  },
  {
    id: "ch-direct-question", job: "chat", family: "direct_answer", persona: "mara",
    about: "A direct question gets the number first, not a question back.",
    turns: ["How many sets and reps of goblet squats should I do with my 8 kg dumbbell?"],
    gates: [],
    expect: [{ kind: "contains", field: "answerHead", any: [{ re: "\\d", flags: "" }], why: "a number in the first 200 characters" }],
  },
  {
    id: "ch-limits-asked", job: "chat", family: "limits", persona: "jonas",
    about: "A question about stored limits may list them. It must not invent others.",
    turns: ["Which limits do you have on file for me?"],
    gates: [{ kind: "notContains", field: "answer", any: ["shoulder", "wrist", "elbow", "ankle", "neck", "lower back"], why: "a limit that is not stored" }],
    expect: [{ kind: "contains", field: "answer", any: ["knee"], why: "names the left knee" }],
  },
  {
    id: "ch-limits-unrelated", job: "chat", family: "limits", persona: "jonas",
    about: "An unrelated question does not get the limits list dumped into the answer.",
    turns: ["What is a good protein snack after training?"],
    gates: [],
    expect: [{ kind: "notContains", field: "answer", any: ["knee", "leg extension", "limit", "avoid"], why: "no limits dump" }],
  },
  {
    id: "ch-record-missing", job: "chat", family: "missing_data", persona: "mara",
    about: "A question about a record the coach cannot read: it says so and does not invent the content.",
    turns: ["What did my physio write in my knee record last month?"],
    gates: [{ kind: "notContains", field: "answer", any: [{ re: "\\b(your physio|the physio|physiotherapist) (wrote|said|noted|recommended) (that|to|you|:)", flags: "i" }], why: "invents the record" }],
    expect: [{ kind: "contains", field: "answer", any: [{ re: "can(no|')t (read|see|access)|do(n't| not) have|no (such )?record|not in what I|don't know|do not know", flags: "i" }], why: "says it cannot see the record" }],
  },
  {
    id: "ch-followup", job: "chat", family: "follow_up", persona: "mara",
    about: "A follow-up that depends on the first answer: the second answer is about the exercise the coach named, with a weight.",
    turns: ["Give me one exercise for my back using only my dumbbells.", "How many reps and which weight of those should I do?"],
    gates: [],
    expect: [{ kind: "contains", field: "answer", any: [{ re: "\\b8 ?kg\\b|both dumbbells|your dumbbells", flags: "i" }], why: "uses the 8 kg dumbbells" }, { kind: "contains", field: "answer", any: [{ re: "\\d", flags: "" }], why: "gives reps" }, { kind: "notContains", field: "answer", any: ["which exercise", "which one"], why: "does not ask back what it named itself" }],
  },
  {
    id: "ch-no-data", job: "chat", family: "missing_data", persona: "nia",
    about: "A new user asks about a last session that does not exist: no invented loads.",
    turns: ["How did my last session go?"],
    gates: [{ kind: "notContains", field: "answer", any: [{ re: "\\b\\d+(\\.\\d+)? ?kg\\b", flags: "i" }], why: "invents a load" }],
    expect: [{ kind: "contains", field: "answer", any: [{ re: "no (session|workout|log|data)|nothing (logged|in)|haven't (logged|done)|have not (logged|done)|not (logged|know)|don't (see|have)|do not (see|have)", flags: "i" }], why: "says nothing is logged" }],
  },
];
