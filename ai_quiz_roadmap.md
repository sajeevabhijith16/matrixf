# AI Quiz Validation + Local Chat History — Implementation Roadmap (Modules F1–F8, G1–G4)

> **Two features, one document**: Track F (quiz comprehension checks after each AI answer) and Track G (hamburger-menu local chat history). Track G depends on nothing from Track F, so order between the two tracks is flexible, but each track's internal modules must go in order.
> **Pattern**: implement → verify → move on.

---

## Module Map

```
TRACK F — Quiz Validation
  F1 → DB migration: ai_quiz_cache table + match RPC
  F2 → MatrixApi extensions (quiz cache CRUD + retrieval)
  F3 → GeminiChatApi: generateQuizQuestion() method
  F4 → AiQuizService (mirrors AiCacheService's lookup/save pattern)
  F5 → ChatMessage model: add quiz-specific fields
  F6 → Quiz bubble UI (question + answer input + validation result)
  F7 → Wire quiz generation into _onSend flow
  F8 → End-to-end verification

TRACK G — Local Chat History
  G1 → Local storage service (SharedPreferences-based)
  G2 → Session lifecycle: start/save/list sessions
  G3 → Hamburger menu UI + history list + resume
  G4 → End-to-end verification
```

**Safe order within each track**: F1→F2→F3→F4→F5→F6→F7→F8, and G1→G2→G3→G4.

---
---

# TRACK F — Quiz Validation

## MODULE F1 — DB Migration

> **Where**: Supabase SQL Editor

### Steps

> **Design note (updated)**: `embedding` here represents the **original student question** that triggered this quiz — NOT the quiz question's own text. This mirrors `ai_qa_cache` exactly: same key (the original question), same reuse logic. That way, checking for a cached quiz is a single lookup using the embedding we already computed for the main answer cache check — no extra Gemini or embedding calls on a cache hit, and quiz generation only happens on a genuine cache miss, just like the main answer.

```sql
CREATE TABLE ai_quiz_cache (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id         TEXT        NOT NULL,
  original_question TEXT        NOT NULL, -- the student's question this quiz was generated from
  quiz_question     TEXT        NOT NULL,
  correct_answer    TEXT        NOT NULL,
  embedding         vector(768) NOT NULL, -- embedding of original_question, NOT quiz_question
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_quiz_cache_course
  ON ai_quiz_cache (course_id);

CREATE INDEX idx_ai_quiz_cache_embedding
  ON ai_quiz_cache
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE OR REPLACE FUNCTION match_quiz_cache(
  p_course_id TEXT,
  p_embedding vector(768),
  p_threshold FLOAT,
  p_count     INT DEFAULT 1
)
RETURNS TABLE (
  id              UUID,
  quiz_question   TEXT,
  correct_answer  TEXT,
  similarity      FLOAT
)
LANGUAGE sql STABLE AS $$
  SELECT
    id,
    quiz_question,
    correct_answer,
    1 - (embedding <=> p_embedding) AS similarity
  FROM ai_quiz_cache
  WHERE course_id = p_course_id
    AND 1 - (embedding <=> p_embedding) >= p_threshold
  ORDER BY embedding <=> p_embedding
  LIMIT p_count;
$$;

ALTER TABLE ai_quiz_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_read_quiz" ON ai_quiz_cache
  FOR SELECT USING (true);

CREATE POLICY "allow_insert_quiz" ON ai_quiz_cache
  FOR INSERT WITH CHECK (true);
```

### ✅ Verification — F1
```sql
INSERT INTO ai_quiz_cache (course_id, original_question, quiz_question, correct_answer, embedding)
VALUES ('test', 'what is integration', 'test question', 'test answer', array_fill(0.1, ARRAY[768])::vector(768));

SELECT * FROM match_quiz_cache('test', array_fill(0.1, ARRAY[768])::vector(768), 0.5);

DELETE FROM ai_quiz_cache WHERE course_id = 'test';
```
- [x] Insert, RPC, delete all succeed with expected results

---

## MODULE F2 — MatrixApi Extensions

> **File**: `lib/src/api.dart`

