# AI Chatbot (RAG + Embeddings) — Modular Implementation Roadmap

> **Stack**: Flutter (Dart) · Gemini API (text-embedding-004 + gemini-2.0-flash) · Supabase (pgvector)
> **Pattern**: Each module is self-contained. Implement → verify → move on.
> **Run key**: `flutter run --dart-define=GEMINI_API_KEY=<your_key>`

---

## Module Map

```
MODULE 1  → Supabase DB Setup             (SQL only, no Flutter code)
MODULE 2  → Data Models                   (ai_models.dart)
MODULE 3  → Gemini Embedding API          (gemini_embedding_api.dart)
MODULE 4  → Gemini Chat API               (gemini_chat_api.dart)
MODULE 5  → MatrixApi Extensions          (api.dart additions)
MODULE 6  → Cache Service                 (ai_cache_service.dart)
MODULE 7  → Course Picker Widget          (course_picker.dart)
MODULE 8  → AI Chat Overlay & FAB         (ai_chat_overlay.dart)
MODULE 9  → App Integration               (app.dart + reader_screen.dart)
```

**Safe implementation order**: 1 → 2 → 5 → 3 → 4 → 6 → 7 → 8 → 9

---

## 📋 Overall Progress Tracker

| # | Module | Status | Notes |
|---|--------|--------|-------|
| 1 | Supabase DB Setup | ⬜ Not started | SQL only |
| 2 | Data Models | ⬜ Not started | Pure Dart, no deps |
| 3 | Gemini Embedding API | ⬜ Not started | |
| 4 | Gemini Chat API | ⬜ Not started | |
| 5 | MatrixApi Extensions | ⬜ Not started | Extends existing api.dart |
| 6 | Cache Service | ⬜ Not started | Depends on 2, 3, 5 |
| 7 | Course Picker Widget | ⬜ Not started | Depends on 2 |
| 8 | Chat Overlay & FAB | ⬜ Not started | Largest module |
| 9 | App Integration | ⬜ Not started | Final wiring |

---

---

# MODULE 1 — Supabase Database Setup

> **What it is**: The database foundation. Everything else depends on this being correct.
> **Files changed**: None (SQL only, run in Supabase Dashboard → SQL Editor)
> **Time estimate**: 10 minutes

---

## Steps

### 1.1 — Enable pgvector Extension
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### 1.2 — Create the Cache Table
```sql
CREATE TABLE ai_qa_cache (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   TEXT        NOT NULL,
  question    TEXT        NOT NULL,
  answer      TEXT        NOT NULL,
  embedding   vector(768) NOT NULL,
  hit_count   INTEGER     NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 1.3 — Create Indexes
```sql
-- Fast lookup by course
CREATE INDEX idx_ai_qa_cache_course
  ON ai_qa_cache (course_id);

-- Approximate nearest-neighbour vector search (cosine distance)
CREATE INDEX idx_ai_qa_cache_embedding
  ON ai_qa_cache
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

### 1.4 — Create the Vector Search RPC Function
```sql
CREATE OR REPLACE FUNCTION match_ai_cache(
  p_course_id TEXT,
  p_embedding vector(768),
  p_threshold FLOAT,
  p_count     INT DEFAULT 3
)
RETURNS TABLE (
  id          UUID,
  question    TEXT,
  answer      TEXT,
  similarity  FLOAT
)
LANGUAGE sql STABLE AS $$
  SELECT
    id,
    question,
    answer,
    1 - (embedding <=> p_embedding) AS similarity
  FROM ai_qa_cache
  WHERE course_id = p_course_id
    AND 1 - (embedding <=> p_embedding) >= p_threshold
  ORDER BY embedding <=> p_embedding
  LIMIT p_count;
$$;
```

### 1.5 — Set Row Level Security (RLS)
```sql
ALTER TABLE ai_qa_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_read" ON ai_qa_cache
  FOR SELECT USING (true);

CREATE POLICY "allow_insert" ON ai_qa_cache
  FOR INSERT WITH CHECK (true);

CREATE POLICY "allow_update_hit_count" ON ai_qa_cache
  FOR UPDATE USING (true);
```

---

## ✅ Verification Checklist — Module 1

- [ ] `SELECT extname FROM pg_extension WHERE extname = 'vector';` → returns `vector`
- [ ] `SELECT * FROM ai_qa_cache LIMIT 1;` → returns empty result with no error
- [ ] Supabase Dashboard → Database → Functions → `match_ai_cache` appears
- [ ] Manual test insert and cleanup:
```sql
INSERT INTO ai_qa_cache (course_id, question, answer, embedding)
VALUES ('test', 'test question', 'test answer',
        array_fill(0.1, ARRAY[768])::vector(768));
SELECT id, question FROM ai_qa_cache WHERE course_id = 'test';
DELETE FROM ai_qa_cache WHERE course_id = 'test';
```

