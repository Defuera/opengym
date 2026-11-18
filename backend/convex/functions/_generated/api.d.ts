/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as commands_context from "../commands/context.js";
import type * as commands_entries from "../commands/entries.js";
import type * as commands_files from "../commands/files.js";
import type * as commands_goals from "../commands/goals.js";
import type * as commands_imports from "../commands/imports.js";
import type * as commands_limits from "../commands/limits.js";
import type * as commands_messages from "../commands/messages.js";
import type * as commands_sessions from "../commands/sessions.js";
import type * as commands_settings from "../commands/settings.js";
import type * as commands_start from "../commands/start.js";
import type * as commands_threads from "../commands/threads.js";
import type * as jobs_chat from "../jobs/chat.js";
import type * as jobs_dashboards from "../jobs/dashboards.js";
import type * as jobs_importFiles from "../jobs/importFiles.js";
import type * as jobs_imports from "../jobs/imports.js";
import type * as jobs_migrations from "../jobs/migrations.js";
import type * as jobs_models from "../jobs/models.js";
import type * as jobs_parseGoal from "../jobs/parseGoal.js";
import type * as jobs_parseLog from "../jobs/parseLog.js";
import type * as jobs_pdfText from "../jobs/pdfText.js";
import type * as jobs_plans from "../jobs/plans.js";
import type * as jobs_rebuild from "../jobs/rebuild.js";
import type * as jobs_reviews from "../jobs/reviews.js";
import type * as jobs_startRequest from "../jobs/startRequest.js";
import type * as lib_ai from "../lib/ai.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_constants from "../lib/constants.js";
import type * as lib_db from "../lib/db.js";
import type * as lib_entriesDb from "../lib/entriesDb.js";
import type * as lib_factsChanged from "../lib/factsChanged.js";
import type * as lib_files from "../lib/files.js";
import type * as lib_importWrite from "../lib/importWrite.js";
import type * as lib_limitsDb from "../lib/limitsDb.js";
import type * as lib_settingsDb from "../lib/settingsDb.js";
import type * as lib_validate from "../lib/validate.js";
import type * as lib_validators from "../lib/validators.js";
import type * as model_ai_factory from "../model/ai/factory.js";
import type * as model_ai_jobs_buildDashboard from "../model/ai/jobs/buildDashboard.js";
import type * as model_ai_jobs_buildSession from "../model/ai/jobs/buildSession.js";
import type * as model_ai_jobs_chat from "../model/ai/jobs/chat.js";
import type * as model_ai_jobs_coachPicture from "../model/ai/jobs/coachPicture.js";
import type * as model_ai_jobs_extractFromChat from "../model/ai/jobs/extractFromChat.js";
import type * as model_ai_jobs_importData from "../model/ai/jobs/importData.js";
import type * as model_ai_jobs_inputs from "../model/ai/jobs/inputs.js";
import type * as model_ai_jobs_parseGoal from "../model/ai/jobs/parseGoal.js";
import type * as model_ai_jobs_parseLog from "../model/ai/jobs/parseLog.js";
import type * as model_ai_jobs_planSession from "../model/ai/jobs/planSession.js";
import type * as model_ai_jobs_reviewSession from "../model/ai/jobs/reviewSession.js";
import type * as model_ai_jobs_shared from "../model/ai/jobs/shared.js";
import type * as model_ai_jobs_summariseThread from "../model/ai/jobs/summariseThread.js";
import type * as model_ai_jobs_titleThread from "../model/ai/jobs/titleThread.js";
import type * as model_ai_modelList from "../model/ai/modelList.js";
import type * as model_ai_promptRules from "../model/ai/promptRules.js";
import type * as model_ai_provider from "../model/ai/provider.js";
import type * as model_ai_providers_anthropic from "../model/ai/providers/anthropic.js";
import type * as model_ai_providers_deepseek from "../model/ai/providers/deepseek.js";
import type * as model_ai_providers_mock from "../model/ai/providers/mock.js";
import type * as model_ai_providers_openai from "../model/ai/providers/openai.js";
import type * as model_ai_providers_openaiCompatible from "../model/ai/providers/openaiCompatible.js";
import type * as model_ai_runJob from "../model/ai/runJob.js";
import type * as model_coachContext from "../model/coachContext.js";
import type * as model_entryContext from "../model/entryContext.js";
import type * as model_fileText from "../model/fileText.js";
import type * as model_importUnits from "../model/importUnits.js";
import type * as model_logDate from "../model/logDate.js";
import type * as model_proposals from "../model/proposals.js";
import type * as model_rules_dashboard from "../model/rules/dashboard.js";
import type * as model_rules_foci from "../model/rules/foci.js";
import type * as model_rules_focusParts from "../model/rules/focusParts.js";
import type * as model_rules_limits from "../model/rules/limits.js";
import type * as model_rules_load from "../model/rules/load.js";
import type * as model_rules_muscles from "../model/rules/muscles.js";
import type * as model_rules_planner from "../model/rules/planner.js";
import type * as model_rules_predictions from "../model/rules/predictions.js";
import type * as model_rules_review from "../model/rules/review.js";
import type * as model_rules_stats from "../model/rules/stats.js";
import type * as model_rules_util from "../model/rules/util.js";
import type * as model_schema_common from "../model/schema/common.js";
import type * as model_schema_dashboard from "../model/schema/dashboard.js";
import type * as model_schema_entry from "../model/schema/entry.js";
import type * as model_schema_goalContext from "../model/schema/goalContext.js";
import type * as model_schema_importReview from "../model/schema/importReview.js";
import type * as model_schema_index from "../model/schema/index.js";
import type * as model_schema_limits from "../model/schema/limits.js";
import type * as model_schema_plan from "../model/schema/plan.js";
import type * as model_schema_session from "../model/schema/session.js";
import type * as model_schema_structuredImport from "../model/schema/structuredImport.js";
import type * as model_schema_thread from "../model/schema/thread.js";
import type * as model_sessionShape from "../model/sessionShape.js";
import type * as model_startFallback from "../model/startFallback.js";
import type * as model_structuredImport from "../model/structuredImport.js";
import type * as model_threadTitle from "../model/threadTitle.js";
import type * as queries_aboutMe from "../queries/aboutMe.js";
import type * as queries_context from "../queries/context.js";
import type * as queries_dashboard from "../queries/dashboard.js";
import type * as queries_entries from "../queries/entries.js";
import type * as queries_files from "../queries/files.js";
import type * as queries_goals from "../queries/goals.js";
import type * as queries_imports from "../queries/imports.js";
import type * as queries_messages from "../queries/messages.js";
import type * as queries_plans from "../queries/plans.js";
import type * as queries_reviews from "../queries/reviews.js";
import type * as queries_sessions from "../queries/sessions.js";
import type * as queries_settings from "../queries/settings.js";
import type * as queries_start from "../queries/start.js";
import type * as queries_threads from "../queries/threads.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "commands/context": typeof commands_context;
  "commands/entries": typeof commands_entries;
  "commands/files": typeof commands_files;
  "commands/goals": typeof commands_goals;
  "commands/imports": typeof commands_imports;
  "commands/limits": typeof commands_limits;
  "commands/messages": typeof commands_messages;
  "commands/sessions": typeof commands_sessions;
  "commands/settings": typeof commands_settings;
  "commands/start": typeof commands_start;
  "commands/threads": typeof commands_threads;
  "jobs/chat": typeof jobs_chat;
  "jobs/dashboards": typeof jobs_dashboards;
  "jobs/importFiles": typeof jobs_importFiles;
  "jobs/imports": typeof jobs_imports;
  "jobs/migrations": typeof jobs_migrations;
  "jobs/models": typeof jobs_models;
  "jobs/parseGoal": typeof jobs_parseGoal;
  "jobs/parseLog": typeof jobs_parseLog;
  "jobs/pdfText": typeof jobs_pdfText;
  "jobs/plans": typeof jobs_plans;
  "jobs/rebuild": typeof jobs_rebuild;
  "jobs/reviews": typeof jobs_reviews;
  "jobs/startRequest": typeof jobs_startRequest;
  "lib/ai": typeof lib_ai;
  "lib/auth": typeof lib_auth;
  "lib/constants": typeof lib_constants;
  "lib/db": typeof lib_db;
  "lib/entriesDb": typeof lib_entriesDb;
  "lib/factsChanged": typeof lib_factsChanged;
  "lib/files": typeof lib_files;
  "lib/importWrite": typeof lib_importWrite;
  "lib/limitsDb": typeof lib_limitsDb;
  "lib/settingsDb": typeof lib_settingsDb;
  "lib/validate": typeof lib_validate;
  "lib/validators": typeof lib_validators;
  "model/ai/factory": typeof model_ai_factory;
  "model/ai/jobs/buildDashboard": typeof model_ai_jobs_buildDashboard;
  "model/ai/jobs/buildSession": typeof model_ai_jobs_buildSession;
  "model/ai/jobs/chat": typeof model_ai_jobs_chat;
  "model/ai/jobs/coachPicture": typeof model_ai_jobs_coachPicture;
  "model/ai/jobs/extractFromChat": typeof model_ai_jobs_extractFromChat;
  "model/ai/jobs/importData": typeof model_ai_jobs_importData;
  "model/ai/jobs/inputs": typeof model_ai_jobs_inputs;
  "model/ai/jobs/parseGoal": typeof model_ai_jobs_parseGoal;
  "model/ai/jobs/parseLog": typeof model_ai_jobs_parseLog;
  "model/ai/jobs/planSession": typeof model_ai_jobs_planSession;
  "model/ai/jobs/reviewSession": typeof model_ai_jobs_reviewSession;
  "model/ai/jobs/shared": typeof model_ai_jobs_shared;
  "model/ai/jobs/summariseThread": typeof model_ai_jobs_summariseThread;
  "model/ai/jobs/titleThread": typeof model_ai_jobs_titleThread;
  "model/ai/modelList": typeof model_ai_modelList;
  "model/ai/promptRules": typeof model_ai_promptRules;
  "model/ai/provider": typeof model_ai_provider;
  "model/ai/providers/anthropic": typeof model_ai_providers_anthropic;
  "model/ai/providers/deepseek": typeof model_ai_providers_deepseek;
  "model/ai/providers/mock": typeof model_ai_providers_mock;
  "model/ai/providers/openai": typeof model_ai_providers_openai;
  "model/ai/providers/openaiCompatible": typeof model_ai_providers_openaiCompatible;
  "model/ai/runJob": typeof model_ai_runJob;
  "model/coachContext": typeof model_coachContext;
  "model/entryContext": typeof model_entryContext;
  "model/fileText": typeof model_fileText;
  "model/importUnits": typeof model_importUnits;
  "model/logDate": typeof model_logDate;
  "model/proposals": typeof model_proposals;
  "model/rules/dashboard": typeof model_rules_dashboard;
  "model/rules/foci": typeof model_rules_foci;
  "model/rules/focusParts": typeof model_rules_focusParts;
  "model/rules/limits": typeof model_rules_limits;
  "model/rules/load": typeof model_rules_load;
  "model/rules/muscles": typeof model_rules_muscles;
  "model/rules/planner": typeof model_rules_planner;
  "model/rules/predictions": typeof model_rules_predictions;
  "model/rules/review": typeof model_rules_review;
  "model/rules/stats": typeof model_rules_stats;
  "model/rules/util": typeof model_rules_util;
  "model/schema/common": typeof model_schema_common;
  "model/schema/dashboard": typeof model_schema_dashboard;
  "model/schema/entry": typeof model_schema_entry;
  "model/schema/goalContext": typeof model_schema_goalContext;
  "model/schema/importReview": typeof model_schema_importReview;
  "model/schema/index": typeof model_schema_index;
  "model/schema/limits": typeof model_schema_limits;
  "model/schema/plan": typeof model_schema_plan;
  "model/schema/session": typeof model_schema_session;
  "model/schema/structuredImport": typeof model_schema_structuredImport;
  "model/schema/thread": typeof model_schema_thread;
  "model/sessionShape": typeof model_sessionShape;
  "model/startFallback": typeof model_startFallback;
  "model/structuredImport": typeof model_structuredImport;
  "model/threadTitle": typeof model_threadTitle;
  "queries/aboutMe": typeof queries_aboutMe;
  "queries/context": typeof queries_context;
  "queries/dashboard": typeof queries_dashboard;
  "queries/entries": typeof queries_entries;
  "queries/files": typeof queries_files;
  "queries/goals": typeof queries_goals;
  "queries/imports": typeof queries_imports;
  "queries/messages": typeof queries_messages;
  "queries/plans": typeof queries_plans;
  "queries/reviews": typeof queries_reviews;
  "queries/sessions": typeof queries_sessions;
  "queries/settings": typeof queries_settings;
  "queries/start": typeof queries_start;
  "queries/threads": typeof queries_threads;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