```dart
  // ─── AI Quiz Cache ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> callMatchQuizCache({
    required String courseId,
    required List<double> embedding,
    required double threshold,
    int count = 1,
  }) async {
    final result = await _rpcPost('match_quiz_cache', {
      'p_course_id': courseId,
      'p_embedding': embedding,
      'p_threshold': threshold,
      'p_count': count,
    });
    if (result == null) return [];
    return (result as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertQuizCache(Map<String, dynamic> row) async {
    await _restPost('ai_quiz_cache', row);
  }
```

### ✅ Verification — F2
Standard debug-button test: insert a fake row via `insertQuizCache`, confirm `callMatchQuizCache` retrieves it, matches your established pattern from Module 5's verification.

---

## MODULE F3 — GeminiChatApi: Quiz Question Generation

> **File**: `lib/src/ai/gemini_chat_api.dart`

### Step 1 — Add the method

```dart
  /// Generates one comprehension-check question (and its correct answer)
  /// testing understanding of [answerText], grounded in [courseContext].
  /// Returns null if parsing fails (caller should treat as "skip quiz
  /// this time" rather than erroring the whole chat flow).
  Future<QuizQuestion?> generateQuizQuestion({
    required String courseTitle,
    required String courseContext,
    required String answerText,
  }) async {
    if (_geminiApiKey.isEmpty) return null;

    final prompt =
        'Based on this explanation given to a student studying '
        '"$courseTitle":\n\n$answerText\n\n'
        'Write ONE short comprehension-check question testing whether the '
        'student understood this specific explanation. Then write the '
        'correct answer to that question.\n'
        'Respond in EXACTLY this format, nothing else:\n'
        'QUESTION: <the question>\n'
        'ANSWER: <the correct answer>';

    try {
      final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final data = jsonDecode(body) as Map<String, dynamic>;
      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = candidates.first['content'];
      if (content is! Map<String, dynamic> || content['parts'] is! List) return null;
      final text = (content['parts'] as List)
          .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
          .join();

      final qMatch = RegExp(r'QUESTION:\s*(.+?)(?=\nANSWER:|$)', dotAll: true).firstMatch(text);
      final aMatch = RegExp(r'ANSWER:\s*(.+)$', dotAll: true).firstMatch(text);
      if (qMatch == null || aMatch == null) return null;

      final question = qMatch.group(1)!.trim();
      final answer = aMatch.group(1)!.trim();
      if (question.isEmpty || answer.isEmpty) return null;

      return QuizQuestion(question: question, correctAnswer: answer);
    } catch (e) {
      return null;
    }
  }
```

### Step 2 — Add the `QuizQuestion` model

Add to `lib/src/ai/ai_models.dart`:
```dart
class QuizQuestion {
  const QuizQuestion({required this.question, required this.correctAnswer});
  final String question;
  final String correctAnswer;
}
```

### ✅ Verification — F3
Debug button calling `generateQuizQuestion` directly with a real course title/context/answer, confirm it returns a sensible `QuizQuestion` with non-empty `question` and `correctAnswer`. Test with deliberately weird input to confirm it returns `null` gracefully rather than throwing, if parsing fails.

---

## MODULE F4 — AiQuizService

> **File to create**: `lib/src/ai/ai_quiz_service.dart`
> Mirrors `AiCacheService`'s lookup/save pattern exactly, applied to quiz Q&A instead of chat Q&A.

