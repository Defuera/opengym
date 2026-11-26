import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvex/dartvex.dart' as cx;
import 'package:http/http.dart' as http;

import '../models.dart';
import 'convex_codec.dart';
import 'convex_types.dart';
import 'tracker_payload.dart';
import 'tracker_source.dart';
import 'transcript_result.dart';

export 'convex_types.dart';

/// The app's gateway to the hosted Convex backend: typed live streams and
/// typed commands. The only seam that knows the wire format.
///
/// Streams are LIVE: subscribe once and every change is pushed. A stream emits
/// an error event ([ConvexCallException]) when the server refuses (for
/// example a wrong token) and keeps running. Commands are idempotent on the
/// server (client-made ids), so the outbox may send them again.
/// One exercise of a planned session, for [ConvexClient.planLoad].
/// [sets] counts rep sets (0 for a time exercise); [minutes] is the planned
/// total of a time exercise (0 otherwise).
class PlanLoadItem {
  const PlanLoadItem({required this.name, required this.sets, required this.minutes});

  final String name;
  final int sets;
  final double minutes;

  Map<String, dynamic> toJson() => <String, dynamic>{'name': name, 'sets': sets, 'minutes': minutes};
}

abstract class ConvexClient {
  /// Link state changes. The first event is the current state.
  Stream<ConvexLink> get connection;

  // ---------- live reads ----------

  /// Newest first.
  Stream<List<Session>> watchRecentSessions({int limit = 200});

  /// Sessions that ended after [since] (epoch ms), oldest first.
  Stream<List<Session>> watchSessionsSince(int since);
  Stream<List<Goal>> watchGoals();
  Stream<List<ContextItem>> watchContext();

  /// Notes, newest first by their time (`at`). The server allows 1 to 200.
  Stream<List<LogEntry>> watchEntries({int limit = 50});

  /// The places the coach knows, sorted by name (`queries/places:list`).
  Stream<List<Place>> watchPlaces();

  /// Every program that is not deleted, newest first (`queries/programs:list`).
  Stream<List<Program>> watchPrograms();

  /// The proposals of one thread, oldest first (`queries/proposals:forThread`).
  Stream<List<Proposal>> watchThreadProposals(String threadId);

  /// The art state of each name, same order (`queries/exerciseArt:get`).
  Stream<List<ExerciseArt>> watchExerciseArt(List<String> names);

  /// Asks the server to make art for these names (1 to 12). Idempotent.
  Future<void> requestExerciseArt(List<String> names);
  /// The stored plan for [activity] (null: Gym) and [focus]; a null focus asks
  /// for the advised focus.
  Stream<Stored<Plan>> watchNextPlan({String? activity, String? focus});

  /// [days] is 7 or 30.
  Stream<Stored<Dashboard>> watchDashboard(int days);

  /// The value is null while the session is not on the server.
  Stream<Stored<Review?>> watchReview(String sessionId);

  /// What one session loaded: muscle key -> level 0..3 (`queries/sessions:load`). Null: no such session.
  Stream<Map<String, int>?> watchSessionLoad(String sessionId);

  /// What a planned session would load: muscle key -> level 0..3, every key
  /// present (`queries/sessions:planLoad`). One call.
  Future<Map<String, int>?> planLoad(List<PlanLoadItem> exercises);
  Stream<List<ImportJob>> watchImports();

  /// Limits (with rules, records, check-ins), body load and focus parts.
  Stream<AboutMe> watchAboutMe();

  /// The coach model setting: provider, default, chosen model, cached model list.
  Stream<AiSettings> watchAiSettings();

  /// The limits a session loaded that have no check-in for it yet. One call.
  Future<List<AskItem>> askAfter(String sessionId);

  /// Newest activity first. Each thread carries its reply status.
  Stream<List<Thread>> watchThreads();

  /// One thread's messages, oldest first. The coach answer arrives here.
  Stream<List<Message>> watchMessages(String threadId);

  // ---------- commands ----------

  Future<void> saveSession(Session session);
  Future<void> removeSession(String sessionId);