---

---

# MODULE 2 — Data Models

> **What it is**: Pure Dart data classes. No API calls, no widgets. The shared vocabulary for all other modules.
> **File to create**: `lib/src/ai/ai_models.dart`
> **Depends on**: Nothing
> **Time estimate**: 15 minutes

---

## Steps

### 2.1 — Create the `ai` directory
Create folder: `lib/src/ai/`

### 2.2 — File contents: `lib/src/ai/ai_models.dart`

**`ChatRole` enum**
```dart
enum ChatRole { user, assistant }
```

**`ChatMessage` class**
```dart
class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;   // true = show animated typing indicator
  final bool isError;     // true = show error styling + retry button
  final bool isConfirm;   // true = show "Did you mean?" bubble with Yes/No

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.isConfirm = false,
  });
}
```

**`AiCourse` class** (lightweight projection of `Course`)
```dart
class AiCourse {
  final String id;
  final String title;
  final String slug;
  const AiCourse({required this.id, required this.title, required this.slug});
}
```

**`CacheEntry` class**
```dart
class CacheEntry {
  final String id;
  final String courseId;
  final String question;   // original text stored in cache
  final String answer;
  final double similarity; // cosine similarity score 0.0 – 1.0

  const CacheEntry({
    required this.id,
    required this.courseId,
    required this.question,
    required this.answer,
    required this.similarity,
  });
}
```

**`CacheResult` sealed class** (exhaustive switch in Dart 3)
```dart
sealed class CacheResult {}

class CacheHit extends CacheResult {
  final CacheEntry entry;
  CacheHit(this.entry);
}

class CacheSimilar extends CacheResult {
  final CacheEntry best;
  CacheSimilar(this.best);
}

class CacheMiss extends CacheResult {}
```

---

## ✅ Verification Checklist — Module 2

- [ ] `flutter analyze lib/src/ai/ai_models.dart` → zero warnings/errors
- [ ] Write a quick switch to confirm sealed exhaustiveness:
```dart
// Paste this anywhere temporarily to confirm compile-time exhaustiveness
void testSealed(CacheResult r) {
  switch (r) {
    case CacheHit(:final entry): print(entry.answer);
    case CacheSimilar(:final best): print(best.question);
    case CacheMiss(): print('miss');
  }
}
```
- [ ] All classes use `const` constructors where fields are all final

---

---

# MODULE 3 — Gemini Embedding API

> **What it is**: Sends a text string to Gemini's embedding model and receives a 768-number vector representing the semantic meaning of that text.
> **File to create**: `lib/src/ai/gemini_embedding_api.dart`
> **Depends on**: `dart:io`, `dart:convert` (no custom modules needed)
> **Time estimate**: 20 minutes

---

## How Embeddings Work (Quick Reference)

An embedding converts text into a list of ~768 numbers:
- "What is integration?" → `[0.12, -0.83, 0.41, ...]`
- "Explain integration"  → `[0.11, -0.81, 0.43, ...]` ← almost identical!
- "What is photosynthesis?" → `[0.89, 0.23, -0.62, ...]` ← very different

Similarity is measured with **cosine similarity** (1.0 = identical meaning, 0.0 = unrelated).

---

## Steps

### 3.1 — API Reference
```
POST https://generativelanguage.googleapis.com/v1beta/models/
     text-embedding-004:embedContent?key={GEMINI_API_KEY}

Request body:
{
  "model": "models/text-embedding-004",
  "content": { "parts": [{ "text": "What is integration?" }] },
  "taskType": "SEMANTIC_SIMILARITY"
}

Response:
{
  "embedding": {
    "values": [0.12, -0.83, 0.41, ...]   ← exactly 768 floats
  }
}
```

### 3.2 — Class structure
```dart
import 'dart:convert';
import 'dart:io';

const _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

class GeminiEmbeddingApi {
  GeminiEmbeddingApi({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'text-embedding-004:embedContent';

  /// Returns a 768-element embedding vector for [text].
  Future<List<double>> embed(String text) async {
    // 1. Build POST request
    // 2. Parse response['embedding']['values'] as List<double>
    // 3. Assert length == 768
    // 4. Throw descriptive exception on error
  }
}
```

### 3.3 — Implementation Notes
- Reuse the **same `dart:io` HttpClient pattern** from the existing `lib/src/api.dart`
- Parse: `(response['embedding']['values'] as List).cast<double>()`
- On non-200 status → throw `Exception('Embedding failed: ${response.statusCode}')`
- On empty API key → throw `Exception('GEMINI_API_KEY is not set. Use --dart-define.')`

