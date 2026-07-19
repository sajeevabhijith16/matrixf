# Chunk-Based RAG for Course Content — Implementation Roadmap (Modules C1–C7)

> **Prerequisite**: Tracks A (rich formatting) and B (image descriptions) are complete.
> **What this replaces**: Today, `_loadCourseContext()` concatenates the first 3 modules' raw text (capped at 20,000 chars) and reuses that same blob for every question in the conversation. This roadmap replaces that with real retrieval: course content is split into chunks, each chunk is embedded once (via an admin "Reindex" action), and every question retrieves only the most relevant chunks — from ALL modules, not just the first 3.
> **Pattern**: Same as before — implement → verify → move on.

---

## Module Map

```
C1 → DB migration: course_content_chunks table + match RPC
C2 → Content chunker (boundary-aware text splitter)
C3 → MatrixApi extensions (chunk CRUD + retrieval RPC)
C4 → AiCourseIndexer service (the reindex pipeline)
C5 → Admin "Reindex Course" screen
C6 → Wire retrieval into the chat sheet (replace static context)
C7 → End-to-end verification
```

**Safe order**: C1 → C2 → C3 → C4 → C5 → C6 → C7

---

## 📋 Progress Tracker

| # | Module | Status |
|---|--------|--------|
| C1 | DB migration | 🔵 Manual — run SQL in Supabase |
| C2 | Content chunker | ✅ Done |
| C3 | MatrixApi extensions | ✅ Done |
| C4 | AiCourseIndexer service | ✅ Done |
| C5 | Admin reindex screen | ✅ Done |
| C6 | Wire retrieval into chat | ✅ Done |
| C7 | End-to-end verification | ⏳ Awaiting manual testing |

---
---

# MODULE C1 — DB Migration

> **Where**: Supabase SQL Editor
> **Depends on**: nothing

## Steps

### C1.1 — Create the chunks table
```sql
CREATE TABLE course_content_chunks (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   TEXT        NOT NULL,
  module_id   TEXT        NOT NULL,
  chunk_index INTEGER     NOT NULL,
  chunk_text  TEXT        NOT NULL,
  embedding   vector(768) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### C1.2 — Indexes
```sql
CREATE INDEX idx_course_chunks_course
  ON course_content_chunks (course_id);

CREATE INDEX idx_course_chunks_embedding
  ON course_content_chunks
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

### C1.3 — Retrieval RPC (top-k, no threshold — standard RAG retrieval)
```sql
CREATE OR REPLACE FUNCTION match_course_chunks(
  p_course_id TEXT,
  p_embedding vector(768),
  p_count     INT DEFAULT 5
)
RETURNS TABLE (
  id          UUID,
  module_id   TEXT,
  chunk_text  TEXT,
  similarity  FLOAT
)
LANGUAGE sql STABLE AS $$
  SELECT
    id,
    module_id,
    chunk_text,
    1 - (embedding <=> p_embedding) AS similarity
  FROM course_content_chunks
  WHERE course_id = p_course_id
  ORDER BY embedding <=> p_embedding
  LIMIT p_count;
$$;
```
Note: unlike `match_ai_cache`, there's no `p_threshold` here — we always want the top 5 closest chunks for a course, even if none are a great match, since the system instruction already tells Gemini to say when something is out of scope. Filtering by threshold here would risk returning zero chunks and leaving Gemini with no context at all.

### C1.4 — RLS
```sql
ALTER TABLE course_content_chunks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_read_chunks" ON course_content_chunks
  FOR SELECT USING (true);

CREATE POLICY "allow_insert_chunks" ON course_content_chunks
  FOR INSERT WITH CHECK (true);

CREATE POLICY "allow_delete_chunks" ON course_content_chunks
  FOR DELETE USING (true);
```

## ✅ Verification — C1

```sql
SELECT * FROM course_content_chunks LIMIT 1;
```
- [ ] Empty result, no error

