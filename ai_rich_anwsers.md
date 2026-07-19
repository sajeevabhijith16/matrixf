# AI Rich Answers — Implementation Roadmap (Track A3–A5, Track B1–B7)

> **Prerequisite**: Modules A1 (shared `parseBlocks()` extraction into `lib/src/components/text_blocks.dart`) and A2 (`AiAnswerRenderer` widget at `lib/src/widgets/ai_answer_renderer.dart`) are already implemented and verified. This document picks up from there.
>
> **Pattern**: Same as before — implement → verify → move on. Do not skip a verification step.
>
> **Scope**: This document covers ONLY the rich-text-rendering + image-description feature. The base AI chat system (embeddings, cache, chat sheet, sign-in gating, etc.) is already built and out of scope here.

---

## Module Map

```
TRACK A (rich text formatting — no DB changes)
  A3 → Update Gemini system instruction to use formatting syntax
  A4 → Wire AiAnswerRenderer into the chat sheet (replace plain Text bubble)
  A5 → Verify rich formatting end-to-end

TRACK B (course image descriptions — DB + admin UI + AI wiring)
  B1 → DB migration: add description column to course_images
  B2 → MatrixApi extensions: save + fetch descriptions
  B3 → Admin UI: add description field to upload screen
  B4 → Token extraction helper: find [IMG:]/[GIF:] tokens in course text
  B5 → Wire chat sheet: build available-media list + real image rendering
  B6 → Extend system instruction with available-media section
  B7 → End-to-end verification
```

**Safe order**: A3 → A4 → A5 → B1 → B2 → B3 → B4 → B5 → B6 → B7

---

## 📋 Progress Tracker

| # | Module | Status |
|---|--------|--------|
| A1 | Extract shared parsing logic | ✅ Done |
| A2 | `AiAnswerRenderer` widget | ✅ Done |
| A3 | Gemini system instruction (formatting) | ⬜ Not started |
| A4 | Wire renderer into chat sheet | ⬜ Not started |
| A5 | Verify rich formatting | ⬜ Not started |
| B1 | DB migration (description column) | ⬜ Not started |
| B2 | MatrixApi extensions | ⬜ Not started |
| B3 | Admin UI: description field | ⬜ Not started |
| B4 | Token extraction helper | ⬜ Not started |
| B5 | Wire chat sheet: media list + rendering | ⬜ Not started |
| B6 | System instruction: available-media | ⬜ Not started |
| B7 | End-to-end verification | ⬜ Not started |

---
---

# MODULE A3 — Gemini System Instruction (Formatting)

> **File to modify**: `lib/src/ai/gemini_chat_api.dart`
> **Depends on**: nothing new (text-only prompt change)
> **Risk note**: This is a pure string change inside `sendMessage()`. It cannot affect app startup — if you see a crash on launch after this change, it is unrelated to this edit and should be diagnosed separately (device/emulator issue) before continuing.

## Steps

### A3.1 — Replace the system instruction

Find:
```dart
    final systemInstruction =
        'You are an AI tutor for the course "$courseTitle".\n'
        'Your job is to answer student questions ONLY about the content of '
        'this course.\n'
        'If a question is unrelated to the course, politely say:\n'
        '"I can only help with questions about $courseTitle. Please ask '
        'something related to the course."\n'
        'Do not make up information. Base all your answers solely on the '
        'course content below.\n\n'
        '--- COURSE CONTENT START ---\n'
        '$trimmedContext\n'
        '--- COURSE CONTENT END ---';
```