---

## ✅ Verification Checklist — Module 3

- [ ] `flutter analyze lib/src/ai/gemini_embedding_api.dart` → zero warnings
- [ ] Add a **temporary debug button** to `ProfileScreen`:
```dart
ElevatedButton(
  onPressed: () async {
    final api = GeminiEmbeddingApi();
    final vec = await api.embed('What is integration?');
    debugPrint('Vector length: ${vec.length}');       // Must be 768
    debugPrint('First 5: ${vec.take(5).toList()}');
  },
  child: const Text('[DEBUG] Test Embedding'),
),
```
- [ ] Confirm printed length is exactly **768**
- [ ] Confirm the values are non-zero floats (not all zeros)
- [ ] Call with empty string → handled exception, not crash
- [ ] **Remove the debug button** after testing

---

---

# MODULE 4 — Gemini Chat API

> **What it is**: Sends a conversation (history + new question) plus course content as context to Gemini and returns the AI's answer string.
> **File to create**: `lib/src/ai/gemini_chat_api.dart`
> **Depends on**: Module 2 (`ChatMessage`, `ChatRole`), `dart:io`, `dart:convert`
> **Time estimate**: 25 minutes

---

## Steps

### 4.1 — API Reference
```
POST https://generativelanguage.googleapis.com/v1beta/models/
     gemini-2.0-flash:generateContent?key={GEMINI_API_KEY}

Request body:
{
  "system_instruction": {
    "parts": [{ "text": "You are an AI tutor for 'Mathematics'..." }]
  },
  "contents": [
    { "role": "user",  "parts": [{ "text": "What is integration?" }] },
    { "role": "model", "parts": [{ "text": "Integration is..." }] },
    { "role": "user",  "parts": [{ "text": "Give an example." }] }
  ]
}

Response:
{
  "candidates": [{
    "content": {
      "parts": [{ "text": "Sure! Here is an example..." }]
    }
  }]
}
```

### 4.2 — Important: Gemini role naming
```
ChatRole.user      → "user"
ChatRole.assistant → "model"    ← Gemini uses "model", NOT "assistant"
```

### 4.3 — Class structure
```dart
class GeminiChatApi {
  GeminiChatApi({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;

  /// [courseTitle]   – shown in system instruction
  /// [courseContext] – raw module text, trimmed to 20 000 chars
  /// [history]       – prior ChatMessages for multi-turn context
  /// [question]      – the current user question
  Future<String> sendMessage({
    required String courseTitle,
    required String courseContext,
    required List<ChatMessage> history,
    required String question,
  }) async { ... }
}
```

### 4.4 — System Instruction Template
```
You are an AI tutor for the course "[courseTitle]".
Your job is to answer student questions ONLY about the content of this course.
If a question is unrelated to the course, politely say:
"I can only help with questions about [courseTitle]. Please ask something related to the course."
Do not make up information. Base all your answers solely on the course content below.

--- COURSE CONTENT START ---
[courseContext trimmed to 20000 chars]
--- COURSE CONTENT END ---
```

### 4.5 — Course Context Loading
- The caller (`_AiChatSheetState`) fetches module text once on course selection using `matrixApi.listModulesByCourseId(courseId)`
- Concatenate titles + content of first 3 modules
- Trim to 20 000 characters total before passing to `sendMessage`

---

## ✅ Verification Checklist — Module 4

- [ ] `flutter analyze lib/src/ai/gemini_chat_api.dart` → zero warnings
- [ ] Add a **temporary debug button** to `ProfileScreen`:
```dart
ElevatedButton(
  onPressed: () async {
    final api = GeminiChatApi();
    final reply = await api.sendMessage(
      courseTitle: 'Mathematics',
      courseContext: 'Chapter 1: Integration is the area under a curve...',
      history: [],
      question: 'What is integration?',
    );
    debugPrint('Reply: $reply');
  },
  child: const Text('[DEBUG] Test Chat'),
),
```
- [ ] Confirm a non-empty, sensible answer is printed
- [ ] Ask an off-topic question ("What is the capital of France?") → AI refuses politely with course redirect
- [ ] Pass 2 prior messages in `history`, ask a follow-up → AI remembers context
- [ ] **Remove the debug button** after testing

---

---

# MODULE 5 — MatrixApi Extensions

> **What it is**: Adds new public methods to the existing `MatrixApi` class so the AI modules can talk to Supabase without duplicating HTTP boilerplate.
> **File to modify**: `lib/src/api.dart`
> **Depends on**: existing `api.dart` patterns
> **Time estimate**: 20 minutes

---

## Steps

