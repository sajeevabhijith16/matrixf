# Inline Image Descriptions — Implementation Roadmap (Modules I1–I5)

> **What it is**: Extends the `[IMG: key]` / `[GIF: key]` token syntax to optionally support `[IMG: key(description)]` — letting content authors document an image right where they use it. Backward compatible: old bare tokens keep working exactly as before.
> **Priority rule for descriptions**: `course_images.description` (admin-confirmed, via Module B) always wins if set; the inline description is a fallback used only when no admin description exists yet — both for the Pending Images scan pre-fill and for what the AI Tutor sees.

---

## Module Map

```
I1 → Core parsing: text_blocks.dart (MediaBlock + extractMediaTokensWithDescriptions)
I2 → Fix inline rendering key-extraction in module_text_renderer.dart + ai_answer_renderer.dart
I3 → Pending Images scan: carry inline description through, pre-fill upload form
I4 → AI Tutor: merge inline description as fallback in available-media list
I5 → End-to-end verification
```

---
---

# MODULE I1 — Core Parsing (`text_blocks.dart`)

> This module is self-contained and exact — no drift risk, since I have full confidence in this file's current state.

### Step 1 — Update `MediaBlock`

Find:
```dart
class MediaBlock extends Block {
  final String key;
  MediaBlock(this.key);
}
```

Replace with:
```dart
class MediaBlock extends Block {
  final String key;
  final String? description; // inline-authored description, if any
  MediaBlock(this.key, [this.description]);
}
```

### Step 2 — Update the standalone media-token detection in `parseBlocks`

Find:
```dart
    // Standalone media token => block image
    final mediaMatch = RegExp(r'^\s*\[(?:IMG|GIF):\s*([^\]]+)\]\s*$', caseSensitive: false).firstMatch(line);
    if (mediaMatch != null) {
      out.add(MediaBlock(mediaMatch.group(1)!.trim()));
      i++;
      continue;
    }
```

Replace with:
```dart
    // Standalone media token => block image
    // Supports both [IMG: key] and [IMG: key(description)]
    final mediaMatch = RegExp(
      r'^\s*\[(?:IMG|GIF):\s*([^\(\)\]]+?)\s*(?:\(([^)]*)\))?\s*\]\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (mediaMatch != null) {
      final key = mediaMatch.group(1)!.trim();
      final description = mediaMatch.group(2)?.trim();
      out.add(MediaBlock(key, (description != null && description.isNotEmpty) ? description : null));
      i++;
      continue;
    }
```

### Step 3 — Replace `extractMediaKeys` with a richer function (keeps the old function working for existing callers)

Find:
```dart
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

Replace with:
```dart
/// Scans [content] for [IMG: key] / [IMG: key(description)] tokens and
/// returns a map of key -> inline description (null if none was given
/// inline). Keys are deduplicated; the first occurrence's description wins
/// if the same key appears multiple times with different inline text.
Map<String, String?> extractMediaTokensWithDescriptions(String content) {
  final regex = RegExp(
    r'\[(?:IMG|GIF):\s*([^\(\)\]]+?)\s*(?:\(([^)]*)\))?\s*\]',
    caseSensitive: false,
  );
  final result = <String, String?>{};
  for (final match in regex.allMatches(content)) {
    final key = match.group(1)?.trim();
    if (key == null || key.isEmpty) continue;
    if (result.containsKey(key)) continue; // first occurrence wins
    final description = match.group(2)?.trim();
    result[key] = (description != null && description.isNotEmpty) ? description : null;
  }
  return result;
}

/// Backward-compatible: existing callers that only need the key set keep
/// working unchanged.
Set<String> extractMediaKeys(String content) =>
    extractMediaTokensWithDescriptions(content).keys.toSet();