Replace with:
```dart
    final systemInstruction =
        'You are an AI tutor for the course "$courseTitle".\n'
        'Your job is to answer student questions ONLY about the content of '
        'this course.\n'
        'If a question is unrelated to the course, politely say:\n'
        '"I can only help with questions about $courseTitle. Please ask '
        'something related to the course."\n'
        'Do not make up information. Base all your answers solely on the '
        'course content below.\n\n'
        'FORMATTING: Use the following formatting only where it genuinely '
        'improves clarity — do not force it into every answer:\n'
        '- Headings: # for main heading, ## for subheading, ### for minor '
        'heading (use sparingly, only for longer multi-part answers)\n'
        '- **bold**, *italic*, `inline code` for emphasis\n'
        '- Bullet lists with "- " and numbered lists with "1. "\n'
        '- Tables: use markdown pipe format only, e.g.:\n'
        '  | Header 1 | Header 2 |\n'
        '  |----------|----------|\n'
        '  | value    | value    |\n'
        '  Do NOT use ASCII box-drawing tables (with +---+ borders).\n'
        '- Math: wrap inline math in single dollar signs like \$x^2\$, and '
        'standalone equations in double dollar signs on their own lines '
        'like \$\$\\int x^2 dx = \\frac{x^3}{3} + C\$\$. Use standard LaTeX '
        'syntax inside the dollar signs.\n'
        '- Code: use triple-backtick fenced blocks for code snippets.\n'
        'For a short, simple answer, plain sentences are fine — do not add '
        'headings or tables to a one-line answer.\n\n'
        '--- COURSE CONTENT START ---\n'
        '$trimmedContext\n'
        '--- COURSE CONTENT END ---';
```

### A3.2 — Analyze

```bash
flutter analyze lib/src/ai/gemini_chat_api.dart
```
Expect zero warnings.

## ✅ Verification — Module A3

Test the raw text output BEFORE wiring the renderer (isolates prompt issues from rendering issues).

Temporary debug button:
```dart
ElevatedButton(
  onPressed: () async {
    try {
      final api = GeminiChatApi();
      final reply = await api.sendMessage(
        courseTitle: 'Mathematics',
        courseContext: 'Chapter 1: Integration...\n(use your real course context)',
        history: [],
        question: 'Compare the power rule and constant multiple rule for '
            'integration, and show the general integration formula.',
      );
      debugPrint('[AI-DEBUG] Raw reply:\n$reply');
    } catch (e) {
      debugPrint('[AI-DEBUG] Error: $e');
    }
  },
  child: const Text('[DEBUG] Test A3 formatting'),
),
```

- [ ] Raw text contains `|` pipe characters forming a markdown table
- [ ] Raw text contains `$...$` or `$$...$$` for equations
- [ ] Raw text does NOT contain `+----+----+` ASCII table syntax
- [ ] Formatting is proportionate — not overstuffed with headings for a short answer
- [ ] Remove debug button after confirming

---
---

# MODULE A4 — Wire `AiAnswerRenderer` Into the Chat Sheet

> **File to modify**: `lib/src/widgets/ai_chat_overlay.dart`
> **Depends on**: A2 (`AiAnswerRenderer`), A3
> **Design decision already made**: AI answers become a full-width block (not the constrained ~75% bubble); user questions keep the bubble style.

## Steps

### A4.1 — Add the import

At the top of `ai_chat_overlay.dart`, add:
```dart
import 'ai_answer_renderer.dart';
```

### A4.2 — Replace `_AssistantBubble`

Find the `_AssistantBubble` class (added back in Module 8C):
```dart
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 8),
              child: Icon(Icons.auto_awesome, size: 16, color: Color(0xFF18664B)),
            ),
            Flexible(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
```

Replace with:
```dart
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF18664B)),
              const SizedBox(width: 6),
              Text(
                'AI Tutor',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF18664B),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AiAnswerRenderer(content: text),
        ],
      ),
    );
  }
}
```

### A4.3 — Analyze

```bash
flutter analyze lib/src/widgets/ai_chat_overlay.dart
```
Expect zero warnings.

## ✅ Verification — Module A4

- [ ] Full stop, full re-run
- [ ] Ask a plain simple question (e.g. "What is 2+2 in this context?") → still renders cleanly as a single paragraph, full-width white card, no visual regression
- [ ] User question bubble is UNCHANGED (still the right-aligned green pill)
- [ ] Loading/error/confirm bubbles are UNCHANGED (only `_AssistantBubble` was touched)
- [ ] `flutter analyze` on whole project → zero errors

---
---

# MODULE A5 — Verify Rich Formatting End-to-End

> No new code in this module — pure verification that A3 + A4 work together correctly.

## ✅ Verification — Module A5

Full stop, full re-run. In the AI Tutor chat for your real Mathematics course:

- [ ] Ask a question that should produce a comparison table (e.g. "Compare the power rule and the constant multiple rule for integration") → renders as an actual bordered table with a shaded header row, not raw `|` characters
- [ ] Ask a question that should produce an equation (e.g. "What is the general formula for the power rule of integration?") → renders as real math notation (via `flutter_math_fork`), not raw `$...$` text
- [ ] Ask a question with a natural multi-step structure (e.g. "Walk me through integration by parts step by step") → headings/numbered list render correctly if the AI chose to use them
- [ ] Ask a short, simple question (e.g. "What does 'dx' mean?") → answer stays plain/simple, no forced headings or tables
- [ ] Old cached plain-text answers from before this feature (if any still exist in `ai_qa_cache`) still render fine as a single paragraph, no crash
- [ ] Scroll performance in the chat list is still smooth with a long rich answer on screen (no jank/stutter)

---
---

# MODULE B1 — DB Migration: Description Column

> **What it is**: Adds a `description` column to `course_images`, the real source of truth for `[IMG: key]` tokens (per your confirmation).
> **Where**: Supabase SQL Editor
> **Depends on**: nothing

## Steps

### B1.1 — Add the column
```sql
ALTER TABLE course_images
ADD COLUMN description TEXT;
```

### B1.2 — (Optional but recommended) Backfill guidance
Existing rows will have `description = NULL`. That's fine — Module B4/B5 will simply skip tokens with no description when building the "available media" list for Gemini, since a token with no description gives Gemini no way to know what it shows.

## ✅ Verification — Module B1

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'course_images';
```
- [ ] `description` appears in the result, type `text`

```sql
SELECT token, storage_path, description FROM course_images LIMIT 5;
```
- [ ] Query runs with no error, `description` column visible (likely `null` for existing rows — expected)

---
---

# MODULE B2 — MatrixApi Extensions

> **File to modify**: `lib/src/api.dart`
> **Depends on**: B1

## Steps

### B2.1 — Update `adminUploadImageToken` to accept a description

Find:
```dart
  Future<String> adminUploadImageToken(String token, File file) async {
    _requireSession();

    final ext = file.path.split('.').last.toLowerCase();
    final storagePath = '$token.$ext';

    final bytes = await file.readAsBytes();
    final mimeType = _mimeFromExt(ext);

    final uploadUri = Uri.parse(
      '$supabaseUrl/storage/v1/object/course-images/$storagePath',
    );
    final request = await _client.postUrl(uploadUri);
    request.headers.set('apikey', supabaseAnonKey);
    request.headers.set(
      'Authorization',
      'Bearer ${session?.accessToken ?? supabaseAnonKey}',
    );
    request.headers.set('Content-Type', mimeType);
    request.headers.set('x-upsert', 'true');
    request.add(bytes);
    final response = await request.close();
    await _readResponse(response);

    await _restPost('course_images', {
      'token': token,
      'storage_path': storagePath,
    });

    return publicImageUrl(storagePath);
  }
```

Replace with:
```dart
  Future<String> adminUploadImageToken(
    String token,
    File file, {
    String? description,
  }) async {
    _requireSession();

    final ext = file.path.split('.').last.toLowerCase();
    final storagePath = '$token.$ext';

    final bytes = await file.readAsBytes();
    final mimeType = _mimeFromExt(ext);

    final uploadUri = Uri.parse(
      '$supabaseUrl/storage/v1/object/course-images/$storagePath',
    );
    final request = await _client.postUrl(uploadUri);
    request.headers.set('apikey', supabaseAnonKey);
    request.headers.set(
      'Authorization',
      'Bearer ${session?.accessToken ?? supabaseAnonKey}',
    );
    request.headers.set('Content-Type', mimeType);
    request.headers.set('x-upsert', 'true');
    request.add(bytes);
    final response = await request.close();
    await _readResponse(response);

    await _restPost('course_images', {
      'token': token,
      'storage_path': storagePath,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });

    return publicImageUrl(storagePath);
  }
```

> **Note**: this is an additive change (`description` is an optional named parameter) — any existing call site that doesn't pass it keeps working unchanged. You will need to see the actual call site in your admin screen to update it in B3.

### B2.2 — Add a way to update description on an existing token (for editing later)

Add this new method anywhere in the "Admin: image tokens" section:
```dart
  Future<void> adminUpdateImageDescription(String id, String description) async {
    _requireSession();
    await _restPatch('course_images', {'id': 'eq.$id'}, {
      'description': description.trim(),
    });
  }
