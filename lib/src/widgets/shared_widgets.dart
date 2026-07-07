import 'package:flutter/material.dart';
import 'package:matrixf/src/screens/course_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
// ─── Rich Text Renderer ───────────────────────────────────────────────────────

// ─── Course & Module Widgets ──────────────────────────────────────────────────

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, required this.onTap});
  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CourseImage(url: course.coverImageUrl),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((course.category ?? '').isNotEmpty)
                    Text(course.category!.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall),
                  Text(
                    course.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if ((course.subtitle ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        course.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: Colors.black.withValues(alpha: .62)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(formatInr(course.priceInr)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseImage extends StatelessWidget {
  const CourseImage({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.text_snippet_outlined, size: 42),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (_, _, _) =>
            const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class CourseHero extends StatelessWidget {
  const CourseHero({super.key, required this.course});
  final Course course;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CourseImage(url: course.coverImageUrl)),
        const SizedBox(height: 16),
        if ((course.category ?? '').isNotEmpty)
          Text(course.category!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
        Text(course.title, style: Theme.of(context).textTheme.headlineMedium),
        if ((course.subtitle ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(course.subtitle!,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        if ((course.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(course.description!,
                style: const TextStyle(height: 1.5)),
          ),
      ],
    );
  }
}

class ModuleTile extends StatelessWidget {
  const ModuleTile({
    super.key,
    required this.module,
    required this.index,
    required this.open,
    required this.signedIn,
    required this.onOpen,
    required this.onBuy,
  });

  final TextModule module;
  final int index;
  final bool open;
  final bool signedIn;
  final VoidCallback onOpen;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final isFreeForMembers = module.isFreeForMembers;
    final needsSignIn = isFreeForMembers && !signedIn;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Text(index.toString().padLeft(2, '0'))),
        title: Text(module.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((module.description ?? '').isNotEmpty) Text(module.description!),
            Wrap(spacing: 6, children: [
              if (module.isFreePreview) const Chip(label: Text('Free preview')),
              if (module.isFreeForMembers) const Chip(label: Text('Members')),
              if (!open && module.priceInr > 0 && !needsSignIn)
                Chip(label: Text(formatInr(module.priceInr))),
            ]),
          ],
        ),
        trailing: open
            ? const Icon(Icons.play_arrow)
            : needsSignIn
                ? const Icon(Icons.person_outline)
                : module.priceInr > 0
                    ? const Icon(Icons.shopping_bag_outlined)
                    : const Icon(Icons.lock_outline),
        onTap: open
            ? onOpen
            : needsSignIn
                ? () => showSnack(context, 'Sign in to open this module.')
                : module.priceInr > 0
                    ? onBuy
                    : () => showSnack(context, 'This module is locked.'),
      ),
    );
  }
}

// ─── Shared Utility Widgets ───────────────────────────────────────────────────

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Matrix',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 5),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        ?action,
      ],
    );
  }
}

class TrustTile extends StatelessWidget {
  const TrustTile({super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Card(
          child: SizedBox(
            height: 128,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyBox extends StatelessWidget {
  const EmptyBox(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message,
            style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    );
  }
}

class CenteredError extends StatelessWidget {
  const CenteredError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.title, required this.body, required this.onTap});
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      children: [
        const BrandHeader(),
        const SizedBox(height: 32),
        Icon(Icons.lock_outline,
            size: 42, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(body),
        const SizedBox(height: 18),
        FilledButton(onPressed: onTap, child: const Text('Sign in')),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: Colors.black.withValues(alpha: .58)))),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

// ─── Navigation helpers ───────────────────────────────────────────────────────

void openCourse(BuildContext context, String slug) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => CourseDetailScreen(slug: slug)));
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ─── Q&A Sheet ───────────────────────────────────────────────────────────────