```sql
INSERT INTO course_content_chunks (course_id, module_id, chunk_index, chunk_text, embedding)
VALUES ('test', 'test-mod', 0, 'test chunk', array_fill(0.1, ARRAY[768])::vector(768));

SELECT * FROM match_course_chunks('test', array_fill(0.1, ARRAY[768])::vector(768), 5);

DELETE FROM course_content_chunks WHERE course_id = 'test';
```
- [ ] Insert succeeds, RPC returns the test row with similarity ~1.0, delete succeeds

---
---

# MODULE C2 — Content Chunker

> **File to create**: `lib/src/ai/content_chunker.dart`
> **Depends on**: nothing

## Steps

### C2.1 — Create the file

```dart
/// Splits raw course content into chunks suitable for embedding, without
/// breaking apart fenced code blocks or $$ math blocks, and without
/// reformatting the original text — each chunk keeps its original
/// markdown/LaTeX syntax intact.
List<String> chunkCourseContent(String content, {int maxChunkChars = 1000}) {
  final segments = _splitIntoSegments(content);
  final chunks = <String>[];
  final current = StringBuffer();

  for (final seg in segments) {
    final trimmedSeg = seg.trim();
    if (trimmedSeg.isEmpty) continue;

    if (current.isNotEmpty &&
        current.length + trimmedSeg.length + 2 > maxChunkChars) {
      chunks.add(current.toString().trim());
      current.clear();
    }
    if (current.isNotEmpty) current.write('\n\n');
    current.write(trimmedSeg);
  }
  if (current.isNotEmpty) chunks.add(current.toString().trim());
  return chunks;
}

/// Splits [content] into paragraph-like segments on blank lines, EXCEPT
/// while inside a ``` fenced block or a $$ math block, where blank lines
/// (if any) do not count as a split point.
List<String> _splitIntoSegments(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final segments = <String>[];
  final buf = StringBuffer();
  bool inFence = false;
  bool inMath = false;

  void flush() {
    if (buf.isNotEmpty) {
      segments.add(buf.toString());
      buf.clear();
    }
  }

  for (final line in lines) {
    final isFenceLine = RegExp(r'^```').hasMatch(line.trim());
    final isMathLine = RegExp(r'^\$\$').hasMatch(line.trim());

    if (isFenceLine) {
      buf.writeln(line);
      inFence = !inFence;
      continue;
    }
    if (isMathLine && !inFence) {
      buf.writeln(line);
      inMath = !inMath;
      continue;
    }

    if (line.trim().isEmpty && !inFence && !inMath) {
      flush();
      continue;
    }

    buf.writeln(line);
  }
  flush();
  return segments;
}
```

Note: this deliberately does NOT reuse `Block`/`parseBlocks()` from `text_blocks.dart` — those classes strip original syntax (e.g. `HeadingBlock.text` has no `#`), and we want chunks to retain exact original formatting since they're both embedded AND shown to Gemini as literal course content.

### C2.2 — Analyze
```bash
flutter analyze lib/src/ai/content_chunker.dart
```
Expect zero warnings.

## ✅ Verification — C2

Temporary debug test:
```dart
final sample = '''
# Heading One

Some paragraph text here that is reasonably short.

```
code block should stay together
even with blank line inside it

still one block
```

## Heading Two

Another paragraph.
''';

final chunks = chunkCourseContent(sample, maxChunkChars: 100);
for (var i = 0; i < chunks.length; i++) {
  debugPrint('[AI-DEBUG] Chunk $i (${chunks[i].length} chars):\n${chunks[i]}\n---');
}
```
- [ ] The fenced code block (including its internal blank line) stays as ONE unbroken chunk, never split
- [ ] Chunks are roughly bounded by `maxChunkChars`, but a single large segment (like the code block) is kept whole even if it exceeds the limit
- [ ] Headings stay attached to reasonable following content where they fit
- [ ] Remove debug code after confirming

---
---

# MODULE C3 — MatrixApi Extensions