```

### B2.3 — Add a public method to fetch descriptions for specific tokens

This is what the AI chat flow will call — public, no auth, since guests reading a course can still trigger the AI tutor sign-in flow which then needs this after sign-in.

Add near `listModulesByCourseId` (in the "AI Chat Cache" section):
```dart
  /// Returns {token: description} for the given tokens that have a
  /// non-null description set. Tokens with no description are omitted
  /// (nothing useful to tell Gemini about them).
  Future<Map<String, String>> getImageDescriptions(List<String> tokens) async {
    if (tokens.isEmpty) return {};
    final rows = await _restGet('course_images', {
      'select': 'token,description',
      'token': 'in.(${tokens.join(',')})',
    });
    final map = <String, String>{};
    for (final row in rows) {
      final token = row['token']?.toString();
      final description = row['description']?.toString();
      if (token != null && description != null && description.trim().isNotEmpty) {
        map[token] = description.trim();
      }
    }
    return map;
  }
```

> **Note on the `in.(...)` filter**: if any token contains a comma, this would break — check your token-naming convention. If tokens are simple slugs/UUIDs without commas (typical), this is safe as written.

### B2.4 — Analyze
```bash
flutter analyze lib/src/api.dart
```
Expect zero warnings.

## ✅ Verification — Module B2

Temporary debug button (use a real existing token from your `course_images` table):
```dart
ElevatedButton(
  onPressed: () async {
    try {
      // Manually set a description first via SQL for this test:
      // UPDATE course_images SET description = 'Diagram showing area under a curve' WHERE token = 'YOUR_REAL_TOKEN';
      final descriptions = await scope.api.getImageDescriptions(['YOUR_REAL_TOKEN', 'nonexistent_token']);
      debugPrint('[AI-DEBUG] Descriptions: $descriptions');
      // Expect: {YOUR_REAL_TOKEN: 'Diagram showing area under a curve'}
      // 'nonexistent_token' should be silently omitted, not cause an error.
    } catch (e) {
      debugPrint('[AI-DEBUG] Error: $e');
    }
  },
  child: const Text('[DEBUG] Test B2'),
),
```

- [ ] Set a description on a real token via SQL, confirm it's returned correctly
- [ ] A nonexistent/no-description token is silently omitted (not an error, not a null crash)
- [ ] `adminUpdateImageDescription` works — call it, confirm the value changes in Supabase Table Editor
- [ ] Remove debug button after testing

---
---

# MODULE B3 — Admin UI: Description Field

> **File to modify**: `lib/src/screens/upload_img_screen.dart`
> **Depends on**: B2
> **⚠️ This module cannot be written from this document alone.** I do not have the current content of `upload_img_screen.dart`. Before implementing this module, paste the full current file content (specifically the upload form/dialog and its call to `adminUploadImageToken`) so the diff can be written precisely, matching your actual widget structure — the same way every other file-editing module in this project has been handled. Do not guess at the form layout; get the real file first.

## Steps (to be finalized once the real file is shared)

The general shape of the change, regardless of the exact widget structure:

1. Add a `TextEditingController` for the description field (e.g. `_descriptionController`).
2. Add a `TextField`/`TextFormField` in the upload form UI, likely near the existing token input field, with a hint like "Describe what this image shows (helps the AI Tutor reference it)".
3. Update the call to `adminUploadImageToken(token, file)` to become `adminUploadImageToken(token, file, description: _descriptionController.text)`.
4. Dispose the new controller in `dispose()`.
5. If the screen also supports editing an existing token's metadata, wire a similar field to `adminUpdateImageDescription`.

## ✅ Verification — Module B3 (once implemented)

- [ ] Upload a new image with a description → confirm `description` is saved in Supabase (Table Editor)
- [ ] Upload a new image WITHOUT a description (leave field blank) → confirm it saves with `description = null`, no crash
- [ ] If edit support was added: edit an existing token's description → confirm it updates in Supabase
- [ ] `flutter analyze lib/src/screens/upload_img_screen.dart` → zero warnings

---
---

# MODULE B4 — Token Extraction Helper

> **File to modify**: `lib/src/components/text_blocks.dart`
> **Depends on**: nothing new (pure text scanning)

## Steps

### B4.1 — Add the extraction function

Add this function to `text_blocks.dart`, anywhere after the existing helpers:
```dart
/// Scans [content] for [IMG: key] / [GIF: key] tokens (both standalone-line
/// and inline forms) and returns the unique set of keys referenced.
/// Used to find which course images are relevant to offer the AI as
/// available media for a given course's chat context.
Set<String> extractMediaKeys(String content) {
  final regex = RegExp(r'\[(?:IMG|GIF):\s*([^\]]+)\]', caseSensitive: false);
  final keys = <String>{};
  for (final match in regex.allMatches(content)) {
    final key = match.group(1)?.trim();
    if (key != null && key.isNotEmpty) keys.add(key);
  }
  return keys;
}
```

### B4.2 — Analyze
```bash
flutter analyze lib/src/components/text_blocks.dart
```
Expect zero warnings.

## ✅ Verification — Module B4

Quick standalone test — temporarily paste into any debug button:
```dart
final keys = extractMediaKeys(
  'Some text [IMG: fig1] more text\n[GIF: anim2]\nMore [IMG:  fig1  ] duplicate',
);
debugPrint('[AI-DEBUG] Keys: $keys');
// Expect: {fig1, anim2} — exactly 2 unique keys, duplicate collapsed,
// whitespace trimmed correctly.
```
- [ ] Confirm exactly 2 unique keys returned, correctly trimmed
- [ ] Test with content containing no tokens at all → returns empty set, no crash
- [ ] Remove debug code after testing

---
---

# MODULE B5 — Wire Chat Sheet: Media List + Real Image Rendering

> **Files to modify**: `lib/src/widgets/ai_answer_renderer.dart`, `lib/src/widgets/ai_chat_overlay.dart`
> **Depends on**: A2, A4, B2, B4

This module has two parts: (1) make `AiAnswerRenderer` actually render real images instead of the Track-A placeholder, and (2) load the available media list alongside course context.

## Steps

### B5.1 — Update `AiAnswerRenderer` to accept a `mediaMap`

Find the constructor:
```dart
class AiAnswerRenderer extends StatelessWidget {
  const AiAnswerRenderer({super.key, required this.content});

