import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';

import "reader_screen.dart";
// ─── Library Screen ───────────────────────────────────────────────────────────

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<Library>? future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = MatrixScope.of(context).api;
    future = api.isSignedIn ? api.getLibrary() : null;
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    if (!scope.api.isSignedIn) {
      return SignInPrompt(
        title: 'Your shelf',
        body: 'Sign in to see purchased courses and unlocked text modules.',
        onTap: () => scope.setTab(4),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('Your shelf', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        FutureBuilder<Library>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LoadingList();
            if (snapshot.hasError) return ErrorBox(snapshot.error.toString());
            final lib = snapshot.data!;
            if (lib.courses.isEmpty && lib.modules.isEmpty) {
              return const EmptyBox('Nothing here yet. Browse the catalog to begin.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lib.courses.isNotEmpty) ...[
                  Text('Courses', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...lib.courses.map((c) =>
                      CourseCard(course: c, onTap: () => openCourse(context, c.slug))),
                ],
                if (lib.modules.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Individual modules', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...lib.modules.map((m) => ModuleTile(
                        module: m,
                        index: m.order + 1,
                        open: true,
                        signedIn: true,
                        onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ReaderScreen(moduleId: m.id),
                        )),
                        onBuy: () {},
                      )),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