> **File to modify**: `lib/src/api.dart`
> **Depends on**: C1

## Steps

### C3.1 — Add chunk management methods

Add these in the "AI Chat Cache" section (or a new "AI RAG" section) of `MatrixApi`:

```dart
  // ─── Course Content RAG ──────────────────────────────────────────────────

  /// Deletes all existing chunks for a course. Called before reindexing.
  Future<void> adminDeleteCourseChunks(String courseId) async {
    _requireSession();
    await _restDelete('course_content_chunks', {'course_id': 'eq.$courseId'});
  }

  /// Inserts a single content chunk with its embedding.
  Future<void> adminInsertCourseChunk({
    required String courseId,
    required String moduleId,
    required int chunkIndex,
    required String chunkText,
    required List<double> embedding,
  }) async {
    _requireSession();
    await _restPost('course_content_chunks', {
      'course_id': courseId,
      'module_id': moduleId,
      'chunk_index': chunkIndex,
      'chunk_text': chunkText,
      'embedding': embedding,
    });
  }

  /// Retrieves the top [count] most relevant chunks for [courseId] given
  /// a question's [embedding]. Public, no auth — used during chat.
  Future<List<Map<String, dynamic>>> callMatchCourseChunks({
    required String courseId,
    required List<double> embedding,
    int count = 5,
  }) async {
    final result = await _rpcPost('match_course_chunks', {
      'p_course_id': courseId,
      'p_embedding': embedding,
      'p_count': count,
    });
    if (result == null) return [];
    return (result as List).cast<Map<String, dynamic>>();
  }

  /// Returns true if a course has at least one indexed chunk.
  Future<bool> courseHasChunks(String courseId) async {
    final rows = await _restGet('course_content_chunks', {
      'select': 'id',
      'course_id': 'eq.$courseId',
      'limit': '1',
    });
    return rows.isNotEmpty;
  }
```

### C3.2 — Analyze
```bash
flutter analyze lib/src/api.dart
```
Expect zero warnings.

## ✅ Verification — C3

Temporary debug button (use a real course id):
```dart
ElevatedButton(
  onPressed: () async {
    const testCourseId = 'YOUR_REAL_COURSE_ID';
    try {
      await scope.api.adminInsertCourseChunk(
        courseId: testCourseId,
        moduleId: 'test-mod',
        chunkIndex: 0,
        chunkText: 'Integration is the area under a curve.',
        embedding: List.filled(768, 0.1),
      );
      debugPrint('[AI-DEBUG] Insert done');

      final hasChunks = await scope.api.courseHasChunks(testCourseId);
      debugPrint('[AI-DEBUG] Has chunks: $hasChunks'); // expect true

      final rows = await scope.api.callMatchCourseChunks(
        courseId: testCourseId,
        embedding: List.filled(768, 0.1),
      );
      debugPrint('[AI-DEBUG] Match rows: ${rows.length}'); // expect 1

      await scope.api.adminDeleteCourseChunks(testCourseId);
      final afterDelete = await scope.api.courseHasChunks(testCourseId);
      debugPrint('[AI-DEBUG] Has chunks after delete: $afterDelete'); // expect false
    } catch (e) {
      debugPrint('[AI-DEBUG] Error: $e');
    }
  },
  child: const Text('[DEBUG] Test C3'),
),
```
- [ ] All four debug lines match expected values
- [ ] Remove debug button after confirming

---
---

# MODULE C4 — AiCourseIndexer Service

> **File to create**: `lib/src/ai/course_indexer.dart`
> **Depends on**: C2, C3

## Steps

### C4.1 — Create the file