void showQaSheet(BuildContext context, List<ModuleQa> questions) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      maxChildSize: .92,
      minChildSize: .35,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Questions & Answers',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (questions.isEmpty)
            const EmptyBox('No questions yet.')
          else
            ...questions.map((qa) => Card(
                  child: ExpansionTile(
                    title: Text(qa.question),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if (qa.answer.isNotEmpty) Text(qa.answer),
                      // ── Answer images grid ──────────────────────────────
                      if (qa.answerImages.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          children: qa.answerImages
                              .map((url) => ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => const Center(
                                          child:
                                              CircularProgressIndicator()),
                                      errorWidget: (_, _, _) =>
                                          const Icon(
                                              Icons.broken_image_outlined),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                )),
        ],
      ),
    ),
  );
}

// ─── Admin bottom sheets (course + module metadata editors) ──────────────────

void showCourseEditor(
  BuildContext context,
  CourseDraft? existing, {
  required VoidCallback onSaved,
}) {
  final api = MatrixScope.of(context).api;
  final title = TextEditingController(text: existing?.title ?? '');
  final slug = TextEditingController(text: existing?.slug ?? '');
  final subtitle = TextEditingController(text: existing?.subtitle ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final category = TextEditingController(text: existing?.category ?? '');
  final price = TextEditingController(
      text: (existing?.priceInr ?? 0).toString());
  final coverUrl = TextEditingController(text: existing?.coverImageUrl ?? '');
  var published = existing?.isPublished ?? false;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing?.id == null ? 'New course' : 'Edit course',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(controller: slug, decoration: const InputDecoration(labelText: 'Slug')),
              const SizedBox(height: 8),
              TextField(controller: subtitle, decoration: const InputDecoration(labelText: 'Subtitle')),
              const SizedBox(height: 8),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price INR'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: coverUrl,
                decoration: const InputDecoration(labelText: 'Cover image URL'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: description,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Description', alignLabelWithHint: true),
              ),
              SwitchListTile(
                value: published,
                onChanged: (v) => setSheetState(() => published = v),
                title: const Text('Published'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await api.adminSaveCourse(CourseDraft(
                      id: existing?.id,
                      slug: slug.text.trim(),
                      title: title.text.trim(),
                      subtitle: subtitle.text.trim(),
                      description: description.text.trim(),
                      category: category.text.trim(),
                      priceInr: int.tryParse(price.text) ?? 0,
                      isPublished: published,
                      coverImageUrl: coverUrl.text.trim().isEmpty
                          ? null
                          : coverUrl.text.trim(),
                    ));
                    if (ctx.mounted) Navigator.pop(ctx);
                    onSaved();
                  } catch (e) {
                    if (ctx.mounted) showSnack(ctx, e.toString());
                  }
                },
                child: const Text('Save course'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void showModuleEditor(
  BuildContext context,
  String courseId,
  TextModule? existing, {
  required VoidCallback onSaved,
}) {
  final api = MatrixScope.of(context).api;
  final title = TextEditingController(text: existing?.title ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final order = TextEditingController(
      text: (existing?.order ?? 0).toString());
  final price = TextEditingController(
      text: (existing?.priceInr ?? 0).toString());
  var freePreview = existing?.isFreePreview ?? false;
  var freeMembers = existing?.isFreeForMembers ?? true;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'New text module' : 'Edit module',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Order'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price INR'),
              ),
              SwitchListTile(
                value: freePreview,
                onChanged: (v) => setSheetState(() => freePreview = v),
                title: const Text('Free preview'),
              ),
              SwitchListTile(
                value: freeMembers,
                onChanged: (v) => setSheetState(() => freeMembers = v),
                title: const Text('Free for signed-in members'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await api.adminSaveModule(ModuleDraft(
                      id: existing?.id,
                      courseId: courseId,
                      title: title.text.trim(),
                      description: description.text.trim(),
                      order: int.tryParse(order.text) ?? 0,
                      priceInr: int.tryParse(price.text) ?? 0,
                      isFreePreview: freePreview,
                      isFreeForMembers: freeMembers,
                    ));
                    if (ctx.mounted) Navigator.pop(ctx);
                    onSaved();
                  } catch (e) {
                    if (ctx.mounted) showSnack(ctx, e.toString());
                  }
                },
                child: const Text('Save module'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}