  /// The person agrees. Returns the id of the program that was made or changed.
  Future<String> acceptProposal(String proposalId);

  /// The person says no, or gives up waiting.
  Future<void> declineProposal(String proposalId);

  /// [status] is `active`, `paused` or `done`.
  Future<void> setProgramStatus(String programId, String status);

  /// Deletes the program (the server marks it and erases it later).
  Future<void> removeProgram(String programId);

  /// Opens the debrief chat of a finished session (ADR-041) and returns its
  /// thread id. The first message of the thread is the coach's debrief. One
  /// thread per session: a second call returns the same thread.
  Future<String> openDebrief(String sessionId);

  /// Sets the place of one session, or clears it with null. Idempotent.
  Future<void> setSessionPlace({required String sessionId, required String? placeId});

  /// Logs an activity as one text (ADR-018). The server stores [session] as
  /// given (type, time, text as the note, parse pending) and then reads the
  /// text into its structure. Sending the same session id again is safe.
  Future<void> logSessionText({
    required String sessionId,
    required String type,
    required String text,
    required int at,
  });
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  });
  Future<void> updateGoal(String goalId, GoalPatch patch);
  Future<void> removeGoal(String goalId);

  /// Saves a note (create or change). Every id in [fileIds] must be uploaded
  /// already. A file left out of a changed note is deleted by the server.
  /// Sending the same [entryId] again is safe.
  Future<void> saveEntry({
    required String entryId,
    required String text,
    required List<String> fileIds,
    required int at,
    required int createdAt,
  });

  /// Deletes the note and its files.
  Future<void> removeEntry(String entryId);
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  });
  Future<void> updateContext(String itemId, ContextPatch patch);
  Future<void> removeContext(String itemId);
  Future<void> removeImport(String importId);

  /// Upsert by [Limit.id]. Records and check-ins are not part of this write.
  Future<void> saveLimit(Limit limit);

  /// Also deletes the limit's records and check-ins.
  Future<void> removeLimit(String limitId);
  Future<void> addRecord(LimitRecord record);
  Future<void> removeRecord(String recordId);
  Future<void> saveCheckin(Checkin checkin);

  /// Without a title the thread starts as "New chat" and is named after the
  /// first message. A given title counts as set by the user. With [placeId]
  /// the thread is about that place.
  Future<void> createThread({required String threadId, String? title, String? placeId, ThreadAbout? about});

  /// The user names a thread. The backend never replaces that title.
  Future<void> renameThread({required String threadId, required String title});

  /// Deletes the thread and its messages. Goals and notes it produced stay.
  Future<void> removeThread(String threadId);

  /// Stores the user message at once and starts the coach. The answer is NOT
  /// returned: it arrives through [watchMessages] and [watchThreads]. Sending
  /// the same [messageId] again changes nothing on the server.
  Future<void> sendMessage({
    required String threadId,
    required String messageId,
    required String text,
    List<String> fileIds = const <String>[],
    ChatContext? context,
    ChatAnswer? answer,
  });

  /// Asks the server for the text of the recording [fileId] (already
  /// uploaded). Nothing is stored as a message and the coach does not run.
  /// On success the server removes the audio file. A failure keeps the file,
  /// so the same call can be made again.
  Future<TranscriptResult> transcribeAudio(String fileId);

  /// Asks the server to read a voice message again (one with `voice: failed`).
  Future<void> retryVoice(String messageId);

  /// Uploads [bytes] (get an upload URL, POST the bytes, register) and
  /// returns the stored file. A retry with the same [fileId] is safe.
  Future<FileMeta> uploadFile({
    required String fileId,
    required String name,
    required String mime,
    required List<int> bytes,
  });

  /// Meta and download URL of a file, or null when the server has no such file.
  Future<FileLink?> fileLink(String fileId);
  Future<void> removeFile(String fileId);

  /// Asks the coach to interpret a typed "something new" start. NOT a fact:
  /// the app never queues it in the outbox. The answer arrives through
  /// [watchStartRequest]. Sending the same [requestId] again changes nothing.
  ///
  /// The Start tab sends the chosen activity as [name] and the optional note
  /// as [text]: the coach then decides the focus and the plan.
  ///
  /// With [feedback] and [previousRequestId] (both or neither) the coach
  /// rebuilds the proposal of that earlier request so the feedback holds; the
  /// server takes the name and the text from the earlier request.
  ///
  /// With [feedback], [previousPlan] (the compact copy of the session as it is
  /// on the phone: names with sets, no notes) and [name], the coach rebuilds
  /// a session that did not come from a start request.
  Future<void> requestStart({
    required String requestId,
    String? name,
    String? text,
    String? feedback,
    String? previousRequestId,
    List<Map<String, dynamic>>? previousPlan,
  });

  /// The state of one start request; null while the server has none.
  Stream<StartRequest?> watchStartRequest(String requestId);

  /// The open session on the server (ADR-028); `session` is null when there is none.
  Stream<OpenRemote> watchOpenSession();

  /// Stores the open session ([openSessionWire]) and returns the server's new
  /// revision. NOT a fact: it never goes to the outbox.
  Future<int> putOpenSession(Map<String, dynamic> session);

  /// The session [id] ended on the phone: the server drops its open copy. Idempotent.
  Future<void> clearOpenSession(String id);

  /// Starts an AI import of uploaded files. Progress arrives through
  /// [watchImports]. Sending the same [importId] again changes nothing.
  Future<void> startImport({required String importId, required List<String> fileIds});

  /// Sets the coach model; null goes back to the backend default. Idempotent.
  /// NOT a fact: the app never queues it in the outbox.
  Future<void> setAiModel(String? model);

  /// Asks the backend to reload the provider's model list. The new list
  /// arrives through [watchAiSettings].
  Future<void> refreshModels();

  /// Sends tracker readings from the phone's health store (`commands/tracker:sync`,
  /// ADR-036). At most 31 days and 100 workouts. Idempotent. NOT a fact the person
  /// logged and NOT queued in the outbox: the next sync sends the window again.
  Future<void> syncTracker({required List<TrackerDay> days, required List<TrackerWorkout> workouts});

  /// One authenticated call. Tells a wrong token from an unreachable server.
  Future<AccessStatus> checkAccess();

  Future<void> dispose();
}

