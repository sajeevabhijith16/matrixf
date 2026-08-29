# Revision Mode — Implementation Roadmap (Modules H1–H7)

> **What it is**: A toggle inside the AI chat sheet that quizzes the student using admin-authored Q&A (`module_qa`) instead of AI-generated questions. Zero Gemini calls for question content (it's pre-written); validation reuses embedding similarity, and the admin answer's embedding is cached at SAVE time (in `adminUpsertModuleQa`), so it's never re-embedded across any student/session — only the student's own typed answer needs a fresh embedding each time.
> **Reuses**: The existing `_QuizBubble` UI and `isQuiz`/`quizCorrectAnswer` fields from Track F (already present in your codebase) — Revision Mode questions render through the exact same bubble, just sourced differently and driving an auto-advance flow afterward.
> **Depends on**: Track F must already be implemented (confirmed — `ai_quiz_service.dart` is already imported in your `ai_chat_overlay.dart`).

---

## Module Map

```
H1 → DB migration + ModuleQa model + save-time embedding caching
H2 → Thread moduleId into the chat sheet (for module-scoped revision)
H3 → Capture the Q&A pool during course context loading
H4 → Shared cosine similarity utility + AiQuizService extension (use cached embeddings)
H5 → Revision session state machine (selection, retry queue, scoring)
H6 → UI: toggle button, auto-advance, summary screen
H7 → End-to-end verification
```

---
---

# MODULE H1 — DB Migration + Model + Save-Time Embedding

### Step 1 — SQL migration

```sql
ALTER TABLE module_qa ADD COLUMN embedding vector(768);
```
(pgvector is already enabled from Module 1 — no need to re-enable the extension.)

### Step 2 — Update `ModuleQa` in `lib/src/models/models.dart`

Find:
```dart
class ModuleQa {
  ModuleQa({
    required this.id,
    required this.question,
    required this.answer,
    this.answerImages = const [],
    this.displayOrder = 0,
  });

  factory ModuleQa.fromJson(Map<String, dynamic> json) => ModuleQa(
    id: json['id']?.toString() ?? '',
    question: json['question']?.toString() ?? '',
    answer: json['answer_text']?.toString() ?? '',
    answerImages: (json['answer_images'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String question;
  final String answer;
  final List<String> answerImages;
  final int displayOrder;
}
```

Replace with:
```dart
class ModuleQa {
  ModuleQa({
    required this.id,
    required this.question,
    required this.answer,
    this.answerImages = const [],
    this.displayOrder = 0,
    this.embedding,
  });

  factory ModuleQa.fromJson(Map<String, dynamic> json) => ModuleQa(
    id: json['id']?.toString() ?? '',
    question: json['question']?.toString() ?? '',
    answer: json['answer_text']?.toString() ?? '',
    answerImages: (json['answer_images'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    embedding: _parseEmbedding(json['embedding']),
  );

  final String id;
  final String question;
  final String answer;
  final List<String> answerImages;
  final int displayOrder;
  final List<double>? embedding; // null if not yet computed (older rows)
}

/// PostgREST returns pgvector columns as a bracketed string like
/// "[0.1,0.2,...]", not a native JSON array — this handles both that
/// string form and, defensively, a real List in case that ever changes.
List<double>? _parseEmbedding(dynamic raw) {
  if (raw == null) return null;
  if (raw is List) {
    return raw.map((e) => (e as num).toDouble()).toList();
  }
  if (raw is String) {
    final cleaned = raw.replaceAll('[', '').replaceAll(']', '').trim();
    if (cleaned.isEmpty) return null;
    try {
      return cleaned.split(',').map((s) => double.parse(s.trim())).toList();
    } catch (_) {
      return null;
    }
  }
  return null;
}
```

### Step 3 — Update `adminUpsertModuleQa` in `lib/src/api.dart` to compute + store the embedding

Find:
```dart
  Future<void> adminUpsertModuleQa({
    String? id,
    required String moduleId,
    required String question,
    required String answerText,
    int displayOrder = 0,
  }) async {
    _requireSession();
    if (id == null) {
      await _restPost('module_qa', {
        'module_id': moduleId,
        'question': question,
        'answer_text': answerText,
        'display_order': displayOrder,
      });
    } else {
      await _restPatch(
        'module_qa',
        {'id': 'eq.$id'},
        {
          'question': question,
          'answer_text': answerText,
          'display_order': displayOrder,
        },
      );
    }
  }
```

Replace with:
```dart
  Future<void> adminUpsertModuleQa({
    String? id,
    required String moduleId,
    required String question,
    required String answerText,
    int displayOrder = 0,
  }) async {
    _requireSession();

    // Compute the answer's embedding once, at save time, so it never needs
    // to be recomputed across any student/session during Revision Mode.
    // Non-fatal if it fails — the Q&A still saves, just without revision
    // support until the next edit succeeds in embedding it.
    List<double>? embedding;
    try {
      embedding = await GeminiEmbeddingApi().embed(answerText);
    } catch (e) {
      debugPrint('Failed to embed QA answer (non-fatal): $e');
    }

    final body = {
      'question': question,
      'answer_text': answerText,
      'display_order': displayOrder,
      if (embedding != null) 'embedding': embedding,
    };

    if (id == null) {
      await _restPost('module_qa', {'module_id': moduleId, ...body});
    } else {
      await _restPatch('module_qa', {'id': 'eq.$id'}, body);
    }
  }
```

Add the import at the top of `api.dart`:
```dart
import 'ai/gemini_embedding_api.dart';
```

### Step 4 — Update `getModuleText`'s `module_qa` select to include `embedding`

Find:
```dart
    final qaRows = await _restGet('module_qa', {
      'select': 'id,question,answer_text,answer_images,display_order',
      'module_id': 'eq.$moduleId',
      'order': 'display_order.asc',
    });
```

Replace with:
```dart
    final qaRows = await _restGet('module_qa', {
      'select': 'id,question,answer_text,answer_images,display_order,embedding',
      'module_id': 'eq.$moduleId',
      'order': 'display_order.asc',
    });
```

### ✅ Verification — H1

- [x] `flutter analyze lib/src/models/models.dart lib/src/api.dart` → zero warnings
- [x] Add/edit a Q&A entry via the admin screen → check Supabase Table Editor → `module_qa` → confirm the `embedding` column is now populated (not null) for that row
- [x] Edit an EXISTING Q&A's answer text → confirm the embedding updates too (not stale)
- [x] Open that module in ReaderScreen, tap Q&A → confirm the sheet still displays correctly (proves the added `embedding` field doesn't break existing `showQaSheet` rendering, since it just ignores the new field)

---
---

# MODULE H2 — Thread `moduleId` Into the Chat Sheet

> **Files**: `lib/src/widgets/ai_chat_overlay.dart`, `lib/src/screens/reader_screen.dart`

### Step 1 — Add `initialModuleId` parameter

In `ai_chat_overlay.dart`, find:
```dart
void openAiChatSheet(BuildContext context, {AiCourse? initialCourse}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(initialCourse: initialCourse),
  );
}
```

Replace with:
```dart
void openAiChatSheet(BuildContext context, {AiCourse? initialCourse, String? initialModuleId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(initialCourse: initialCourse, initialModuleId: initialModuleId),
  );
}
```

Find:
```dart
class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet({this.initialCourse});
  final AiCourse? initialCourse;
```

Replace with:
```dart
class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet({this.initialCourse, this.initialModuleId});
  final AiCourse? initialCourse;
  final String? initialModuleId;
```

### Step 2 — Store it in state

In `_AiChatSheetState`, add:
```dart
  String? _currentModuleId;
```
In `initState()`, find:
```dart
    if (widget.initialCourse != null) {
      _selectedCourse = widget.initialCourse;
```
Add right before it:
```dart
    _currentModuleId = widget.initialModuleId;
    if (widget.initialCourse != null) {
      _selectedCourse = widget.initialCourse;
```

### Step 3 — Pass the module ID from ReaderScreen

In `reader_screen.dart`'s `_openAiTutor`, find where `openAiChatSheet` is called and add `initialModuleId: data.module.id` to the call.

### ✅ Verification — H2
- [x] `flutter analyze` → zero warnings
- [x] Opening AI Tutor from ReaderScreen still works exactly as before (this step only adds a field, doesn't change existing behavior yet — the actual scoping logic comes in H3)

---
---

# MODULE H3 — Capture the Q&A Pool During Course Context Loading

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add pool-tracking fields

```dart
  final Map<String, List<ModuleQa>> _qaByModule = {};
  List<ModuleQa> get _allQaPool => _qaByModule.values.expand((l) => l).toList();
  List<ModuleQa> get _revisionPool {
    if (_currentModuleId != null && _qaByModule.containsKey(_currentModuleId)) {
      return _qaByModule[_currentModuleId!] ?? [];
    }
    return _allQaPool;
  }
```

### Step 2 — Populate it inside `_loadCourseContext`

Find the loop over modules inside `_loadCourseContext` (adjust to match whichever version you currently have — with or without Track C's RAG changes — the loop iterating `modules` and calling `api.getModuleText(m.id)` is the same either way). Right after the line that does `mergedMediaMap.addAll(text.mediaMap);` (or equivalent), add:
```dart
        _qaByModule[m.id] = text.questions.where((q) => q.embedding != null).toList();
```

So the loop body includes something like:
```dart
      for (final m in modules) {
        final text = await api.getModuleText(m.id);
        mergedMediaMap.addAll(text.mediaMap);
        _qaByModule[m.id] = text.questions.where((q) => q.embedding != null).toList();
        // ...whatever else your version already does (buffer.write, etc.)
      }
```
Only Q&A entries that already HAVE a computed embedding are included — older entries saved before H1 won't have one until an admin re-saves them.

### ✅ Verification — H3
Temporarily `debugPrint('${_qaByModule.map((k, v) => MapEntry(k, v.length))}')` right after the loop, confirm it shows the right module IDs with the right Q&A counts for a course you know has admin Q&A entered. Remove the debug print after confirming.

---
---

# MODULE H4 — Shared Cosine Similarity + AiQuizService Extension

> **Files**: `lib/src/ai/embedding_utils.dart` (new), `lib/src/ai/ai_quiz_service.dart`

### Step 1 — Create the shared utility

```dart
import 'dart:math';

double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (sqrt(normA) * sqrt(normB));
}
```

### Step 2 — Extend `AiQuizService.validateAnswer` to accept a pre-computed correct-answer embedding

This is the key efficiency piece: without this change, validating a Revision Mode answer would re-embed the admin's answer text every single time (wasting the exact embedding we cached in H1). Find your current `validateAnswer` method and its `_cosineSimilarity` helper — replace both with:

```dart
  /// Validates [studentAnswer] against [correctAnswer]. If
  /// [correctAnswerEmbedding] is provided (e.g. a cached embedding from
  /// module_qa), it's used directly instead of re-embedding correctAnswer —
  /// this is what Revision Mode uses to avoid redundant embedding calls.
  Future<QuizValidation> validateAnswer({
    required String studentAnswer,
    required String correctAnswer,
    List<double>? correctAnswerEmbedding,
  }) async {
    final studentEmbedding = await _embeddingApi.embed(studentAnswer);
    final correctEmbedding = correctAnswerEmbedding ?? await _embeddingApi.embed(correctAnswer);
    final similarity = cosineSimilarity(studentEmbedding, correctEmbedding);
    return QuizValidation(
      result: similarity >= _correctThreshold ? ValidationResult.correct : ValidationResult.incorrect,
      correctAnswer: correctAnswer,
      similarity: similarity,
    );
  }
```
Remove the old private `_cosineSimilarity` method from this file (now using the shared one) and add `import 'embedding_utils.dart';` at the top. Existing Track F call sites (which don't pass `correctAnswerEmbedding`) keep working unchanged, since it's optional.

### ✅ Verification — H4
- [x] `flutter analyze` on both files → zero warnings
- [x] Existing Track F quiz flow (Gemini-generated questions) still works exactly as before — confirms the optional parameter didn't break anything
- [x] Temporarily call `validateAnswer` with a manually-supplied `correctAnswerEmbedding` (any real embedding you have handy) and confirm it skips embedding `correctAnswer` — check via a debug print inside `generateQuizQuestion`/`embed` call sites, or just trust the code path (the `??` operator makes this straightforward to reason about)

---
---

# MODULE H5 — Revision Session State Machine

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add `ChatMessage.isRevisionQuestion` field

In `ai_models.dart`, add to `ChatMessage`:
```dart
  final bool isRevisionQuestion;
```
Add to constructor: `this.isRevisionQuestion = false,`. This distinguishes a Revision Mode quiz bubble from a one-off Track F quiz bubble, so submission behavior can differ (auto-advance + scoring vs just showing the result).

### Step 2 — Add revision session state

```dart
  bool _revisionMode = false;
  List<ModuleQa> _revisionRemaining = [];
  List<ModuleQa> _revisionRetryQueue = [];
  int _revisionCorrectCount = 0;
  int _revisionTotalAnswered = 0;
```

### Step 3 — Start / advance / end methods

```dart
  void _startRevisionMode() {
    if (_revisionPool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No revision questions available yet for this course.')),
      );
      return;
    }
    setState(() {
      _revisionMode = true;
      _revisionRemaining = List.of(_revisionPool)..shuffle();
      _revisionRetryQueue = [];
      _revisionCorrectCount = 0;
      _revisionTotalAnswered = 0;
    });
    _nextRevisionQuestion();
  }

  void _nextRevisionQuestion() {
    if (_revisionRemaining.isEmpty && _revisionRetryQueue.isNotEmpty) {
      _revisionRemaining = List.of(_revisionRetryQueue)..shuffle();
      _revisionRetryQueue = [];
    }
    if (_revisionRemaining.isEmpty) {
      _endRevisionMode();
      return;
    }
    final next = _revisionRemaining.removeAt(0);
    setState(() {
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        content: next.question,
        timestamp: DateTime.now(),
        isQuiz: true,
        isRevisionQuestion: true,
        quizCorrectAnswer: next.answer,
      ));
    });
    _scrollToBottom();
  }

  void _endRevisionMode() {
    final total = _revisionTotalAnswered;
    final correct = _revisionCorrectCount;
    setState(() {
      _revisionMode = false;
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        content: total == 0
            ? 'Revision session ended.'
            : 'Revision complete! You got $correct/$total correct.',
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }
```

### Step 4 — Handle revision-specific validation in `_onQuizSubmit`

Find your existing `_onQuizSubmit` (from Track F). Replace it with a version that branches on `isRevisionQuestion`:
```dart
  Future<void> _onQuizSubmit(ChatMessage quizMessage, String studentAnswer) async {
    if (quizMessage.quizCorrectAnswer == null) return;
    try {
      List<double>? correctEmbedding;
      if (quizMessage.isRevisionQuestion) {
        // Find the original ModuleQa to get its cached embedding.
        final match = _allQaPool.where((q) => q.answer == quizMessage.quizCorrectAnswer);
        if (match.isNotEmpty) correctEmbedding = match.first.embedding;
      }

      final result = await _quizService.validateAnswer(
        studentAnswer: studentAnswer,
        correctAnswer: quizMessage.quizCorrectAnswer!,
        correctAnswerEmbedding: correctEmbedding,
      );
      if (!mounted) return;

      setState(() {
        final index = _messages.indexOf(quizMessage);
        if (index != -1) {
          _messages[index] = quizMessage.copyWith(quizResult: result);
        }
      });

      if (quizMessage.isRevisionQuestion) {
        _revisionTotalAnswered++;
        if (result.result == ValidationResult.correct) {
          _revisionCorrectCount++;
        } else {
          // Find the original ModuleQa to requeue it.
          final match = _allQaPool.where((q) => q.question == quizMessage.content);
          if (match.isNotEmpty) _revisionRetryQueue.add(match.first);
        }
        // Brief pause so the student can see the result before advancing.
        await Future.delayed(const Duration(seconds: 2));
        if (mounted && _revisionMode) _nextRevisionQuestion();
      }
    } catch (e) {
      debugPrint('[AiChatSheet] Quiz validation failed: $e');
    }
  }
```

> **Note on matching by `answer`/`question` text**: this is a pragmatic way to find the original `ModuleQa` (for its embedding / for requeueing) without threading an extra ID through `ChatMessage`. It's reliable as long as two different admin questions never have byte-identical text — a reasonable assumption, but if you ever hit an edge case, the more robust fix would be adding a `sourceQaId` field to `ChatMessage` instead. Not doing that now to keep this change smaller, but flagging it as a known simplification.

### ✅ Verification — H5
`flutter analyze` whole project → zero warnings. Full behavioral testing happens in H7.

---
---

# MODULE H6 — UI: Toggle Button + Exit Control

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add the toggle button to the header

Find `_buildHeader()` (already modified in Track G to include the hamburger icon):
```dart
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _showHistoryMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 22,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF18664B)),
```

Add a revision toggle right after the hamburger icon:
```dart
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _showHistoryMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 22,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(_revisionMode ? Icons.school : Icons.school_outlined),
            tooltip: _revisionMode ? 'Exit Revision Mode' : 'Start Revision Mode',
            onPressed: _phase == _ChatPhase.chatting
                ? () => _revisionMode ? _endRevisionMode() : _startRevisionMode()
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 22,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF18664B)),
```

### Step 2 — Disable normal chat input while in Revision Mode

Find `_buildInputRow()`:
```dart
  Widget _buildInputRow() {
    final canSend = _phase == _ChatPhase.chatting && !_isSending;
```
Replace with:
```dart
  Widget _buildInputRow() {
    final canSend = _phase == _ChatPhase.chatting && !_isSending && !_revisionMode;
```
The rest of that method stays unchanged — this alone disables free-text input while revision is active, since the quiz bubble itself provides the answer input.

### ✅ Verification — H6
- [x] Toggle icon appears in header, changes appearance when active
- [x] Tapping it while in normal chat starts Revision Mode
- [x] Normal text input is disabled while Revision Mode is active
- [x] Tapping the toggle again while active exits Revision Mode early (shows the summary with whatever was answered so far)

---
---

# MODULE H7 — End-to-End Verification

Full stop, full re-run. Test with a course that has at least 3-4 admin-authored Q&A entries (with embeddings computed per H1) across at least 2 modules.

## ✅ Final Checklist

- [x] From ReaderScreen (module-specific entry): start Revision Mode → only questions from THAT module appear, not the whole course
- [x] From the general FAB (course-level entry, no specific module): start Revision Mode → questions from ALL modules in the course appear
- [x] Answer a question correctly (semantically, even if worded differently than the admin's answer) → shows "Correct!", auto-advances to next question after a short pause
- [x] Answer a question incorrectly → shows "Not quite" + the correct answer, auto-advances, and that question reappears again LATER in the same session (not immediately next)
- [x] Exhaust the full pool → summary message shows correct accurate count (e.g. "5/7 correct" — note total may exceed pool size if some were retried)
- [x] Exit Revision Mode early via the toggle → summary reflects partial progress, normal chat input re-enables
- [x] Confirm ZERO new Gemini calls happen for question content during a revision session (only the student's own answer gets embedded each time) — you can sanity-check this by temporarily adding a debug print inside `GeminiChatApi.sendMessage` and `generateQuizQuestion`, confirming neither fires during a pure revision session
- [x] Confirm normal AI chat (non-revision) still works completely unaffected
- [x] Confirm Track F's original Gemini-generated quiz (non-revision) still works completely unaffected — `isRevisionQuestion: false` path
- [x] `flutter analyze` on the entire project → zero errors