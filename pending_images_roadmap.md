# Pending Images Feature — Implementation Plan (Modules D1–D2)

> **What it is**: Adds a "Pending Images" section to `upload_img_screen.dart`. Admin taps "Scan", the app checks every course's module content for `[IMG: key]` / `[GIF: key]` tokens that don't yet have an uploaded image in `course_images`, and lists them — showing which course/module each one is used in. Tapping a pending token pre-fills the existing upload form's token field so the admin can immediately select an image and upload.
> **Depends on**: `extractMediaKeys()` (Module B4, already built), `adminUploadImageToken` with description support (Module B2, already built).
> **Pattern**: Same as before — implement → verify → move on.

---

## Module Map

```
D1 → MatrixApi: adminScanPendingImageTokens() + PendingImageToken model
D2 → UI: Pending Images section in upload_img_screen.dart
D3 → End-to-end verification
```

---
---

# MODULE D1 — MatrixApi Extension + Data Model

### Step 1 — Create the data model

Create `lib/src/models/pending_image_token.dart`:
```dart
/// A media token referenced in some course's module content
/// ([IMG: token] / [GIF: token]) that has no uploaded image yet.
class PendingImageToken {
  const PendingImageToken({
    required this.token,
    required this.moduleId,
    required this.moduleTitle,
    required this.courseId,
    required this.courseTitle,
  });

  final String token;
  final String moduleId;
  final String moduleTitle;
  final String courseId;
  final String courseTitle;
}
```

### Step 2 — Add the scanning method to `MatrixApi`

Add this to `lib/src/api.dart`, in the "Admin: image tokens" section:

```dart
  /// Scans every course's latest module content for [IMG:]/[GIF:] tokens
  /// and returns the ones that have no uploaded image in course_images yet.
  /// Deduplicated globally by token (first occurrence wins for display).
  Future<List<PendingImageToken>> adminScanPendingImageTokens() async {
    _requireSession();

    // 1. All modules — for id -> (title, course_id) lookup.
    final moduleRows = await _restGet('modules', {
      'select': 'id,title,course_id',
    });
    final moduleInfo = <String, Map<String, String>>{};
    for (final row in moduleRows) {
      final id = row['id']?.toString();
      if (id == null) continue;
      moduleInfo[id] = {
        'title': row['title']?.toString() ?? 'Untitled module',
        'course_id': row['course_id']?.toString() ?? '',
      };
    }

    // 2. All courses (including unpublished/drafts) — for title lookup.
    final courses = await adminListCourses();
    final courseTitleById = {for (final c in courses) c.id: c.title};

    // 3. Latest content for every module, in one query.
    final versionRows = await _restGet('module_text_versions', {
      'select': 'module_id,content',
      'is_latest': 'eq.true',
    });

    // 4. Tokens that already have an uploaded image.
    final imageRows = await _restGet('course_images', {'select': 'token'});
    final uploadedTokens = imageRows
        .map((r) => r['token']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();

    // 5. Scan content, collect tokens not yet uploaded.
    final seen = <String>{};
    final pending = <PendingImageToken>[];
    for (final row in versionRows) {
      final moduleId = row['module_id']?.toString();
      final content = row['content']?.toString();
      if (moduleId == null || content == null) continue;
      final info = moduleInfo[moduleId];
      if (info == null) continue;

      final keys = extractMediaKeys(content);
      for (final key in keys) {
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
        ));
      }
    }

    return pending;
  }
```

### Step 3 — Add the required imports to `api.dart`

At the top of `api.dart`, add:
```dart
import 'components/text_blocks.dart';
import 'models/pending_image_token.dart';
```
Adjust the relative path for `text_blocks.dart` to match where `api.dart` actually sits relative to `lib/src/components/` — based on your project layout (`lib/src/api.dart` and `lib/src/components/text_blocks.dart`), `components/text_blocks.dart` is correct as a relative import from `api.dart`.

> **Why this is safe to import here**: `text_blocks.dart` has no Flutter dependency (pure Dart, just `RegExp`/`String` logic) — importing it into `api.dart` doesn't pull any UI code into your data layer.

### Step 4 — Analyze
```bash
flutter analyze lib/src/api.dart lib/src/models/pending_image_token.dart
```
Expect zero warnings.

## ✅ Verification — D1

Temporary debug button:
```dart
ElevatedButton(
  onPressed: () async {
    try {
      final pending = await scope.api.adminScanPendingImageTokens();
      for (final p in pending) {
        debugPrint('[AI-DEBUG] ${p.token} — ${p.courseTitle} → ${p.moduleTitle}');
      }
      debugPrint('[AI-DEBUG] Total pending: ${pending.length}');
    } catch (e) {
      debugPrint('[AI-DEBUG] Error: $e');
    }
  },
  child: const Text('[DEBUG] Test D1 scan'),
),
```
- [ ] If you have a course with an `[IMG: key]` token in its content that has NOT been uploaded to `course_images` yet, it appears in the results with the correct course/module names
- [ ] A token that DOES already have an uploaded image does NOT appear (confirms the filter works)
- [ ] Remove debug button after confirming

---
---

# MODULE D2 — UI: Pending Images Section