/// [ConvexClient] on top of the community `dartvex` package. The only file in
/// the app that imports `dartvex`.
class DartvexConvexClient implements ConvexClient {
  /// Opens a socket to [url] (`https://<name>.convex.cloud`).
  /// [token] is the interim shared app token.
  factory DartvexConvexClient.connect({
    required String url,
    required String token,
  }) {
    final cx.ConvexClient raw = cx.ConvexClient(url);
    return DartvexConvexClient(
      caller: raw,
      token: token,
      connectionStates: raw.connectionStatus.map(_link),
      onDispose: () async => raw.dispose(),
    );
  }

  /// For tests: pass a fake [cx.ConvexFunctionCaller].
  DartvexConvexClient({
    required cx.ConvexFunctionCaller caller,
    required String token,
    required Stream<ConvexLink> connectionStates,
    Future<void> Function()? onDispose,
    this.accessTimeout = const Duration(seconds: 8),
    http.Client? httpClient,
    this.uploadTimeout = const Duration(seconds: 90),
  })  : _http = httpClient ?? http.Client(),
        _caller = caller,
        _token = token,
        _states = connectionStates,
        _onDispose = onDispose;

  final cx.ConvexFunctionCaller _caller;
  final String _token;
  final Stream<ConvexLink> _states;
  final Future<void> Function()? _onDispose;
  final Duration accessTimeout;
  final http.Client _http;
  final Duration uploadTimeout;

  static ConvexLink _link(cx.ConnectionStatus s) {
    if (s.isConnected) {
      return ConvexLink.connected;
    }
    if (!s.hasEverConnected) {
      return ConvexLink.connecting;
    }
    return s.isWebSocketConnected ? ConvexLink.reconnecting : ConvexLink.offline;
  }

  @override
  Stream<ConvexLink> get connection => _states;

  // ---------- live reads ----------