```dart
import 'content_chunker.dart';
import 'gemini_embedding_api.dart';
import '../api.dart';

/// Progress callback: (modulesDone, totalModules, chunksIndexedSoFar)
typedef IndexProgressCallback = void Function(int modulesDone, int totalModules, int chunksIndexed);

class AiCourseIndexer {
  AiCourseIndexer({
    required GeminiEmbeddingApi embeddingApi,
    required MatrixApi matrixApi,
  })  : _embeddingApi = embeddingApi,
        _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final MatrixApi _matrixApi;

  /// Reindexes an entire course: deletes existing chunks, then chunks and
  /// embeds every module's content, inserting fresh rows.
  /// Returns the total number of chunks indexed.
  Future<int> reindexCourse(
    String courseId, {
    IndexProgressCallback? onProgress,
  }) async {
    await _matrixApi.adminDeleteCourseChunks(courseId);

    final modules = await _matrixApi.listModulesByCourseId(courseId);
    var chunksIndexed = 0;

    for (var i = 0; i < modules.length; i++) {
      final module = modules[i];
      final moduleText = await _matrixApi.getModuleText(module.id);
      final chunks = chunkCourseContent(
        '${module.title}\n${moduleText.content}',
      );

      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunkText = chunks[chunkIndex];
        final embedding = await _embeddingApi.embed(chunkText);
        await _matrixApi.adminInsertCourseChunk(
          courseId: courseId,
          moduleId: module.id,
          chunkIndex: chunkIndex,
          chunkText: chunkText,
          embedding: embedding,
        );
        chunksIndexed++;
      }

      onProgress?.call(i + 1, modules.length, chunksIndexed);
    }

    return chunksIndexed;
  }
}
```

Note: this calls `getModuleText()` which requires a signed-in session (per your existing `api.dart`) — since this only ever runs from the admin panel, the admin is always signed in, so this is safe as-is, no changes needed.

### C4.2 — Analyze
```bash
flutter analyze lib/src/ai/course_indexer.dart
```
Expect zero warnings.

## ✅ Verification — C4