  final String content;
```

Replace with:
```dart
class AiAnswerRenderer extends StatelessWidget {
  const AiAnswerRenderer({
    super.key,
    required this.content,
    this.mediaMap = const {},
  });

  final String content;
  final Map<String, ModuleMedia> mediaMap;
```

Add the import at the top of the file:
```dart
import 'dart:io';
import 'package:matrixf/src/models/models.dart';
```

### B5.2 — Replace the `MediaBlock` placeholder rendering

Find:
```dart
    } else if (b is MediaBlock) {
      // Track B wires real media lookup. For now (Track A), show a neutral
      // placeholder if the AI ever emits a media token before Track B exists.
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Text('[Image: ${b.key}]', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
```

Replace with:
```dart
    } else if (b is MediaBlock) {
      final path = mediaMap[b.key]?.url;
      if (path == null) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text('Missing media: ${b.key}', style: const TextStyle(color: Colors.red)),
        );
      }
      final isNetwork = path.startsWith('http://') || path.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: isNetwork
              ? Image.network(path, fit: BoxFit.contain)
              : Image.file(File(path), fit: BoxFit.contain),
        ),
      );
    }
```

### B5.3 — Replace the inline media placeholder too

Find (inside `_renderInline`):
```dart
        if (mediaMatch != null) {
          final key = mediaMatch.group(1)!.trim();
          // Track A placeholder — Track B replaces this with real image lookup.
          inlineParts.add(TextSpan(text: '[Image: $key]', style: defaultStyle?.copyWith(color: Colors.grey.shade600)));
        } else {
```

Replace with:
```dart
        if (mediaMatch != null) {
          final key = mediaMatch.group(1)!.trim();
          final path = mediaMap[key]?.url;
          if (path == null) {
            inlineParts.add(TextSpan(text: '[missing: $key]', style: const TextStyle(color: Colors.red)));
          } else {
            final isNetwork = path.startsWith('http://') || path.startsWith('https://');
            inlineParts.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: isNetwork ? Image.network(path, height: 24) : Image.file(File(path), height: 24),
              ),
            ));
          }
        } else {
```

### B5.4 — `flutter analyze lib/src/widgets/ai_answer_renderer.dart` → expect zero warnings

### B5.5 — Wire the chat sheet to build the available-media list

In `_AiChatSheetState`, add a new field:
```dart
  Map<String, String> _availableMedia = {}; // token -> description
```

Find `_loadCourseContext`:
```dart
  Future<void> _loadCourseContext(AiCourse course) async {
    try {
      final api = MatrixScope.of(context).api;
      final modules = await api.listModulesByCourseId(course.id);
      final buffer = StringBuffer();
      for (final m in modules.take(3)) {
        final text = await api.getModuleText(m.id);
        buffer.write('${m.title}\n${text.content}\n\n');
        if (buffer.length > 20000) break;
      }
      if (!mounted) return;
      setState(() {
        _courseContext =
            buffer.toString().substring(0, buffer.length.clamp(0, 20000));
      });
    } catch (e) {
      debugPrint('[AiChatSheet] Failed to load course context: $e');
    }
  }
```

Replace with:
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

Add the new `_courseMediaMap` field alongside `_availableMedia`:
```dart
  Map<String, ModuleMedia> _courseMediaMap = {};
```

Add the required imports at the top of `ai_chat_overlay.dart`:
```dart
import 'package:matrixf/src/models/models.dart';
import '../components/text_blocks.dart';
```

### B5.6 — Pass `mediaMap` into `AiAnswerRenderer`

Find (from Module A4):
```dart
          AiAnswerRenderer(content: text),
```

This is inside `_AssistantBubble`, which currently only receives `text` — it has no access to `_courseMediaMap`. Update `_AssistantBubble` to also accept a `mediaMap`:

```dart
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, this.mediaMap = const {}});
  final String text;
  final Map<String, ModuleMedia> mediaMap;