  @override
  Stream<List<Session>> watchRecentSessions({int limit = 200}) =>
      _watch('queries/sessions:recent', <String, dynamic>{'limit': limit}, decodeSessions);

  @override
  Stream<List<Session>> watchSessionsSince(int since) =>
      _watch('queries/sessions:since', <String, dynamic>{'since': since}, decodeSessions);

  @override
  Stream<List<Goal>> watchGoals() =>
      _watch('queries/goals:list', const <String, dynamic>{}, decodeGoals);

  @override
  Stream<List<LogEntry>> watchEntries({int limit = 50}) =>
      _watch('queries/entries:recent', <String, dynamic>{'limit': limit}, decodeEntries);

  @override
  Stream<List<Place>> watchPlaces() =>
      _watch('queries/places:list', const <String, dynamic>{}, decodePlaces);

  @override
  Stream<List<ExerciseArt>> watchExerciseArt(List<String> names) =>
      _watch('queries/exerciseArt:get', <String, dynamic>{'names': names}, decodeExerciseArts);

  @override
  Future<void> requestExerciseArt(List<String> names) =>
      _mutate('commands/exerciseArt:request', <String, dynamic>{'names': names});

  @override
  Future<void> saveEntry({
    required String entryId,
    required String text,
    required List<String> fileIds,
    required int at,
    required int createdAt,
  }) =>
      _mutate('commands/entries:save', <String, dynamic>{
        'entry': <String, dynamic>{
          'entryId': entryId,
          'text': text,
          'fileIds': fileIds,
          'at': at,
          'createdAt': createdAt,
        },
      });

  @override
  Future<void> removeEntry(String entryId) =>
      _mutate('commands/entries:remove', <String, dynamic>{'entryId': entryId});

  @override
  Stream<List<ContextItem>> watchContext() =>
      _watch('queries/context:list', const <String, dynamic>{}, decodeContext);

  @override
  Stream<Stored<Plan>> watchNextPlan({String? activity, String? focus}) => _watch(
        'queries/plans:next',
        <String, dynamic>{
          if (activity != null) 'activity': activity,
          if (focus != null) 'focus': focus,
        },
        decodePlan,
      );

  @override
  Stream<StartRequest?> watchStartRequest(String requestId) => _watch(
        'queries/start:request',
        <String, dynamic>{'requestId': requestId},
        decodeStartRequest,
      );

  @override
  Future<void> requestStart({
    required String requestId,
    String? name,
    String? text,
    String? feedback,
    String? previousRequestId,
    List<Map<String, dynamic>>? previousPlan,
  }) =>
      _mutate('commands/start:request', <String, dynamic>{
        'requestId': requestId,
        if (name != null) 'name': name,
        if (text != null) 'text': text,
        if (feedback != null) 'feedback': feedback,
        if (previousRequestId != null) 'previousRequestId': previousRequestId,
        if (previousPlan != null) 'previousPlan': previousPlan,
      });

  @override
  Stream<OpenRemote> watchOpenSession() =>
      _watch('queries/openSession:get', const <String, dynamic>{}, decodeOpenRemote);

  @override
  Future<int> putOpenSession(Map<String, dynamic> session) async {
    final Object? v = await _mutateValue('commands/openSession:put', <String, dynamic>{'session': session});
    return v is num ? v.toInt() : 0;
  }

  @override
  Future<void> clearOpenSession(String id) => _mutate('commands/openSession:clear', <String, dynamic>{'id': id});

  @override
  Stream<List<Program>> watchPrograms() =>
      _watch('queries/programs:list', const <String, dynamic>{}, decodePrograms);

  @override
  Stream<List<Proposal>> watchThreadProposals(String threadId) =>
      _watch('queries/proposals:forThread', <String, dynamic>{'threadId': threadId}, decodeProposals);

  @override
  Future<String> acceptProposal(String proposalId) async {
    final Object? v = await _mutateValue('commands/proposals:accept', <String, dynamic>{'proposalId': proposalId});
    return decodeAccepted(v);
  }

  @override
  Future<void> declineProposal(String proposalId) =>
      _mutate('commands/proposals:decline', <String, dynamic>{'proposalId': proposalId});