All new methods go inside the existing `MatrixApi` class, after the existing banner methods.

### 5.1 — `listModulesByCourseId` (public, no auth required)
```dart
/// Returns all modules for a course ordered by display_order.
/// Used by the AI to build course context for Gemini.
Future<List<TextModule>> listModulesByCourseId(String courseId) async {
  final rows = await _restGet('modules', {
    'select':
        'id,course_id,title,description,display_order,price_inr,'
        'page_count,is_free_preview,is_free_for_members,module_type',
    'course_id': 'eq.$courseId',
    'order': 'display_order.asc',
  });
  return rows.map<TextModule>((r) => TextModule.fromJson(r)).toList();
}
```

### 5.2 — `callMatchAiCache` (calls the Supabase RPC)
```dart
/// Calls the match_ai_cache RPC for vector similarity search.
/// Returns rows sorted by similarity descending.
Future<List<Map<String, dynamic>>> callMatchAiCache({
  required String courseId,
  required List<double> embedding,
  required double threshold,
  int count = 3,
}) async {
  final result = await _rpcPost('match_ai_cache', {
    'p_course_id': courseId,
    'p_embedding': embedding,
    'p_threshold': threshold,
    'p_count': count,
  });
  if (result == null) return [];
  return (result as List).cast<Map<String, dynamic>>();
}
```

### 5.3 — `insertAiCache`
```dart
/// Inserts a new Q&A entry into the ai_qa_cache table.
Future<void> insertAiCache(Map<String, dynamic> row) async {
  await _restPost('ai_qa_cache', row);
}
```

### 5.4 — `patchAiCacheHitCount`
```dart
/// Increments the hit_count of a cache entry by 1.
Future<void> patchAiCacheHitCount(String id) async {
  // PostgREST does not support raw SQL expressions in PATCH body.
  // Workaround: first fetch current count, then patch with count + 1.
  final rows = await _restGet('ai_qa_cache', {
    'select': 'hit_count',
    'id': 'eq.$id',
    'limit': '1',
  });
  if (rows.isEmpty) return;
  final current = (rows.first['hit_count'] as num?)?.toInt() ?? 0;
  await _restPatch('ai_qa_cache', {'id': 'eq.$id'}, {
    'hit_count': current + 1,
  });
}
```

### 5.5 — Private `_rpcPost` helper (add once)
```dart
/// Calls a Supabase RPC function via POST to /rest/v1/rpc/{fn}.
Future<dynamic> _rpcPost(String fn, Map<String, dynamic> body) async {
  final request = await _client.postUrl(
    Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'),
  );
  _setRestHeaders(request);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  return _readResponse(await request.close());
}
```

---

## ✅ Verification Checklist — Module 5

- [ ] `flutter analyze lib/src/api.dart` → zero warnings
- [ ] `listModulesByCourseId('real-course-id')` → non-empty list logged
- [ ] `callMatchAiCache(...)` → returns `[]` when cache table is empty (no crash)
- [ ] `insertAiCache({...})` → row appears in Supabase table dashboard
- [ ] `patchAiCacheHitCount(id)` → `hit_count` increments in Supabase

---

---

# MODULE 6 — Cache Service

> **What it is**: The brain of the caching system. Takes a question, embeds it, searches the vector store, and decides whether to return a cached answer, ask for confirmation, or signal a miss.
> **File to create**: `lib/src/ai/ai_cache_service.dart`
> **Depends on**: Module 2 (models), Module 3 (embedding API), Module 5 (MatrixApi extensions)
> **Time estimate**: 40 minutes

---

## Steps

### 6.1 — Similarity Thresholds
```dart
static const double _exactThreshold   = 0.92;  // same question → return cached
static const double _similarThreshold = 0.75;  // related → ask "Did you mean?"
// below 0.75 → CacheMiss → call Gemini
```

### 6.2 — Class Structure
```dart
class AiCacheService {
  AiCacheService({
    required GeminiEmbeddingApi embeddingApi,
    required MatrixApi matrixApi,
  }) : _embeddingApi = embeddingApi,
       _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final MatrixApi _matrixApi;

  Future<CacheResult> lookup(String courseId, String question) async { ... }
  Future<void> save(String courseId, String question, String answer) async { ... }
  Future<void> incrementHit(String entryId) async { ... }
}
```

### 6.3 — `lookup()` Implementation
```
1. embedding = await _embeddingApi.embed(question)
2. rows = await _matrixApi.callMatchAiCache(
             courseId:  courseId,
             embedding: embedding,
             threshold: _similarThreshold,   ← fetch everything ≥ 0.75
             count:     3
           )
3. if rows.isEmpty → return CacheMiss()
4. best row = rows.first  (RPC already sorts by similarity DESC)
5. entry = CacheEntry.fromRow(best)
6. if entry.similarity >= _exactThreshold → return CacheHit(entry)
7. else                                   → return CacheSimilar(entry)
```