```dart
import 'ai_models.dart';
import 'gemini_embedding_api.dart';
import 'gemini_chat_api.dart';
import '../api.dart';

enum ValidationResult { correct, incorrect }

class QuizValidation {
  const QuizValidation({
    required this.result,
    required this.correctAnswer,
    required this.similarity,
  });
  final ValidationResult result;
  final String correctAnswer;
  final double similarity;
}

class AiQuizService {
  AiQuizService({
    required GeminiEmbeddingApi embeddingApi,
    required GeminiChatApi chatApi,
    required MatrixApi matrixApi,
  })  : _embeddingApi = embeddingApi,
        _chatApi = chatApi,
        _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final GeminiChatApi _chatApi;
  final MatrixApi _matrixApi;

  static const double _reuseThreshold = 0.90; // original question similar enough to reuse its quiz
  static const double _correctThreshold = 0.80; // student answer similarity to count as correct

  /// Gets a quiz question tied to [originalQuestion] (the student's actual
  /// question, e.g. "What is integration?") — checking the cache FIRST via
  /// [originalQuestionEmbedding] (the SAME embedding already computed for
  /// the main answer cache lookup in _onSend — pass it in, don't re-embed).
  /// Only calls Gemini if no similar quiz is cached yet for this question,
  /// exactly mirroring how the main answer cache avoids redundant Gemini
  /// calls for repeat/similar questions.
  Future<QuizQuestion?> getQuizQuestion({
    required String courseId,
    required String courseTitle,
    required String courseContext,
    required String originalQuestion,
    required List<double> originalQuestionEmbedding,
    required String answerText,
  }) async {
    // 1. Check cache FIRST — zero Gemini calls on a hit.
    final existing = await _matrixApi.callMatchQuizCache(
      courseId: courseId,
      embedding: originalQuestionEmbedding,
      threshold: _reuseThreshold,
      count: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      final question = row['quiz_question']?.toString();
      final answer = row['correct_answer']?.toString();
      if (question != null && answer != null) {
        return QuizQuestion(question: question, correctAnswer: answer);
      }
    }

    // 2. Cache miss — generate a fresh quiz via Gemini.
    final generated = await _chatApi.generateQuizQuestion(
      courseTitle: courseTitle,
      courseContext: courseContext,
      answerText: answerText,
    );
    if (generated == null) return null;

    // 3. Cache it keyed by the ORIGINAL question's embedding (already have
    //    it — no extra embedding call needed here).
    await _matrixApi.insertQuizCache({
      'course_id': courseId,
      'original_question': originalQuestion,
      'quiz_question': generated.question,
      'correct_answer': generated.correctAnswer,
      'embedding': originalQuestionEmbedding,
    });
    return generated;
  }

  /// Validates the student's [studentAnswer] against [correctAnswer] via
  /// embedding cosine similarity.
  Future<QuizValidation> validateAnswer({
    required String studentAnswer,
    required String correctAnswer,
  }) async {
    final studentEmbedding = await _embeddingApi.embed(studentAnswer);
    final correctEmbedding = await _embeddingApi.embed(correctAnswer);
    final similarity = _cosineSimilarity(studentEmbedding, correctEmbedding);
    return QuizValidation(
      result: similarity >= _correctThreshold ? ValidationResult.correct : ValidationResult.incorrect,
      correctAnswer: correctAnswer,
      similarity: similarity,
    );
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
```
Add `import 'dart:math';` at the top for `sqrt`.

> **Note on thresholds**: `_correctThreshold = 0.80` is a starting estimate, NOT calibrated against real data yet — unlike your main chat cache thresholds, which you calibrated from actual measurements back in Module 6. Plan to recalibrate this the same way (ask a correct-ish answer and a wrong answer to the same quiz question, check real similarity scores, adjust) during F8 verification.

### ✅ Verification — F4
Standalone debug test: call `getQuizQuestion` twice with the same `originalQuestion`/`originalQuestionEmbedding` (embed the same test string both times) → first call should call Gemini and cache the result (visible as a new row in `ai_quiz_cache`); second call should hit the cache directly, returning the identical `QuizQuestion` with **no second Gemini call** — confirm this via a debug print showing the second call returns near-instantly compared to the first, or by temporarily adding a print inside `generateQuizQuestion` to confirm it's only invoked once across both calls. Call `validateAnswer` with an obviously correct vs obviously wrong student answer, confirm the similarity scores and resulting `ValidationResult` make sense.

---

## MODULE F5 — ChatMessage Model Extensions

> **File**: `lib/src/ai/ai_models.dart`

