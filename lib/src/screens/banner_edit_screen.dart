import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../app.dart';

class BannerEditScreen extends StatefulWidget {
  const BannerEditScreen({super.key, this.existing});

  final AppBanner? existing;

  @override
  State<BannerEditScreen> createState() => _BannerEditScreenState();
}

class _BannerEditScreenState extends State<BannerEditScreen> {
  late BannerDraft draft;
  late TextEditingController urlController;
  late TextEditingController orderController;
  String previewUrl = '';
  bool saving = false;
  bool _resolvedTitle = false;

  @override
  void initState() {
    super.initState();
    draft = widget.existing != null
        ? BannerDraft.fromBanner(widget.existing!)
        : BannerDraft();
    urlController = TextEditingController(text: draft.imageUrl);
    orderController = TextEditingController(
      text: draft.displayOrder.toString(),
    );
    previewUrl = draft.imageUrl;

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_resolvedTitle && draft.redirectCourseSlug != null) {
      _resolvedTitle = true;
      _resolveCourseTitle(draft.redirectCourseSlug!);
    }
  }

  Future<void> _resolveCourseTitle(String slug) async {
    try {
      final courses = await MatrixScope.of(context).api.listCourses();
      final match = courses.where((c) => c.slug == slug);
      if (match.isNotEmpty && mounted) {
        setState(() => draft.redirectCourseTitle = match.first.title);
      }
    } catch (_) {
      // Non-fatal — the picker button just shows the slug instead of title.
    }
  }

  @override
  void dispose() {
    urlController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _pickCourse() async {
    final api = MatrixScope.of(context).api;
    List<Course> courses;
    try {
      courses = await api.adminListCourses();
    } catch (_) {
      courses = await api.listCourses();
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CoursePickerSheet(courses: courses),
    );
    if (selected != null) {
      setState(() {
        draft.redirectCourseSlug = selected.slug;
        draft.redirectCourseTitle = selected.title;
      });
    }
  }

  Future<void> _save() async {
    if (!draft.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add an image URL, and pick a course if redirect is on.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final api = MatrixScope.of(context).api;
      await api.adminSaveBanner(draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save banner: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete banner?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => saving = true);
    try {
      final api = MatrixScope.of(context).api;
      await api.adminDeleteBanner(draft.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete banner: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit banner' : 'New banner'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: saving ? null : _delete,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                draft.imageUrl = v;
                setState(() => previewUrl = v.trim());
              },
            ),
            const SizedBox(height: 16),
            _PreviewBox(url: previewUrl),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Active'),
              subtitle: const Text('Show this banner on the home screen'),
              value: draft.isActive,
              onChanged: (v) => setState(() => draft.isActive = v),
            ),
            const Divider(),
            TextField(
              controller: orderController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Display order',
                helperText: 'Lower numbers show first',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => draft.displayOrder = int.tryParse(v) ?? 0,
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Redirect to course'),
              subtitle: const Text('Tapping the banner opens a course'),
              value: draft.redirectEnabled,
              onChanged: (v) => setState(() {
                draft.redirectEnabled = v;
                if (!v) {
                  draft.redirectCourseSlug = null;
                  draft.redirectCourseTitle = null;
                }
              }),
            ),
            if (draft.redirectEnabled) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickCourse,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(
                  draft.redirectCourseTitle ??
                      draft.redirectCourseSlug ??
                      'Choose a course',
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save banner'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Container(
          color: Colors.black.withValues(alpha: .04),
          child: url.isEmpty
              ? const Center(child: Text('Paste an image URL to preview'))
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) =>
                      const Center(child: Text('Could not load this image')),
                ),
        ),
      ),
    );
  }
}

class _CoursePickerSheet extends StatelessWidget {
  const _CoursePickerSheet({required this.courses});
  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: courses.length,
        itemBuilder: (context, index) {
          final course = courses[index];
          return ListTile(
            title: Text(course.title),
            subtitle: Text(course.slug),
            onTap: () => Navigator.of(context).pop(course),
          );
        },
      ),
    );
  }
}