### 6.4 — `save()` Implementation
```
1. embedding = await _embeddingApi.embed(question)
2. Guard: quick = await _matrixApi.callMatchAiCache(
              courseId: courseId,
              embedding: embedding,
              threshold: _exactThreshold,   ← only 0.92+
              count: 1
            )
   if quick.isNotEmpty → return early (near-duplicate exists)
3. await _matrixApi.insertAiCache({
     'course_id': courseId,
     'question':  question,
     'answer':    answer,
     'embedding': embedding,   // List<double> → serialized as JSON array
   })
```

### 6.5 — `incrementHit()` Implementation
```
await _matrixApi.patchAiCacheHitCount(entryId)
```

### 6.6 — `CacheEntry.fromRow()` factory (add to ai_models.dart)
```dart
factory CacheEntry.fromRow(Map<String, dynamic> row) => CacheEntry(
  id:         row['id'] as String,
  courseId:   '',   // not returned by RPC
  question:   row['question'] as String,
  answer:     row['answer'] as String,
  similarity: (row['similarity'] as num).toDouble(),
);
```

---

## ✅ Verification Checklist — Module 6

- [ ] `flutter analyze lib/src/ai/ai_cache_service.dart` → zero warnings

Run these tests via a temporary debug button in sequence:

**Test 1 — Save a new entry:**
```dart
await cacheService.save('course-id', 'What is integration?', 'Integration is the area under a curve.');
// Verify: Supabase ai_qa_cache has 1 row with a real 768-dim vector
```

**Test 2 — Exact hit (same question):**
```dart
final r = await cacheService.lookup('course-id', 'What is integration?');
assert(r is CacheHit);   // similarity should be ~1.0
```

**Test 3 — Similar match (rephrased question):**
```dart
final r = await cacheService.lookup('course-id', 'Explain integration to me');
assert(r is CacheSimilar);   // similarity ~0.85–0.91
```

**Test 4 — Full miss (unrelated question):**
```dart
final r = await cacheService.lookup('course-id', 'What is photosynthesis?');
assert(r is CacheMiss);
```

**Test 5 — Deduplication guard:**
```dart
await cacheService.save('course-id', 'What is integration?', 'Another answer');
// Verify: still only 1 row in Supabase (no duplicate inserted)
```

- [ ] **Remove debug button** after all 5 tests pass

---

---

# MODULE 7 — Course Picker Widget

> **What it is**: A standalone autocomplete input — shows matching courses as the user types, like a Google Forms dropdown picker. No AI logic, no network calls (uses pre-loaded course list).
> **File to create**: `lib/src/widgets/course_picker.dart`
> **Depends on**: Module 2 (`AiCourse`), existing `MatrixScope`
> **Time estimate**: 35 minutes

---

## Steps

### 7.1 — Widget API (public interface)
```dart
class CoursePicker extends StatefulWidget {
  const CoursePicker({
    super.key,
    required this.courses,      // List<AiCourse>, pre-loaded from MatrixScope
    required this.onSelected,   // void Function(AiCourse course)
  });

  final List<AiCourse> courses;
  final void Function(AiCourse) onSelected;
  ...
}
```

### 7.2 — Layout
```
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'Which course would you like help with?',
      style: titleMedium,
    ),
    SizedBox(height: 12),
    TextField(
      hintText: 'Search courses...',
      prefixIcon: Icons.school_outlined,
      onChanged: _onQueryChanged,
    ),
    AnimatedSize(
      child: _filtered.isEmpty ? SizedBox.shrink() : _DropdownCard(),
    ),
  ]
)
```

### 7.3 — Filter logic
```dart
List<AiCourse> get _filtered => _query.trim().isEmpty
    ? []
    : courses
        .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
        .take(6)
        .toList();
```

### 7.4 — Dropdown card
- White `Material` card with 12dp rounded corners, `elevation: 4`
- Each item: `ListTile` with the title — **matching substring bolded** using `TextSpan`
- Tap → call `onSelected(course)`, parent transitions to chatting phase
- Max 6 items (scroll if more)
- "No courses match" message when filtered list is empty and query is non-empty

### 7.5 — Bold matching substring helper
```dart
TextSpan _highlightMatch(String title, String query) {
  final idx = title.toLowerCase().indexOf(query.toLowerCase());
  if (idx == -1) return TextSpan(text: title);
  return TextSpan(children: [
    TextSpan(text: title.substring(0, idx)),
    TextSpan(
      text: title.substring(idx, idx + query.length),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    TextSpan(text: title.substring(idx + query.length)),
  ]);
}
```