> **File to modify**: `lib/src/screens/upload_img_screen.dart`

### Step 1 — Add imports

At the top of the file, add:
```dart
import '../models/pending_image_token.dart';
```

### Step 2 — Add new state fields

Find:
```dart
  List<InlineImage> _images = [];
```

Replace with:
```dart
  List<InlineImage> _images = [];

  List<PendingImageToken> _pendingTokens = [];
  bool _scanningPending = false;
  bool _hasScannedPending = false;
  final ScrollController _formScrollController = ScrollController();
```

### Step 3 — Dispose the new controller

Find:
```dart
  @override
  void dispose() {
    _tokenController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }
```

Replace with:
```dart
  @override
  void dispose() {
    _tokenController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _formScrollController.dispose();
    super.dispose();
  }
```

### Step 4 — Add the scan and select methods

Add these anywhere among the other methods (e.g. right after `_loadImages`):
```dart
  Future<void> _scanPendingImages() async {
    setState(() => _scanningPending = true);
    try {
      final pending = await _api.adminScanPendingImageTokens();
      if (!mounted) return;
      setState(() {
        _pendingTokens = pending;
        _hasScannedPending = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _scanningPending = false);
    }
  }

  void _selectPendingToken(PendingImageToken pending) {
    setState(() => _tokenController.text = pending.token);
    _formScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Token "${pending.token}" filled in — select an image and upload.')),
    );
  }
```

### Step 5 — Auto-remove from pending list after a successful upload

Find (inside `_upload()`):
```dart
      setState(() {
        _selectedImage = null;
        _tokenController.clear();
        _descriptionController.clear();
      });
      await _loadImages();
```

Replace with:
```dart
      setState(() {
        _selectedImage = null;
        _pendingTokens.removeWhere((p) => p.token.toLowerCase() == token.toLowerCase());
        _tokenController.clear();
        _descriptionController.clear();
      });
      await _loadImages();
```

### Step 6 — Wire the `ScrollController` into the `SingleChildScrollView`

Find:
```dart
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
```

Replace with:
```dart
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        controller: _formScrollController,
        padding: const EdgeInsets.all(20),
```

### Step 7 — Add the Pending Images section to the UI

Find the upload button row and the section right after it:
```dart
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text("Select Image"),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload),
                    label: Text(_uploading ? "Uploading..." : "Upload"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Text(
              "Search Token",
              style: Theme.of(context).textTheme.titleMedium,
            ),
```

Replace with (inserting the new section between the upload row and "Search Token"):
```dart
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text("Select Image"),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload),
                    label: Text(_uploading ? "Uploading..." : "Upload"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Text(
              "Pending Images",
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 8),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _hasScannedPending
                        ? '${_pendingTokens.length} token(s) referenced in course content without an uploaded image.'
                        : 'Scan your courses for [IMG:]/[GIF:] tokens that have no image uploaded yet.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _scanningPending ? null : _scanPendingImages,
                  icon: _scanningPending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: Text(_scanningPending ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_hasScannedPending && _pendingTokens.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('No pending tokens — all referenced images are uploaded.'),
              ),

            if (_pendingTokens.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingTokens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final pending = _pendingTokens[index];
                  return Card(
                    color: Colors.amber.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.image_not_supported_outlined, color: Colors.orange),
                      title: Text(
                        pending.token,
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${pending.courseTitle} → ${pending.moduleTitle}'),
                      trailing: TextButton(
                        onPressed: () => _selectPendingToken(pending),
                        child: const Text('Upload'),
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 32),

            Text(
              "Search Token",
              style: Theme.of(context).textTheme.titleMedium,
            ),
```

Note: this uses `ListView.separated` with `shrinkWrap: true` + `NeverScrollableScrollPhysics()` inside the outer `SingleChildScrollView` — the same pattern your existing "Registered Tokens" list already uses successfully in this exact file, so it won't hit the intrinsic-dimension bug we just fixed in `MatrixTextRenderer` (that bug was specifically about `DataTable`/`Table`, not `ListView`).

### Step 8 — Analyze
```bash
flutter analyze lib/src/screens/upload_img_screen.dart
```
Expect zero warnings.

---
---

# MODULE D3 — End-to-End Verification

Full stop, full re-run. In the admin Upload Screen:

- [ ] Add an `[IMG: some_new_token]` reference in some module's content (via your module editor) that has NOT been uploaded yet
- [ ] Open the Upload Screen, tap "Scan" → the new token appears in the Pending Images list, showing the correct course and module name
- [ ] Tap "Upload" on that pending item → the token field at the top auto-fills, screen scrolls up to the form
- [ ] Select an image, tap the main "Upload" button → upload succeeds
- [ ] Confirm the item is now REMOVED from the Pending Images list automatically (no rescan needed)
- [ ] Confirm it now appears in "Registered Tokens" below, as normal
- [ ] Tap "Scan" again → confirm it does NOT reappear (proves the scan correctly excludes now-uploaded tokens)
- [ ] Test the empty case: if all tokens are already uploaded, scanning shows the green "No pending tokens" message, not an empty blank area
- [ ] `flutter analyze` whole project → zero errors