Temporary debug button (use a real course with real module content — your Mathematics course):
```dart
ElevatedButton(
  onPressed: () async {
    final indexer = AiCourseIndexer(
      embeddingApi: GeminiEmbeddingApi(),
      matrixApi: scope.api,
    );
    final count = await indexer.reindexCourse(
      'YOUR_REAL_COURSE_ID',
      onProgress: (done, total, chunks) {
        debugPrint('[AI-DEBUG] Progress: $done/$total modules, $chunks chunks so far');
      },
    );
    debugPrint('[AI-DEBUG] Total chunks indexed: $count');
  },
  child: const Text('[DEBUG] Test C4 reindex'),
),
```
- [ ] Progress lines print incrementally as each module is processed
- [ ] Final count is a reasonable number (not 0, not absurdly high)
- [ ] Check Supabase Table Editor → `course_content_chunks` → rows exist for this course, each with a real 768-dim embedding
- [ ] Run it a SECOND time → confirm old chunks were deleted first (row count doesn't just keep growing — should be replaced, not appended)
- [ ] Remove debug button after confirming

---
---

# MODULE C5 — Admin "Reindex Course" Screen

> **File to create**: `lib/src/screens/admin_reindex_screen.dart`
> **Depends on**: C4
> **⚠️ Needs your input before finalizing**: I don't know how your admin panel currently navigates between screens (a drawer? a list of admin actions? named routes?). The screen below is written to be self-contained and usable on its own, but wiring a way to *get to* this screen from your existing admin UI needs the real navigation structure — share that when you reach this module.

## Steps (screen content — navigation entry point TBD)

```dart
import 'package:flutter/material.dart';

import '../ai/course_indexer.dart';
import '../ai/gemini_embedding_api.dart';
import '../app.dart';
import '../models/models.dart';

class AdminReindexScreen extends StatefulWidget {
  const AdminReindexScreen({super.key});

  @override
  State<AdminReindexScreen> createState() => _AdminReindexScreenState();
}

class _AdminReindexScreenState extends State<AdminReindexScreen> {
  List<Course> _courses = [];
  bool _loading = true;
  String? _activeCourseId;
  String _statusText = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      final courses = await MatrixScope.of(context).api.adminListCourses();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Failed to load courses: $e';
        _loading = false;
      });
    }
  }

  Future<void> _reindex(Course course) async {
    setState(() {
      _activeCourseId = course.id;
      _statusText = 'Starting...';
    });
    try {
      final indexer = AiCourseIndexer(
        embeddingApi: GeminiEmbeddingApi(),
        matrixApi: MatrixScope.of(context).api,
      );
      final count = await indexer.reindexCourse(
        course.id,
        onProgress: (done, total, chunks) {
          if (!mounted) return;
          setState(() => _statusText = 'Module $done/$total — $chunks chunks so far');
        },
      );
      if (!mounted) return;
      setState(() => _statusText = 'Done — $count chunks indexed for "${course.title}"');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error: $e');
    } finally {
      if (mounted) setState(() => _activeCourseId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reindex Courses (AI RAG)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_statusText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_statusText),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _courses.length,
                    itemBuilder: (context, index) {
                      final course = _courses[index];
                      final isActive = _activeCourseId == course.id;
                      return ListTile(
                        title: Text(course.title),
                        subtitle: Text(course.id),
                        trailing: isActive
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton(
                                onPressed: _activeCourseId == null ? () => _reindex(course) : null,
                                child: const Text('Reindex'),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
```

### ✅ Verification — C5 (once navigation is wired)

- [ ] Screen lists all real courses
- [ ] Tapping "Reindex" on one course shows live progress text, disables other reindex buttons while running
- [ ] Completion message shows a sensible chunk count
- [ ] `flutter analyze lib/src/screens/admin_reindex_screen.dart` → zero warnings

---
---

# MODULE C6 — Wire Retrieval Into the Chat Sheet

> **File to modify**: `lib/src/widgets/ai_chat_overlay.dart`
> **Depends on**: C3, and Track B's existing state (`_availableMedia`, `_courseMediaMap`)

This is the most significant behavioral change: instead of loading a static `_courseContext` once per course selection and reusing it for every question, we now retrieve fresh, question-specific chunks on every send — and reuse the SAME question embedding for both cache lookup and chunk retrieval (no duplicate embedding calls).

## Steps

### C6.1 — Simplify `_loadCourseContext`

Since content is no longer preloaded in bulk, this method now only needs to check whether the course has been indexed at all (for a fallback path), and keep the media-map loading from Track B.

Find the current `_loadCourseContext` (from Track B):
```dart
  Future<void> _loadCourseContext(AiCourse course) async {
    try {
      final api = MatrixScope.of(context).api;
      final modules = await api.listModulesByCourseId(course.id);
      final buffer = StringBuffer();
      final mergedMediaMap = <String, ModuleMedia>{};
      for (final m in modules.take(3)) {
        final text = await api.getModuleText(m.id);
        buffer.write('${m.title}\n${text.content}\n\n');
        mergedMediaMap.addAll(text.mediaMap);
        if (buffer.length > 20000) break;
      }
      final trimmedContext =
          buffer.toString().substring(0, buffer.length.clamp(0, 20000));

      final referencedKeys = extractMediaKeys(trimmedContext);
      final descriptions = referencedKeys.isEmpty
          ? <String, String>{}
          : await api.getImageDescriptions(referencedKeys.toList());

      if (!mounted) return;
      setState(() {
        _courseContext = trimmedContext;
        _courseMediaMap = mergedMediaMap;
        _availableMedia = descriptions;
      });
    } catch (e) {
      debugPrint('[AiChatSheet] Failed to load course context: $e');
    }
  }
```

Replace with:
```dart
  bool _courseIsIndexed = false;

  Future<void> _loadCourseContext(AiCourse course) async {
    try {
      final api = MatrixScope.of(context).api;
      final hasChunks = await api.courseHasChunks(course.id);

      if (!mounted) return;
      setState(() => _courseIsIndexed = hasChunks);

      if (hasChunks) {
        // RAG path: media map is still built from full module content since
        // images can appear anywhere; retrieval itself happens per-question
        // in _buildRetrievedContext(). No bulk course_context needed here.
        final modules = await api.listModulesByCourseId(course.id);
        final mergedMediaMap = <String, ModuleMedia>{};
        final allText = StringBuffer();
        for (final m in modules) {
          final text = await api.getModuleText(m.id);
          mergedMediaMap.addAll(text.mediaMap);
          allText.write(text.content);
        }
        final referencedKeys = extractMediaKeys(allText.toString());
        final descriptions = referencedKeys.isEmpty
            ? <String, String>{}
            : await api.getImageDescriptions(referencedKeys.toList());
        if (!mounted) return;
        setState(() {
          _courseMediaMap = mergedMediaMap;
          _availableMedia = descriptions;
        });
      } else {
        // Fallback: course not yet reindexed — use the old bulk-context
        // approach so chat still works, just without retrieval precision.
        final modules = await api.listModulesByCourseId(course.id);
        final buffer = StringBuffer();
        final mergedMediaMap = <String, ModuleMedia>{};
        for (final m in modules.take(3)) {
          final text = await api.getModuleText(m.id);
          buffer.write('${m.title}\n${text.content}\n\n');
          mergedMediaMap.addAll(text.mediaMap);
          if (buffer.length > 20000) break;
        }
        final trimmedContext =
            buffer.toString().substring(0, buffer.length.clamp(0, 20000));
        final referencedKeys = extractMediaKeys(trimmedContext);
        final descriptions = referencedKeys.isEmpty
            ? <String, String>{}
            : await api.getImageDescriptions(referencedKeys.toList());
        if (!mounted) return;
        setState(() {
          _courseContext = trimmedContext;
          _courseMediaMap = mergedMediaMap;
          _availableMedia = descriptions;
        });
      }
    } catch (e) {
      debugPrint('[AiChatSheet] Failed to load course context: $e');
    }
  }
```

> **Note on the fallback's media scan**: fetching `allText` for every module (not just 3) to scan for media keys is fine since it's only string concatenation for regex scanning, not what gets sent to Gemini — the actual per-question content sent to Gemini comes from retrieval, not this buffer.

### C6.2 — Add a helper to build per-question retrieved context

Add this method to `_AiChatSheetState`:
```dart
  /// Retrieves the most relevant chunks for [questionEmbedding] and joins
  /// them into a context string for this specific question. Falls back to
  /// the static _courseContext if the course isn't indexed yet.
  Future<String> _buildRetrievedContext(List<double> questionEmbedding) async {
    if (!_courseIsIndexed) return _courseContext;

    final rows = await MatrixScope.of(context).api.callMatchCourseChunks(
          courseId: _selectedCourse!.id,
          embedding: questionEmbedding,
          count: 5,
        );
    if (rows.isEmpty) return '';
    return rows.map((r) => r['chunk_text']?.toString() ?? '').join('\n\n---\n\n');
  }
```

### C6.3 — Update `_onSend` to compute the embedding once and reuse it

Find the start of the `try` block in `_onSend`:
```dart
    try {
      final result = await _cacheService.lookup(_selectedCourse!.id, trimmed);
      if (!mounted) return;
      setState(() => _messages.removeLast()); // remove loading bubble
```

Replace with:
```dart
    try {
      final questionEmbedding = await _embeddingApi.embed(trimmed);
      final result = await _cacheService.lookupWithEmbedding(
        _selectedCourse!.id,
        questionEmbedding,
      );
      if (!mounted) return;
      setState(() => _messages.removeLast()); // remove loading bubble
```

This requires a small addition to `AiCacheService` — a variant of `lookup()` that accepts a pre-computed embedding instead of recomputing it, so we only call `embed()` once per question total (previously `_cacheService.lookup()` computed its own embedding internally).

**Add to `ai_cache_service.dart`**, alongside the existing `lookup()`:
```dart
  /// Same as lookup(), but uses a pre-computed embedding instead of
  /// calling the embedding API again. Use this when the caller already
  /// has the question's embedding for another purpose (e.g. RAG retrieval).
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
    final exactMatches =
        entries.where((e) => e.similarity >= _exactThreshold).toList();

    if (exactMatches.isNotEmpty) {
      final chosen = exactMatches[_random.nextInt(exactMatches.length)];
      return CacheHit(chosen);
    }

    return CacheSimilar(entries.first);
  }
```
(This duplicates `lookup()`'s body intentionally rather than having `lookup()` call `lookupWithEmbedding()` internally with a freshly computed embedding — both are kept for clarity and because `lookup()` is still used elsewhere unchanged, e.g. nowhere else in this codebase currently, but keeping it avoids any risk of breaking something calling the old method signature.)

### C6.4 — Replace `_courseContext` usage in all 4 `sendMessage()` call sites with retrieved context

Each of the 4 call sites currently has `courseContext: _courseContext,`. Since retrieval must happen per-question now, add this line right before each `_chatApi.sendMessage(...)` call:
```dart
      final retrievedContext = await _buildRetrievedContext(questionEmbedding);
```
and change `courseContext: _courseContext,` to `courseContext: retrievedContext,` in all 4 sites (the two forced-regen branches, `CacheMiss`, and `_sendDirect`).

> **Note for `_sendDirect`**: this method doesn't currently compute a `questionEmbedding` at all (it bypasses cache lookup entirely per `_onConfirmNo`'s design). Add `final questionEmbedding = await _embeddingApi.embed(trimmed);` near the top of `_sendDirect`, before building `retrievedContext`.

### C6.5 — Analyze
```bash
flutter analyze lib/src/widgets/ai_chat_overlay.dart lib/src/ai/ai_cache_service.dart
```
Expect zero warnings on both.

## ✅ Verification — C6

- [ ] For an INDEXED course (reindexed via C4/C5): ask a question, confirm the answer is grounded in relevant retrieved chunks — check by asking about a topic from a module BEYOND the old "first 3 modules" limit, confirm it still answers correctly (proves retrieval spans all modules now)
- [ ] For a NON-indexed course: chat still works via the fallback path, no crash
- [ ] Cache hit/miss/similar flows still work correctly (unaffected by this change — same thresholds, same behavior, just fed by `lookupWithEmbedding` now)
- [ ] Confirm only ONE embedding API call happens per question (not two) — you can verify this by temporarily counting/logging inside `GeminiEmbeddingApi.embed()` if you want certainty

---
---

# MODULE C7 — End-to-End Verification

Full stop, full re-run.

## ✅ Final Checklist

- [ ] Reindex your real Mathematics course via the new admin screen, confirm chunk count in Supabase
- [ ] Ask a question about content from module 1 → correct, relevant answer
- [ ] Ask a question about content from a module PAST the old 3-module cap (if you have 4+ modules) → correct, relevant answer (this is the key proof RAG is working, since the old system physically could not see this content)
- [ ] Ask an off-topic question → still politely refuses per the system instruction
- [ ] Ask a question, then a rephrased version → cache hit/similar flow still works exactly as before
- [ ] Ask a question relevant to a described course image → image still renders correctly (Track B unaffected)
- [ ] Try a course that has NOT been reindexed yet → chat still works via fallback, no crash
- [ ] `flutter analyze` on the whole project → zero errors
- [ ] Reindex the same course a second time → old chunks replaced, not duplicated (row count in Supabase makes sense)

---

## 🗺️ Dependency Graph

```
C1 (DB migration)          — no deps
C2 (chunker)                — no deps
C3 (MatrixApi ext)          — C1
C4 (indexer service)        — C2, C3
C5 (admin screen)           — C4, needs real admin nav info
C6 (wire into chat)         — C3, Track B's existing state
C7 (final verification)     — everything above
```