---

## ✅ Verification Checklist — Module 7

- [ ] **Temporarily add** `CoursePicker` to `HomeScreen` for isolated testing:
```dart
CoursePicker(
  courses: [
    AiCourse(id: '1', title: 'Mathematics', slug: 'mathematics'),
    AiCourse(id: '2', title: 'Physics',     slug: 'physics'),
    AiCourse(id: '3', title: 'Math Advanced', slug: 'math-advanced'),
  ],
  onSelected: (c) => debugPrint('Selected: ${c.title}'),
),
```
- [ ] Type "math" → "Mathematics" and "Math Advanced" appear, "Physics" hidden
- [ ] Matching letters "math" are **bold** in the suggestions
- [ ] Type "xyz" → "No courses match" text shown
- [ ] Clear field → dropdown disappears (no items when query is empty)
- [ ] Tap suggestion → `onSelected` fires, `debugPrint` logged
- [ ] `flutter analyze lib/src/widgets/course_picker.dart` → zero warnings
- [ ] **Remove the HomeScreen test** after verification

---

---

# MODULE 8 — AI Chat Overlay & FAB

> **What it is**: The entire visual layer — the floating action button, the full-screen chat sheet, the chat bubble list, the input row, the "Did you mean?" confirmation bubble, and the loading indicator.
> **File to create**: `lib/src/widgets/ai_chat_overlay.dart`
> **Depends on**: Modules 2–7 (all previous modules)
> **Time estimate**: 90 minutes (largest module)

---

## Steps

### 8.1 — `AiChatOverlay` (public wrapper widget)
```dart
class AiChatOverlay extends StatelessWidget {
  const AiChatOverlay({
    super.key,
    required this.child,
    this.initialCourse,   // non-null = skip course picker (ReaderScreen)
  });

  final Widget child;
  final AiCourse? initialCourse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          bottom: 20,
          right: 16,
          child: _AiFab(initialCourse: initialCourse),
        ),
      ],
    );
  }
}
```

### 8.2 — `_AiFab` (the floating button)

**Appearance:**
- Size: 56 × 56 circle
- Background: `LinearGradient` (brand green `#18664b` → teal `#0d9488`)
- Icon: `Icons.auto_awesome` (sparkle/AI icon), white
- Continuous **pulse animation**: scale oscillates between 0.97 and 1.03 over 2 seconds

**Behavior:**
- Tap: scale-down feedback (0.9) then open `_AiChatSheet` via `showModalBottomSheet`

### 8.3 — Chat Phase Enum
```dart
enum _ChatPhase {
  courseSelect,      // showing CoursePicker
  awaitingConfirm,   // showing "Did you mean?" bubble, input locked
  chatting,          // normal Q&A conversation
}
```

### 8.4 — `_AiChatSheet` state variables
```dart
_ChatPhase _phase;            // current phase
AiCourse? _selectedCourse;    // null until user selects
String _courseContext = '';   // fetched once, up to 20k chars of module text
List<ChatMessage> _messages = [];
CacheEntry? _pendingSimilar;  // the CacheSimilar entry awaiting Yes/No
String _pendingQuestion = ''; // original user question that triggered Similar
bool _isSending = false;
final TextEditingController _inputCtrl = TextEditingController();
final ScrollController _scrollCtrl = ScrollController();

// Services (initialized in initState)
late final GeminiEmbeddingApi _embeddingApi;
late final GeminiChatApi _chatApi;
late final AiCacheService _cacheService;
```

### 8.5 — Layout Structure
```
Column(
  children: [
    _SheetHandle(),              ← drag indicator pill
    _SheetHeader(),              ← title + close button
    Expanded(
      child: _phase == _ChatPhase.courseSelect
          ? _buildCoursePicker()
          : _buildChatList(),
    ),
    if (_phase != _ChatPhase.courseSelect)
      _InputRow(),               ← text field + send button
  ]
)
```

### 8.6 — `_buildChatList()` — Chat Bubble Types

| `ChatMessage` flag | Widget rendered |
|--------------------|----------------|
| `isLoading: true`  | Left-aligned 3-dot animated bubble |
| `isError: true`    | Red-tinted card + "Retry" button |
| `isConfirm: true`  | "Did you mean?" card with Yes/No buttons |
| Normal user msg    | Right-aligned filled pill, brand green |
| Normal AI msg      | Left-aligned white card with small AI avatar icon |