Add quiz-related fields to `ChatMessage`:
```dart
class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final bool isConfirm;
  final bool isQuiz;              // true = show quiz question + answer input
  final String? quizCorrectAnswer; // hidden from UI until validated
  final QuizValidation? quizResult; // null until student submits an answer

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.isConfirm = false,
    this.isQuiz = false,
    this.quizCorrectAnswer,
    this.quizResult,
  });

  ChatMessage copyWith({QuizValidation? quizResult}) => ChatMessage(
        role: role,
        content: content,
        timestamp: timestamp,
        isLoading: isLoading,
        isError: isError,
        isConfirm: isConfirm,
        isQuiz: isQuiz,
        quizCorrectAnswer: quizCorrectAnswer,
        quizResult: quizResult ?? this.quizResult,
      );
}
```
Import `ai_quiz_service.dart` for `QuizValidation`, or move `QuizValidation` into `ai_models.dart` instead to avoid a circular import (`ai_quiz_service.dart` importing `ai_models.dart` AND `ai_models.dart` importing `ai_quiz_service.dart` would fail) — **move `QuizValidation`/`ValidationResult` into `ai_models.dart`**, and have `ai_quiz_service.dart` import them from there instead of defining them itself. Adjust Module F4's code accordingly: remove the `QuizValidation`/`ValidationResult` class definitions from `ai_quiz_service.dart` and instead add `import 'ai_models.dart';` at its top.

### ✅ Verification — F5
`flutter analyze` on both files, zero warnings, confirms no circular import.

---

## MODULE F6 — Quiz Bubble UI

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add the quiz bubble widget

```dart
class _QuizBubble extends StatefulWidget {
  const _QuizBubble({
    required this.message,
    required this.onSubmit,
  });
  final ChatMessage message;
  final void Function(String studentAnswer) onSubmit;

  @override
  State<_QuizBubble> createState() => _QuizBubbleState();
}

class _QuizBubbleState extends State<_QuizBubble> {
  final TextEditingController _answerCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.message.quizResult;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text('Quick check', style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(widget.message.content),
          const SizedBox(height: 10),
          if (result == null) ...[
            TextField(
              controller: _answerCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                hintText: 'Your answer...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _submitting || _answerCtrl.text.trim().isEmpty
                      ? null
                      : () {
                          setState(() => _submitting = true);
                          widget.onSubmit(_answerCtrl.text.trim());
                        },
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit'),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  result.result == ValidationResult.correct ? Icons.check_circle : Icons.cancel,
                  color: result.result == ValidationResult.correct ? Colors.green : Colors.orange,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  result.result == ValidationResult.correct ? 'Correct!' : 'Not quite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: result.result == ValidationResult.correct ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Correct answer: ${result.correctAnswer}', style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
```

### Step 2 — Wire into `_buildBubble`

Find:
```dart
  Widget _buildBubble(ChatMessage m) {
    if (m.isLoading) return _LoadingBubble();
    if (m.isError) {
      return _ErrorBubble(
        message: m.content,
        onRetry: _onRetryLastMessage,
      );
    }
    if (m.isConfirm) {
```

Add right after the `isError` check:
```dart
    if (m.isQuiz) {
      return _QuizBubble(
        message: m,
        onSubmit: (answer) => _onQuizSubmit(m, answer),
      );
    }
    if (m.isConfirm) {
```

