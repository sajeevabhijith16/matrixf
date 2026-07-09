import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';

import "reader_screen.dart";
// ─── Course Detail Screen ─────────────────────────────────────────────────────

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.slug});
  final String slug;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late Future<CourseDetail?> future;
  Library? library;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = MatrixScope.of(context);
    future = scope.api.getCourse(widget.slug);
    if (scope.api.isSignedIn) {
      scope.api
          .getLibrary()
          .then((v) {
            if (mounted) setState(() => library = v);
          })
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Course')),
      body: FutureBuilder<CourseDetail?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredError(snapshot.error.toString());
          }
          final detail = snapshot.data;
          if (detail == null) return const CenteredError('Course not found.');

          final ownsCourse =
              library?.courses.any((c) => c.id == detail.course.id) ?? false;
          final ownedModules =
              library?.modules.map((m) => m.id).toSet() ?? <String>{};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CourseHero(course: detail.course),
              const SizedBox(height: 20),
              // ─── Buy / In Library button ──────────────────────────────────
              if (ownsCourse)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    scope.setTab(2);
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('In your library'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => showSnack(
                    context,
                    'Checkout needs the web app. This build keeps the UI ready.',
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(
                    'Buy full course  ${formatInr(detail.course.priceInr)}',
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Text modules',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (detail.modules.isEmpty)
                const EmptyBox('No text modules added yet.')
              else
                ...detail.modules.asMap().entries.map((entry) {
                  final module = entry.value;
                  final isOwned =
                      ownsCourse ||
                      ownedModules.contains(module.id) ||
                      module.isFreePreview ||
                      (module.isFreeForMembers && scope.api.isSignedIn);
                  return ModuleTile(
                    module: module,
                    index: entry.key + 1,
                    open: isOwned,
                    signedIn: scope.api.isSignedIn,
                    onOpen: () {
                      if (!scope.api.isSignedIn && !module.isFreePreview) {
                        showSnack(context, 'Sign in to open this module.');
                        scope.setTab(4);
                        Navigator.pop(context);
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReaderScreen(moduleId: module.id),
                        ),
                      );
                    },
                    onBuy: () => showSnack(
                      context,
                      'Checkout needs the web app server. Module: ${module.title}',
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