### 8.7 — `_onCourseSelected()` (phase transition)
```dart
Future<void> _onCourseSelected(AiCourse course) async {
  setState(() {
    _selectedCourse = course;
    _phase = _ChatPhase.chatting;
    _messages.add(ChatMessage(role: ChatRole.assistant,
      content: 'Hi! I\'m ready to help you with **${course.title}**. '
               'What would you like to learn today?',
      timestamp: DateTime.now(),
    ));
  });

  // Fetch course context in background (non-blocking)
  final api = MatrixScope.of(context).api;
  final modules = await api.listModulesByCourseId(course.id);
  final buffer = StringBuffer();
  for (final m in modules.take(3)) {
    final text = await api.getModuleText(m.id);
    buffer.write('${m.title}\n${text.content}\n\n');
    if (buffer.length > 20000) break;
  }
  _courseContext = buffer.toString().substring(0, buffer.length.clamp(0, 20000));
}
```

### 8.8 — `_onSend()` — Full Orchestration
```dart
Future<void> _onSend(String question) async {
  if (question.trim().isEmpty || _isSending) return;
  _inputCtrl.clear();

  setState(() {
    _isSending = true;
    _messages.add(ChatMessage(role: ChatRole.user, content: question, timestamp: DateTime.now()));
    _messages.add(ChatMessage(role: ChatRole.assistant, content: '', timestamp: DateTime.now(), isLoading: true));
  });
  _scrollToBottom();

  try {
    final result = await _cacheService.lookup(_selectedCourse!.id, question);
    setState(() => _messages.removeLast()); // remove loading bubble

    switch (result) {
      case CacheHit(:final entry):
        _messages.add(ChatMessage(role: ChatRole.assistant, content: entry.answer, timestamp: DateTime.now()));
        await _cacheService.incrementHit(entry.id);

      case CacheSimilar(:final best):
        _pendingSimilar = best;
        _pendingQuestion = question;
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          content: best.question,
          timestamp: DateTime.now(),
          isConfirm: true,
        ));
        setState(() => _phase = _ChatPhase.awaitingConfirm);

      case CacheMiss():
        final answer = await _chatApi.sendMessage(
          courseTitle:   _selectedCourse!.title,
          courseContext: _courseContext,
          history:       _messages.where((m) => !m.isLoading && !m.isError).toList(),
          question:      question,
        );
        _messages.add(ChatMessage(role: ChatRole.assistant, content: answer, timestamp: DateTime.now()));
        await _cacheService.save(_selectedCourse!.id, question, answer);
    }
  } catch (e) {
    setState(() {
      _messages.removeLast();
      _messages.add(ChatMessage(role: ChatRole.assistant, content: e.toString(),
        timestamp: DateTime.now(), isError: true));
    });
  } finally {
    setState(() => _isSending = false);
    _scrollToBottom();
  }
}
```

### 8.9 — Confirm bubble Yes/No handlers
```dart
void _onConfirmYes() {
  final answer = _pendingSimilar!.answer;
  final id = _pendingSimilar!.id;
  setState(() {
    _messages.removeLast();   // remove isConfirm bubble
    _messages.add(ChatMessage(role: ChatRole.assistant, content: answer, timestamp: DateTime.now()));
    _phase = _ChatPhase.chatting;
  });
  _cacheService.incrementHit(id);
}

Future<void> _onConfirmNo() async {
  final question = _pendingQuestion;
  setState(() {
    _messages.removeLast();   // remove isConfirm bubble
    _phase = _ChatPhase.chatting;
  });
  await _onSend(question);   // will hit CacheMiss and save a new entry
}
```

### 8.10 — Also expose as a top-level helper function
```dart
/// Opens the AI chat sheet. Call this from ReaderScreen.
void openAiChatSheet(BuildContext context, {AiCourse? initialCourse}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(initialCourse: initialCourse),
  );
}
```

---

## ✅ Verification Checklist — Module 8

### FAB
- [ ] FAB appears on all 5 main tabs
- [ ] FAB shows pulse animation
- [ ] FAB sits above the NavigationBar (use `bottom: 76` if nav bar is ~56px tall)
- [ ] Tapping FAB opens chat sheet with slide-up animation

### Course Select Phase
- [ ] Chat sheet opens in `courseSelect` phase (if no `initialCourse`)
- [ ] `CoursePicker` renders, filters, and fires `onSelected` correctly
- [ ] After selection, smooth transition to `chatting` phase
- [ ] AI greeting message appears immediately

### Chatting Phase — Cache Miss
- [ ] Type a question → user bubble appears immediately
- [ ] Loading indicator (3 dots) appears
- [ ] Gemini answer appears, loading indicator gone
- [ ] New row visible in Supabase `ai_qa_cache`

### Chatting Phase — Exact Cache Hit
- [ ] Ask the same question again → answer appears near-instantly (no Gemini call delay)
- [ ] `hit_count` incremented in Supabase