  @override
  Future<void> setProgramStatus(String programId, String status) =>
      _mutate('commands/programs:setStatus', <String, dynamic>{'programId': programId, 'status': status});

  @override
  Future<void> removeProgram(String programId) =>
      _mutate('commands/programs:remove', <String, dynamic>{'programId': programId});

  @override
  Stream<Stored<Dashboard>> watchDashboard(int days) =>
      _watch('queries/dashboard:get', <String, dynamic>{'days': days}, decodeDashboard);

  @override
  Stream<Stored<Review?>> watchReview(String sessionId) =>
      _watch('queries/reviews:get', <String, dynamic>{'sessionId': sessionId}, decodeReview);

  @override
  Stream<Map<String, int>?> watchSessionLoad(String sessionId) =>
      _watch('queries/sessions:load', <String, dynamic>{'sessionId': sessionId}, decodeSessionLoad);

  @override
  Future<Map<String, int>?> planLoad(List<PlanLoadItem> exercises) async {
    try {
      final Object? v = await _caller.query('queries/sessions:planLoad', <String, dynamic>{
        'token': _token,
        'exercises': <Map<String, dynamic>>[for (final PlanLoadItem x in exercises) x.toJson()],
      });
      return decodeSessionLoad(v);
    } on cx.ConvexException catch (e) {
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Stream<List<ImportJob>> watchImports() =>
      _watch('queries/imports:list', const <String, dynamic>{}, decodeImports);

  @override
  Stream<AboutMe> watchAboutMe() =>
      _watch('queries/aboutMe:get', const <String, dynamic>{}, decodeAboutMe);

  @override
  Stream<AiSettings> watchAiSettings() =>
      _watch('queries/settings:ai', const <String, dynamic>{}, decodeAiSettings);

  @override
  Future<List<AskItem>> askAfter(String sessionId) async {
    try {
      final Object? v = await _caller.query(
          'queries/aboutMe:askAfter', <String, dynamic>{'token': _token, 'sessionId': sessionId});
      return decodeAskAfter(v);
    } on cx.ConvexException catch (e) {
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Stream<List<Thread>> watchThreads() =>
      _watch('queries/threads:list', const <String, dynamic>{}, decodeThreads);

  @override
  Stream<List<Message>> watchMessages(String threadId) =>
      _watch('queries/messages:list', <String, dynamic>{'threadId': threadId}, decodeMessages);

  Stream<T> _watch<T>(
    String name,
    Map<String, dynamic> args,
    T Function(Object?) decode,
  ) {
    late final StreamController<T> out;
    cx.ConvexSubscription? sub;
    StreamSubscription<cx.QueryResult>? listener;
    out = StreamController<T>(
      onListen: () {
        sub = _caller.subscribe(name, <String, dynamic>{'token': _token, ...args});
        listener = sub!.stream.listen((cx.QueryResult r) {
          switch (r) {
            case cx.QuerySuccess(:final Object? value):
              try {
                out.add(decode(value));
              } catch (_) {
                out.addError(const ConvexCallException(
                    'The server sent an answer the app does not understand.'));
              }
            case cx.QueryError(:final Object? data):
              out.addError(ConvexCallException.fromData(data));
            case cx.QueryLoading():
              break;
          }
        });
      },
      onCancel: () async {
        await listener?.cancel();
        sub?.cancel();
      },
    );
    return out.stream;
  }

  // ---------- commands ----------

  @override
  Future<void> saveSession(Session session) =>
      _mutate('commands/sessions:save', <String, dynamic>{'session': encodeSession(session)});

  @override
  Future<void> removeSession(String sessionId) =>
      _mutate('commands/sessions:remove', <String, dynamic>{'sessionId': sessionId});

  @override
  Future<String> openDebrief(String sessionId) async {
    final Object? v = await _mutateValue('commands/debrief:open', <String, dynamic>{'sessionId': sessionId});
    return decodeDebriefThread(v);
  }

  @override
  Future<void> setSessionPlace({required String sessionId, required String? placeId}) =>
      _mutate('commands/sessions:setPlace', <String, dynamic>{'sessionId': sessionId, 'placeId': placeId});

  @override
  Future<void> logSessionText({
    required String sessionId,
    required String type,
    required String text,
    required int at,
  }) {
    return _mutate('commands/sessions:logText', <String, dynamic>{
      'sessionId': sessionId,
      'type': type,
      'text': text,
      'at': at,
    });
  }

  @override
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) {
    return _mutate('commands/goals:create', <String, dynamic>{
      'goalId': goalId,
      'title': title,
      'kind': kind,
      if (exercise != null) 'exercise': exercise,
      if (targetKg != null) 'targetKg': targetKg,
      if (sessionsPerWeek != null) 'sessionsPerWeek': sessionsPerWeek,
    });
  }

  @override
  Future<void> updateGoal(String goalId, GoalPatch patch) =>
      _mutate('commands/goals:update', <String, dynamic>{'goalId': goalId, ...patch.toJson()});

  @override
  Future<void> removeGoal(String goalId) =>
      _mutate('commands/goals:remove', <String, dynamic>{'goalId': goalId});

  @override
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  }) {
    return _mutate('commands/context:create',
        <String, dynamic>{'itemId': itemId, 'text': text, 'topic': topic});
  }

  @override
  Future<void> updateContext(String itemId, ContextPatch patch) =>
      _mutate('commands/context:update', <String, dynamic>{'itemId': itemId, ...patch.toJson()});

  @override
  Future<void> removeContext(String itemId) =>
      _mutate('commands/context:remove', <String, dynamic>{'itemId': itemId});

  @override
  Future<void> removeImport(String importId) =>
      _mutate('commands/imports:remove', <String, dynamic>{'importId': importId});

  @override
  Future<void> saveLimit(Limit limit) =>
      _mutate('commands/limits:save', <String, dynamic>{'limit': limit.toWire()});

  @override
  Future<void> removeLimit(String limitId) =>
      _mutate('commands/limits:remove', <String, dynamic>{'limitId': limitId});

  @override
  Future<void> addRecord(LimitRecord record) =>
      _mutate('commands/limits:addRecord', <String, dynamic>{'record': record.toJson()});

  @override
  Future<void> removeRecord(String recordId) =>
      _mutate('commands/limits:removeRecord', <String, dynamic>{'recordId': recordId});

  @override
  Future<void> saveCheckin(Checkin checkin) =>
      _mutate('commands/limits:checkin', <String, dynamic>{'checkin': checkin.toJson()});

  @override
  Future<void> createThread({required String threadId, String? title, String? placeId, ThreadAbout? about}) =>
      _mutate('commands/threads:create', <String, dynamic>{
        'threadId': threadId,
        if (title != null) 'title': title,
        if (placeId != null) 'placeId': placeId,
        if (about != null) 'about': about.toJson(),
      });

  @override
  Future<void> renameThread({required String threadId, required String title}) =>
      _mutate('commands/threads:rename', <String, dynamic>{'threadId': threadId, 'title': title});

  @override
  Future<void> removeThread(String threadId) =>
      _mutate('commands/threads:remove', <String, dynamic>{'threadId': threadId});

  @override
  Future<void> sendMessage({
    required String threadId,
    required String messageId,
    required String text,
    List<String> fileIds = const <String>[],
    ChatContext? context,
    ChatAnswer? answer,
  }) {
    return _mutate('commands/messages:send', <String, dynamic>{
      'threadId': threadId,
      'messageId': messageId,
      'text': text,
      if (fileIds.isNotEmpty) 'fileIds': fileIds,
      if (context != null) 'context': context.toJson(),
      if (answer != null) 'answer': answer.toJson(),
    });
  }

  @override
  Future<TranscriptResult> transcribeAudio(String fileId) async {
    try {
      final Object? v = await _caller
          .action('commands/voice:transcribe', <String, dynamic>{'token': _token, 'fileId': fileId});
      if (v is Map) {
        final Object? text = v['text'];
        if (v['ok'] == true && text is String && text.trim().isNotEmpty) {
          return TranscriptResult.text(text);
        }
        final Object? why = v['reason'];
        return TranscriptResult.failed(why is String && why.isNotEmpty ? why : 'No speech was heard.');
      }
      return const TranscriptResult.failed('The answer was not understood.');
    } on cx.ConvexException catch (e) {
      // Never use e.message: it carries a server stack trace.
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Future<void> retryVoice(String messageId) =>
      _mutate('commands/messages:retryVoice', <String, dynamic>{'messageId': messageId});

  @override
  Future<FileMeta> uploadFile({
    required String fileId,
    required String name,
    required String mime,
    required List<int> bytes,
  }) async {
    final Object? url = await _mutateValue('commands/files:generateUploadUrl', <String, dynamic>{});
    if (url is! String || url.isEmpty) {
      throw const ConvexCallException('The server gave no upload address.');
    }
    final String storageId;
    try {
      final http.Response r = await _http
          .post(Uri.parse(url), headers: <String, String>{'Content-Type': mime}, body: bytes)
          .timeout(uploadTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw const ConvexCallException('The upload was refused. Try again.');
      }
      final Object? body = jsonDecode(r.body);
      final Object? id = body is Map ? body['storageId'] : null;
      if (id is! String || id.isEmpty) {
        throw const ConvexCallException('The upload answer was not understood.');
      }
      storageId = id;
    } on TimeoutException {
      throw const ConvexCallException.unreachable();
    } on SocketException {
      throw const ConvexCallException.unreachable();
    } on http.ClientException {
      throw const ConvexCallException.unreachable();
    } on FormatException {
      throw const ConvexCallException('The upload answer was not understood.');
    }
    final Object? meta = await _mutateValue('commands/files:register', <String, dynamic>{
      'fileId': fileId,
      'storageId': storageId,
      'name': name,
      'mime': mime,
      'size': bytes.length,
    });
    try {
      return decodeFileMeta(meta);
    } catch (_) {
      throw const ConvexCallException('The server sent an answer the app does not understand.');
    }
  }

  @override
  Future<FileLink?> fileLink(String fileId) async {
    try {
      final Object? v = await _caller
          .query('queries/files:get', <String, dynamic>{'token': _token, 'fileId': fileId});
      return decodeFileLink(v);
    } on cx.ConvexException catch (e) {
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Future<void> removeFile(String fileId) =>
      _mutate('commands/files:remove', <String, dynamic>{'fileId': fileId});

  @override
  Future<void> startImport({required String importId, required List<String> fileIds}) =>
      _mutate('commands/imports:start', <String, dynamic>{'importId': importId, 'fileIds': fileIds});

  @override
  Future<void> setAiModel(String? model) =>
      _mutate('commands/settings:setAiModel', <String, dynamic>{'model': model});

  @override
  Future<void> refreshModels() =>
      _mutate('commands/settings:refreshModels', const <String, dynamic>{});

  @override
  Future<void> syncTracker({required List<TrackerDay> days, required List<TrackerWorkout> workouts}) =>
      _mutate('commands/tracker:sync', <String, dynamic>{
        'days': days.map(trackerDayJson).toList(),
        'workouts': workouts.map(trackerWorkoutJson).toList(),
      });

  Future<void> _mutate(String name, Map<String, dynamic> args) async {
    await _mutateValue(name, args);
  }

  Future<Object?> _mutateValue(String name, Map<String, dynamic> args) async {
    try {
      return await _caller.mutate(name, <String, dynamic>{'token': _token, ...args}) as Object?;
    } on cx.ConvexException catch (e) {
      // Never use e.message: it carries a server stack trace.
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Future<AccessStatus> checkAccess() async {
    try {
      await _caller
          .query('queries/goals:list', <String, dynamic>{'token': _token}).timeout(accessTimeout);
      return AccessStatus.ok;
    } on TimeoutException {
      return AccessStatus.unreachable;
    } on cx.ConvexException catch (e) {
      return ConvexCallException.fromData(e.data).unauthorized
          ? AccessStatus.unauthorized
          : AccessStatus.failed;
    } catch (_) {
      return AccessStatus.unreachable;
    }
  }

  @override
  Future<void> dispose() async => _onDispose?.call();
}