### ✅ Verification — F6
Temporarily seed a fake `ChatMessage(isQuiz: true, content: 'What is 2+2?', ...)` into `_messages` (same pattern as Module 8C's bubble test), confirm it renders correctly with input field and submit button. `_onQuizSubmit` doesn't exist yet — stub it as an empty method for this visual test only, remove after confirming, real implementation comes in F7.

---

## MODULE F7 — Wire Quiz Generation Into `_onSend`

> **File**: `lib/src/widgets/ai_chat_overlay.dart`
> **Key change from the original draft**: we now compute the question's embedding ONCE at the top of `_onSend`, and reuse that same embedding for both the main answer cache lookup AND the quiz cache lookup — matching the efficiency of the main answer flow exactly, per your feedback. This means `_onSend` needs to call `_embeddingApi.embed(trimmed)` directly instead of letting `_cacheService.lookup()` embed internally.

### Step 0 — Expose an embedding-accepting lookup on `AiCacheService` (if not already present)

Check whether `lib/src/ai/ai_cache_service.dart` already has a `lookupWithEmbedding(String courseId, List<double> embedding)` method (it does if you've implemented Module C6 from the RAG roadmap; skip this step if so). If not, add it now:
```dart
  /// Same as lookup(), but uses a pre-computed embedding instead of
  /// calling the embedding API again.
  Future<CacheResult> lookupWithEmbedding(
    String courseId,
    List<double> embedding,
  ) async {
    final rows = await _matrixApi.callMatchAiCache(
      courseId: courseId,
      embedding: embedding,
      threshold: _similarThreshold,
      count: 5,
    );
    if (rows.isEmpty) return CacheMiss();
    final entries = rows.map((r) => CacheEntry.fromRow(r)).toList();
    final exactMatches = entries.where((e) => e.similarity >= _exactThreshold).toList();
    if (exactMatches.isNotEmpty) {
      final chosen = exactMatches[_random.nextInt(exactMatches.length)];
      return CacheHit(chosen);
    }
    return CacheSimilar(entries.first);
  }
```

### Step 1 — Add the quiz service field

```dart
  late final AiQuizService _quizService;
```
Initialize in `didChangeDependencies()` alongside `_cacheService`:
```dart
      _quizService = AiQuizService(
        embeddingApi: _embeddingApi,
        chatApi: _chatApi,
        matrixApi: MatrixScope.of(context).api,
      );
```

### Step 2 — Compute the embedding once at the top of `_onSend`, reuse it everywhere

Find the start of the `try` block in `_onSend`:
```dart
    try {
      final result = await _cacheService.lookup(_selectedCourse!.id, trimmed);
```
Replace with:
```dart
    try {
      final questionEmbedding = await _embeddingApi.embed(trimmed);
      final result = await _cacheService.lookupWithEmbedding(
        _selectedCourse!.id,
        questionEmbedding,
      );
```

### Step 3 — Trigger quiz generation only on `CacheMiss` (genuinely new question)

In the `CacheMiss()` case, after the answer is added and saved, add the quiz call — passing the SAME `questionEmbedding` computed above, no re-embedding:
```dart
        case CacheMiss():
          final answer = await _chatApi.sendMessage(
            courseTitle: _selectedCourse!.title,
            courseContext: _courseContext,
            history: _messages.where((m) => !m.isLoading && !m.isError && !m.isConfirm).toList(),
            question: trimmed,
          );
          if (!mounted) return;
          setState(() {
            _messages.add(ChatMessage(role: ChatRole.assistant, content: answer, timestamp: DateTime.now()));
          });
          await _cacheService.save(_selectedCourse!.id, trimmed, answer);
          _generateQuizFor(
            originalQuestion: trimmed,
            originalQuestionEmbedding: questionEmbedding,
            answerText: answer,
          );
```

Add the new method (fire-and-forget, doesn't block the UI):
```dart
  Future<void> _generateQuizFor({
    required String originalQuestion,
    required List<double> originalQuestionEmbedding,
    required String answerText,
  }) async {
    if (_selectedCourse == null) return;
    try {
      final quiz = await _quizService.getQuizQuestion(
        courseId: _selectedCourse!.id,
        courseTitle: _selectedCourse!.title,
        courseContext: _courseContext,
        originalQuestion: originalQuestion,
        originalQuestionEmbedding: originalQuestionEmbedding,
        answerText: answerText,
      );
      if (quiz == null || !mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          content: quiz.question,
          timestamp: DateTime.now(),
          isQuiz: true,
          quizCorrectAnswer: quiz.correctAnswer,
        ));
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[AiChatSheet] Quiz generation failed (non-fatal): $e');
    }
  }
```

> **Note**: quiz generation is deliberately only wired to `CacheMiss` — not to `CacheHit`/`CacheSimilar` — since those paths mean the student asked something already answered before, and (per this same reuse logic) would already have a cached quiz too. We don't need a separate code path for that: if you DO want a quiz to appear even on a `CacheHit`, you'd add the identical `_generateQuizFor(...)` call in that branch too, using the same `questionEmbedding` — it would hit the quiz cache immediately with no extra Gemini call, consistent with everything above. Left out of the base plan to keep quiz appearances tied to genuinely new questions, but this is an easy toggle if you want quizzes on every answer instead.

### Step 3 — Handle quiz submission

```dart
  Future<void> _onQuizSubmit(ChatMessage quizMessage, String studentAnswer) async {
    if (quizMessage.quizCorrectAnswer == null) return;
    try {
      final result = await _quizService.validateAnswer(
        studentAnswer: studentAnswer,
        correctAnswer: quizMessage.quizCorrectAnswer!,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexOf(quizMessage);
        if (index != -1) {
          _messages[index] = quizMessage.copyWith(quizResult: result);
        }
      });
    } catch (e) {
      debugPrint('[AiChatSheet] Quiz validation failed: $e');
    }
  }
```

### ✅ Verification — F7
`flutter analyze` whole project, zero warnings.

---

## MODULE F8 — End-to-End Verification (Track F)

- [x] Ask a genuinely new question → main answer appears, then shortly after a quiz bubble appears below it
- [x] Submit an answer clearly matching the correct answer → shows "Correct!" with the correct answer shown
- [x] Submit an obviously wrong answer → shows "Not quite" with the correct answer shown
- [x] Ask the SAME (or very similar) question again in a new session → the identical quiz question/answer reappears (reused from cache), and Supabase `ai_quiz_cache` row count does NOT grow for this repeat — confirms zero extra Gemini calls, matching the main answer cache's efficiency exactly
- [x] Confirm quiz is skippable — send a new message without answering the quiz, everything continues normally
- [x] Recalibrate `_correctThreshold` using real similarity numbers from a few test answers, same process as Module 6
- [x] Cache-hit/similar answer paths (no NEW answer generated) do NOT trigger a quiz — confirm no quiz appears after a `CacheHit`

---
---

# TRACK G — Local Chat History

## MODULE G1 — Local Storage Service

> **File to create**: `lib/src/ai/local_chat_history.dart`
> **Depends on**: `shared_preferences` (already a dependency)

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_models.dart';

class ChatSession {
  ChatSession({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.messages,
    required this.lastUpdated,
  });

  final String id;
  final String courseId;
  final String courseTitle;
  final List<ChatMessage> messages;
  final DateTime lastUpdated;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'courseTitle': courseTitle,
        'lastUpdated': lastUpdated.toIso8601String(),
        'messages': messages
            .where((m) => !m.isLoading) // don't persist transient loading bubbles
            .map((m) => {
                  'role': m.role.name,
                  'content': m.content,
                  'timestamp': m.timestamp.toIso8601String(),
                  'isError': m.isError,
                  'isConfirm': m.isConfirm,
                  'isQuiz': m.isQuiz,
                  'quizCorrectAnswer': m.quizCorrectAnswer,
                })
            .toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        courseTitle: json['courseTitle'] as String,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        messages: (json['messages'] as List).map((m) {
          final map = m as Map<String, dynamic>;
          return ChatMessage(
            role: (map['role'] as String) == 'user' ? ChatRole.user : ChatRole.assistant,
            content: map['content'] as String,
            timestamp: DateTime.parse(map['timestamp'] as String),
            isError: map['isError'] as bool? ?? false,
            isConfirm: map['isConfirm'] as bool? ?? false,
            isQuiz: map['isQuiz'] as bool? ?? false,
            quizCorrectAnswer: map['quizCorrectAnswer'] as String?,
          );
        }).toList(),
      );
}

class LocalChatHistory {
  static const _storageKey = 'ai_chat_sessions';
  static const _maxSessions = 20;

  Future<List<ChatSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final sessions = list
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList();
      sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      return sessions;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSession(ChatSession session) async {
    final sessions = await loadAll();
    sessions.removeWhere((s) => s.id == session.id);
    sessions.insert(0, session);
    if (sessions.length > _maxSessions) {
      sessions.removeRange(_maxSessions, sessions.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> deleteSession(String id) async {
    final sessions = await loadAll();
    sessions.removeWhere((s) => s.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }
}
```

### ✅ Verification — G1
Debug test: create a fake `ChatSession`, `saveSession()`, `loadAll()`, confirm it round-trips correctly (same messages, same order). Save 25 fake sessions, confirm only the most recent 20 remain (cap enforcement).

---

## MODULE G2 — Session Lifecycle in Chat Sheet

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add session tracking fields

```dart
  final LocalChatHistory _history = LocalChatHistory();
  late final String _sessionId;
```
Initialize `_sessionId` in `initState()`:
```dart
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
```

### Step 2 — Save after every message change

Add a helper called after any `setState` that adds to `_messages`:
```dart
  void _persistSession() {
    if (_selectedCourse == null) return;
    _history.saveSession(ChatSession(
      id: _sessionId,
      courseId: _selectedCourse!.id,
      courseTitle: _selectedCourse!.title,
      messages: List.of(_messages),
      lastUpdated: DateTime.now(),
    ));
  }
```
Call `_persistSession();` at the end of: `_onCourseSelected`, `_onSend` (in the `finally` block), `_onConfirmYes`, `_sendDirect` (in `finally`), and `_onQuizSubmit`. This is a simple, slightly repetitive wiring — call it after every point where `_messages` changes and settles.

### Step 3 — Support resuming a past session

Add a constructor variant / method to load an existing session instead of starting fresh:
```dart
  Future<void> _resumeSession(ChatSession session) async {
    setState(() {
      _selectedCourse = AiCourse(id: session.courseId, title: session.courseTitle, slug: '');
      _messages
        ..clear()
        ..addAll(session.messages);
      _phase = _ChatPhase.chatting;
    });
    await _loadCourseContext(_selectedCourse!);
  }
```
Note: this reuses `_sessionId` from `initState()` — for resumed sessions, we actually want to KEEP THE SAME id (`session.id`), not generate a new one, so future saves overwrite the same history entry rather than creating a duplicate. Change `_sessionId` from `late final` to just `late String` (removable-final) and set it inside `_resumeSession`:
```dart
    _sessionId = session.id;
```

### ✅ Verification — G2
Chat normally, close the sheet, check `SharedPreferences` (via a debug print of `LocalChatHistory().loadAll()`) — confirm a session was saved with the right course and messages.

---

## MODULE G3 — Hamburger Menu UI

> **File**: `lib/src/widgets/ai_chat_overlay.dart`

### Step 1 — Add hamburger icon to the header

Find `_buildHeader()`:
```dart
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF18664B)),
```

Replace with:
```dart
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
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

### Step 2 — Add the history menu

```dart
  Future<void> _showHistoryMenu() async {
    final sessions = await _history.loadAll();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) {
          if (sessions.isEmpty) {
            return const Center(child: Text('No past conversations yet.'));
          }
          return ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final preview = s.messages.isNotEmpty ? s.messages.first.content : '';
              return ListTile(
                title: Text(s.courseTitle),
                subtitle: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    await _history.deleteSession(s.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _resumeSession(s);
                },
              );
            },
          );
        },
      ),
    );
  }
```

### ✅ Verification — G3
- [x] Hamburger icon visible top-left of the chat header
- [x] Tapping it shows past sessions with course title + first message preview
- [x] Tapping a session resumes it — full message history restored, including quiz bubbles with their prior validation state
- [x] Deleting a session removes it from the list and from storage
- [x] Empty state (no history yet) shows a friendly message, not a blank screen

---

## MODULE G4 — End-to-End Verification (Track G)

- [x] Have 3+ separate conversations across different courses, close the sheet each time
- [x] Open hamburger menu → all 3 appear, most recent first
- [x] Resume one → continue chatting → close → reopen menu → confirm it updated (not duplicated as a new entry)
- [x] Confirm history persists across a full app restart (not just hot reload) — this is the real test that `SharedPreferences` persistence works
- [x] Create 21+ sessions, confirm only the most recent 20 remain
- [x] `flutter analyze` whole project → zero errors