### Chatting Phase — Similar Match
- [ ] Ask a rephrased version → "Did you mean: [original]?" bubble appears with Yes/No
- [ ] Input row is disabled while in `awaitingConfirm` phase
- [ ] Tap **Yes** → cached answer shown, `hit_count` incremented
- [ ] Tap **No** → Gemini called with original question, new cache entry created

### Error Handling
- [ ] Disable network → error bubble appears with "Retry" button
- [ ] Tapping Retry re-sends the last question

---

---

# MODULE 9 — App Integration

> **What it is**: The final wiring. Plugs `AiChatOverlay` into the app shell and adds the AI button to `ReaderScreen`.
> **Files to modify**: `lib/src/app.dart`, `lib/src/screens/reader_screen.dart`
> **Depends on**: Module 8 (all other modules transitively)
> **Time estimate**: 20 minutes

---

## Steps

### 9.1 — Modify `lib/src/app.dart`

Add import at top of file:
```dart
import 'widgets/ai_chat_overlay.dart';
```

In `MatrixShell.build`, wrap the body:
```diff
  return Scaffold(
-   body: pages[safeTab],
+   body: AiChatOverlay(
+     child: pages[safeTab],
+   ),
    bottomNavigationBar: NavigationBar(
```

### 9.2 — Modify `lib/src/screens/reader_screen.dart`

Add import at top of file:
```dart
import '../widgets/ai_chat_overlay.dart';
import '../ai/ai_models.dart';
```

In `_buildAppBar()`, add a new `IconButton` after the Q&A button:
```diff
  IconButton(
    tooltip: 'Q & A',
    icon: const Icon(Icons.help_outline),
    onPressed: data == null ? null : () => showQaSheet(context, data.questions),
  ),
+ IconButton(
+   tooltip: 'AI Tutor',
+   icon: const Icon(Icons.auto_awesome),
+   onPressed: data == null
+       ? null
+       : () => openAiChatSheet(
+             context,
+             initialCourse: AiCourse(
+               id:    data.module.courseId,
+               title: data.module.title,
+               slug:  '',
+             ),
+           ),
+ ),
```

> **Why `slug: ''`**: The `ReaderScreen` only has `moduleId`; the course slug is not needed by the AI chat flow since it uses `courseId` for all Supabase queries.

---

## ✅ Final Verification Checklist — Module 9

- [ ] `flutter analyze` — zero errors across **entire project**
- [ ] `flutter run --dart-define=GEMINI_API_KEY=<your_key>` — app starts without error

### End-to-End Flow A (from any main tab)
- [ ] FAB visible on Home, Catalog, Library, Support, Profile
- [ ] Tap FAB → course picker opens
- [ ] Type partial course name → suggestions appear
- [ ] Select course → AI greets with course name
- [ ] Ask a question → Gemini answers, cached in Supabase
- [ ] Ask same question → instant cached reply
- [ ] Ask similar question → "Did you mean?" flow works

### End-to-End Flow B (from ReaderScreen)
- [ ] Open any module in ReaderScreen
- [ ] ✨ AI Tutor icon visible in AppBar (after module loads)
- [ ] Tap icon → chat opens directly in chatting phase (no course picker)
- [ ] AI greeting includes the module's course title
- [ ] Chat works normally (cache + Gemini)

### Edge Cases
- [ ] No `GEMINI_API_KEY` set → error bubble shown, app does not crash
- [ ] No courses in database → course picker shows empty state gracefully
- [ ] Network loss mid-conversation → error bubble with Retry, no crash
- [ ] ReaderScreen does **not** show the global FAB (it has its own Scaffold on top)

---

---

## 🔑 Environment Setup

```bash
# Run with Gemini key injected at build time
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE

# Add permanently to .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "matrixf (debug)",
      "request": "launch",
      "type": "dart",
      "args": ["--dart-define=GEMINI_API_KEY=YOUR_KEY_HERE"]
    }
  ]
}
```

Get your Gemini API key at: https://aistudio.google.com/apikey

---

## 🗺️ Dependency Graph

```
MODULE 1 (Supabase SQL)        — no deps
MODULE 2 (Models)              — no deps
MODULE 5 (MatrixApi ext)       — extends existing api.dart
MODULE 3 (Embedding API)       — dart:io only
MODULE 4 (Chat API)            — MODULE 2
MODULE 6 (Cache Service)       — MODULES 2 + 3 + 5
MODULE 7 (Course Picker)       — MODULE 2
MODULE 8 (Chat Overlay)        — MODULES 2 + 3 + 4 + 5 + 6 + 7
MODULE 9 (Integration)         — MODULE 8 (all transitively)
```