```

### ✅ Verification — I1

```bash
flutter analyze lib/src/components/text_blocks.dart
```
Expect zero warnings.

Temporary debug test:
```dart
final result = extractMediaTokensWithDescriptions(
  'Text [IMG: fig1] more text\n'
  '[IMG: fig2(Diagram showing current flow)]\n'
  'Inline [GIF: anim3(A short looping animation)] here\n'
  '[IMG:  fig1(duplicate, should be ignored)  ]',
);
debugPrint('[AI-DEBUG] $result');
// Expect: {fig1: null, fig2: 'Diagram showing current flow',
//          anim3: 'A short looping animation'}
// Note fig1 stays null — its LATER duplicate occurrence with a description
// does NOT override the first (bare) occurrence, per "first occurrence wins".
```
- [ ] Confirm the map matches exactly, including the "first occurrence wins" behavior for `fig1`
- [ ] Test `parseBlocks()` on a standalone line `[IMG: fig2(A diagram)]` → confirm it produces a `MediaBlock` with `key: 'fig2'` and `description: 'A diagram'`
- [ ] Test a bare `[IMG: fig1]` standalone line still parses with `description: null` (no regression)
- [ ] Remove debug code after confirming

---
---

# MODULE I2 — Fix Inline Rendering (⚠️ needs current file content)

> **Files**: `lib/src/components/module_text_renderer.dart`, `lib/src/widgets/ai_answer_renderer.dart`
> **The bug this fixes**: both files' `_renderInline` methods currently do inline media matching with the OLD regex (`r'^\[(?:IMG|GIF):\s*([^\]]+)\]$'`), which would capture the ENTIRE `key(description)` string as if it were the key. Without this fix, writing `[IMG: fig1(a diagram)]` **inline within a paragraph** (not on its own line) would show as a broken "missing image" — the lookup `mediaMap[key]` would fail because `key` would literally be `"fig1(a diagram)"`, not `"fig1"`.
>
> **⚠️ Before implementing**: paste the current full content of both files. Both have been edited multiple times across this conversation (mojibake fix, intrinsic-dimension Column fix, B5's mediaMap addition), so I want the exact current `_renderInline` method from each rather than risk a mismatch.

### What needs to change (once we have the current files)

In BOTH files, inside `_renderInline`, find the line:
```dart
final mediaMatch = RegExp(r'^\[(?:IMG|GIF):\s*([^\]]+)\]$', caseSensitive: false).firstMatch(matchText);
if (mediaMatch != null) {
  final key = mediaMatch.group(1)!.trim();
```

Replace the regex with the key/description-splitting version, and keep using only `key` (group 1) for the `mediaMap` lookup:
```dart
final mediaMatch = RegExp(
  r'^\[(?:IMG|GIF):\s*([^\(\)\]]+?)\s*(?:\(([^)]*)\))?\s*\]$',
  caseSensitive: false,
).firstMatch(matchText);
if (mediaMatch != null) {
  final key = mediaMatch.group(1)!.trim();
  // group(2) is the inline description, if present — not needed for
  // display here, but available if you want to use it as an image
  // tooltip/semantic label later.
```
Everything after that (the `mediaMap[key]?.url` lookup and rendering) stays unchanged — this fix ONLY corrects what gets extracted as `key`.

> **Note on block-level `MediaBlock` rendering**: this does NOT need the same fix — `MediaBlock.key` is already correctly separated from `.description` by I1's parser change, so any code doing `mediaMap[b.key]` already works correctly. Only the INLINE (mid-paragraph) matching path has this bug.

### ✅ Verification — I2
- [ ] Write a module with an INLINE (not standalone-line) token: `Some text [IMG: realtoken(a test description)] more text` where `realtoken` is a real uploaded image
- [ ] Confirm the image renders correctly inline (not a "missing" placeholder) — this is the specific regression this module prevents
- [ ] Confirm a bare inline `[IMG: realtoken]` (no description) still renders correctly too
- [ ] `flutter analyze` on both files → zero warnings

---
---

# MODULE I3 — Pending Images: Carry Inline Description Through

> **Files**: `lib/src/models/pending_image_token.dart`, `lib/src/api.dart` (`adminScanPendingImageTokens`), `lib/src/screens/upload_img_screen.dart`
> **⚠️ Needs current file content** for `adminScanPendingImageTokens` and `upload_img_screen.dart`'s `_selectPendingToken` — these were built in the Pending Images roadmap; paste current versions to confirm no drift before applying.

### Step 1 — Add the field to `PendingImageToken`

```dart
class PendingImageToken {
  const PendingImageToken({
    required this.token,
    required this.moduleId,
    required this.moduleTitle,
    required this.courseId,
    required this.courseTitle,
    this.inlineDescription,
  });

  final String token;
  final String moduleId;
  final String moduleTitle;
  final String courseId;
  final String courseTitle;
  final String? inlineDescription;
}
```

### Step 2 — Update `adminScanPendingImageTokens` to use the richer extraction

Find the line calling `extractMediaKeys(content)` inside the scan loop, and the `PendingImageToken(...)` construction. Replace the extraction call with `extractMediaTokensWithDescriptions(content)`, iterate its entries instead of a plain key set, and pass the description through:

```dart
      final tokenMap = extractMediaTokensWithDescriptions(content);
      for (final entry in tokenMap.entries) {
        final key = entry.key;
        final lower = key.toLowerCase();
        if (uploadedTokens.contains(lower)) continue;
        if (seen.contains(lower)) continue;
        seen.add(lower);
        pending.add(PendingImageToken(
          token: key,
          moduleId: moduleId,
          moduleTitle: info['title']!,
          courseId: info['course_id']!,
          courseTitle: courseTitleById[info['course_id']] ?? 'Unknown course',
          inlineDescription: entry.value,
        ));
      }
```
(Adapt variable names to match whatever your current loop actually uses — the logic is: same dedup/filter behavior as before, just also carrying `entry.value` — the inline description — into the new field.)

### Step 3 — Pre-fill the description field when selecting a pending token

In `upload_img_screen.dart`'s `_selectPendingToken`, find:
```dart
void _selectPendingToken(PendingImageToken pending) {
  setState(() => _tokenController.text = pending.token);
```

Replace with:
```dart
void _selectPendingToken(PendingImageToken pending) {
  setState(() {
    _tokenController.text = pending.token;
    if (pending.inlineDescription != null && pending.inlineDescription!.isNotEmpty) {
      _descriptionController.text = pending.inlineDescription!;
    }
  });
```
(Only overwrites the description field if an inline one actually exists — otherwise leaves whatever's already there, e.g. from a previous selection, untouched.)

### ✅ Verification — I3
- [ ] Add a module content with `[IMG: newtoken(A helpful description)]` for a token that has NOT been uploaded yet
- [ ] Run the Pending Images scan → confirm the entry appears
- [ ] Tap "Upload" on it → confirm BOTH the token field AND the description field are pre-filled correctly
- [ ] Test a pending token with NO inline description → confirm description field stays empty/unaffected (admin must type it manually, same as before)
- [ ] `flutter analyze` → zero warnings

---
---

# MODULE I4 — AI Tutor: Inline Description as Fallback

> **File**: `lib/src/widgets/ai_chat_overlay.dart`
> **⚠️ Needs current file content** — specifically the current `_loadCourseContext` method. This has been modified across Track B (image descriptions) and possibly Track C (RAG chunking, if you've implemented it) — I need to see its exact current form before writing the diff, since the two versions look meaningfully different.

### What needs to change (once we have the current file)

Wherever `_loadCourseContext` currently does:
```dart
final referencedKeys = extractMediaKeys(someContentString);
final descriptions = referencedKeys.isEmpty
    ? <String, String>{}
    : await api.getImageDescriptions(referencedKeys.toList());
```

Replace with logic that also pulls in inline descriptions as a fallback:
```dart
final tokenMap = extractMediaTokensWithDescriptions(someContentString);
final referencedKeys = tokenMap.keys.toList();
final dbDescriptions = referencedKeys.isEmpty
    ? <String, String>{}
    : await api.getImageDescriptions(referencedKeys);

final mergedDescriptions = <String, String>{};
for (final key in referencedKeys) {
  final dbDesc = dbDescriptions[key];
  final inlineDesc = tokenMap[key];
  if (dbDesc != null && dbDesc.trim().isNotEmpty) {
    mergedDescriptions[key] = dbDesc; // admin-confirmed wins
  } else if (inlineDesc != null && inlineDesc.trim().isNotEmpty) {
    mergedDescriptions[key] = inlineDesc; // fallback to inline
  }
}
_availableMedia = mergedDescriptions; // (or however this gets set in your version)
```

### ✅ Verification — I4
- [ ] For an image token with ONLY an inline description (no course_images.description set, not even uploaded yet) → confirm it still appears in the AI's "available images" and Gemini can reference it in an answer if relevant
- [ ] For a token with BOTH an inline description AND an admin-set course_images.description that differ → confirm the admin-set one is what's actually used (priority check)
- [ ] `flutter analyze` → zero warnings

---
---

# MODULE I5 — End-to-End Verification

- [ ] Write fresh module content using the new `[IMG: key(description)]` syntax, both inline and standalone
- [ ] Confirm rendering is correct in BOTH ReaderScreen (`MatrixTextRenderer`) and AI Tutor answers (`AiAnswerRenderer`)
- [ ] Confirm Pending Images scan picks up the inline description and pre-fills it correctly on upload
- [ ] Confirm the AI Tutor can reference and explain an image using only its inline description, before any admin action in the upload screen
- [ ] Confirm ALL existing content using the old bare `[IMG: key]` format still renders and behaves identically — zero regressions
- [ ] `flutter analyze` on the entire project → zero errors