```

And update its `build()`:
```dart
          AiAnswerRenderer(content: text, mediaMap: mediaMap),
```

Then find where `_AssistantBubble` is constructed in `_buildBubble`:
```dart
    return _AssistantBubble(text: m.content);
```

Replace with:
```dart
    return _AssistantBubble(text: m.content, mediaMap: _courseMediaMap);
```

### B5.7 — Analyze
```bash
flutter analyze lib/src/widgets/ai_chat_overlay.dart lib/src/widgets/ai_answer_renderer.dart
```
Expect zero warnings.

## ✅ Verification — Module B5

- [ ] Full stop, full re-run
- [ ] Open the AI Tutor for a course whose module content has at least one real `[IMG: key]` token with a description set (from B2/B3 testing)
- [ ] Confirm `_availableMedia` is populated — temporarily `debugPrint(_availableMedia)` right after `_loadCourseContext` to check (remove after confirming)
- [ ] Ask a question unrelated to any image → no image appears (expected, Gemini hasn't been told about media yet — that's B6)
- [ ] `flutter analyze` whole project → zero errors

---
---

# MODULE B6 — System Instruction: Available Media

> **Files to modify**: `lib/src/ai/gemini_chat_api.dart`, `lib/src/widgets/ai_chat_overlay.dart`
> **Depends on**: B5

## Steps

### B6.1 — Add an `availableMedia` parameter to `sendMessage`

Find:
```dart
  Future<String> sendMessage({
    required String courseTitle,
    required String courseContext,
    required List<ChatMessage> history,
    required String question,
  }) async {
```

Replace with:
```dart
  Future<String> sendMessage({
    required String courseTitle,
    required String courseContext,
    required List<ChatMessage> history,
    required String question,
    Map<String, String> availableMedia = const {},
  }) async {
```

### B6.2 — Add the media section to the system instruction

Find the end of the FORMATTING section (right before `--- COURSE CONTENT START ---`):
```dart
        'For a short, simple answer, plain sentences are fine — do not add '
        'headings or tables to a one-line answer.\n\n'
        '--- COURSE CONTENT START ---\n'
```

Replace with:
```dart
        'For a short, simple answer, plain sentences are fine — do not add '
        'headings or tables to a one-line answer.\n\n'
        '${_buildMediaSection(availableMedia)}'
        '--- COURSE CONTENT START ---\n'
```

Add this private helper method to the `GeminiChatApi` class:
```dart
  String _buildMediaSection(Map<String, String> availableMedia) {
    if (availableMedia.isEmpty) return '';
    final lines = availableMedia.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    return 'AVAILABLE IMAGES: You may reference at most ONE of the '
        'following existing course images if — and only if — it is '
        'directly relevant to your answer. To include one, put it on its '
        'own line using EXACTLY this format: [IMG: the_exact_key]\n'
        'Do NOT invent keys that are not in this list. Do NOT include an '
        'image unless it genuinely helps explain your answer.\n'
        '$lines\n\n';
  }
```

### A6.3 — Pass `availableMedia` from the chat sheet

In `ai_chat_overlay.dart`, find all THREE call sites of `_chatApi.sendMessage(...)` (the `CacheMiss` case, and the two forced-regeneration branches added earlier). Each currently looks like:
```dart
          final answer = await _chatApi.sendMessage(
            courseTitle: _selectedCourse!.title,
            courseContext: _courseContext,
            history: _messages.where((m) => !m.isLoading && !m.isError && !m.isConfirm).toList(),
            question: trimmed,
          );
```

Add `availableMedia: _availableMedia,` to each of the three:
```dart
          final answer = await _chatApi.sendMessage(
            courseTitle: _selectedCourse!.title,
            courseContext: _courseContext,
            history: _messages.where((m) => !m.isLoading && !m.isError && !m.isConfirm).toList(),
            question: trimmed,
            availableMedia: _availableMedia,
          );
```

### B6.4 — Analyze
```bash
flutter analyze lib/src/ai/gemini_chat_api.dart lib/src/widgets/ai_chat_overlay.dart
```
Expect zero warnings.

## ✅ Verification — Module B6

Temporary debug button testing `GeminiChatApi` directly with a fake media list:
```dart
final reply = await GeminiChatApi().sendMessage(
  courseTitle: 'Mathematics',
  courseContext: 'Integration is the area under a curve...',
  history: [],
  question: 'Show me a diagram of the area under a curve',
  availableMedia: {'fig1': 'Diagram showing shaded area under a curve between two x-values'},
);
debugPrint('[AI-DEBUG] $reply');
```
- [ ] Reply includes `[IMG: fig1]` on its own line when the question is clearly about that image's content
- [ ] Ask something unrelated to any image with the same `availableMedia` passed → reply does NOT include `[IMG: fig1]` (confirms it's not forcing images in)
- [ ] Remove debug button after testing

---
---

# MODULE B7 — End-to-End Verification

Full stop, full re-run. Use your real Mathematics course, with at least one real course image that:
1. Has a `description` set (via B3's admin UI or SQL)
2. Is referenced via `[IMG: key]` or `[GIF: key]` somewhere in that course's actual module content

## ✅ Final Verification Checklist

- [ ] Open AI Tutor for the course, ask a question directly related to what that image shows
- [ ] AI's answer includes the image reference, and it renders as an ACTUAL IMAGE in the chat (not a text placeholder, not "[missing: key]")
- [ ] Ask a question unrelated to the image → no image appears, answer stays text/table/math as appropriate
- [ ] Ask a question where NO images exist for that course at all (a course/module with no `[IMG:]` tokens) → chat works normally, no crash, no empty "AVAILABLE IMAGES:" section confusing the model
- [ ] `flutter analyze` on the entire project → zero errors
- [ ] Old cached answers (pre-dating this feature) still render fine
- [ ] Full regression check: ask a normal question, confirm cache hit/miss/similar flows from before still work correctly (this feature should not have touched cache logic at all)

---

## 🗺️ Dependency Graph

```
A3 (system instruction)        — no deps
A4 (wire renderer)              — A2, A3
A5 (verify)                     — A4
B1 (DB migration)               — no deps
B2 (MatrixApi ext)               — B1
B3 (admin UI)                    — B2, requires real file content before writing
B4 (token extraction)            — no deps
B5 (wire media + real images)    — A2, A4, B2, B4
B6 (system instruction media)    — B5
B7 (final verification)          — everything above
```