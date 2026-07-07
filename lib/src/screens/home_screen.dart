import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';

// ─── Home Screen ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Course>> future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = MatrixScope.of(context).api.listCourses();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          future = scope.api.listCourses();
        });
        await future;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
        children: [
          const BrandHeader(),
          const SizedBox(height: 34),
          Text(
            'Read deeper.\nLearn slower.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.02,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            'Matrix is a focused mobile shelf for premium text modules. Browse courses, unlock only what you need, and read inside a quiet text-first reader.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.black.withValues(alpha: .62),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => scope.setTab(1),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Browse catalog'),
          ),
          const SizedBox(height: 34),
          SectionTitle(
            title: 'Currently reading',
            action: TextButton(
              onPressed: () => scope.setTab(1),
              child: const Text('All courses'),
            ),
          ),
          FutureBuilder<List<Course>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingList();
              }
              if (snapshot.hasError) return ErrorBox(snapshot.error.toString());
              final courses = (snapshot.data ?? []).take(6).toList();
              if (courses.isEmpty) return const EmptyBox('No courses published yet.');
              return Column(
                children: courses
                    .map((c) => CourseCard(course: c, onTap: () => openCourse(context, c.slug)))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          const TrustTile(
            icon: Icons.text_snippet_outlined,
            title: 'Text-first modules',
            body: 'Structured lessons and Q&A in a quiet reader.',
          ),
          const TrustTile(
            icon: Icons.lock_outline,
            title: 'Member access',
            body: 'Open free previews, member-free lessons, and modules you own.',
          ),
        ],
      ),
    );
  }
}
