import 'package:flutter/material.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';

// ─── Branch List ───────────────────────────────────────────────────────────

class BranchListScreen extends StatelessWidget {
  const BranchListScreen({
    super.key,
    required this.program,
    required this.allCourses,
  });
  final String program;
  final List<Course> allCourses;

  @override
  Widget build(BuildContext context) {
    final branches =
        allCourses
            .where((c) => (c.program ?? '') == program)
            .map((c) => (c.branch ?? '').trim())
            .where((b) => b.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(title: Text(program)),
      body: branches.isEmpty
          ? const EmptyBox('No branches added yet.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: branches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final branch = branches[i];
                return Card(
                  child: ListTile(
                    title: Text(branch),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SemesterListScreen(
                          program: program,
                          branch: branch,
                          allCourses: allCourses,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Semester List ─────────────────────────────────────────────────────────

class SemesterListScreen extends StatelessWidget {
  const SemesterListScreen({
    super.key,
    required this.program,
    required this.branch,
    required this.allCourses,
  });
  final String program;
  final String branch;
  final List<Course> allCourses;

  @override
  Widget build(BuildContext context) {
    final semesters =
        allCourses
            .where(
              (c) => (c.program ?? '') == program && (c.branch ?? '') == branch,
            )
            .map((c) => (c.semester ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(title: Text(branch)),
      body: semesters.isEmpty
          ? const EmptyBox('No semesters added yet.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: semesters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final semester = semesters[i];
                return Card(
                  child: ListTile(
                    title: Text(semester),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SubjectListScreen(
                          program: program,
                          branch: branch,
                          semester: semester,
                          allCourses: allCourses,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Subject (Course) List ─────────────────────────────────────────────────

class SubjectListScreen extends StatelessWidget {
  const SubjectListScreen({
    super.key,
    required this.program,
    required this.branch,
    required this.semester,
    required this.allCourses,
  });
  final String program;
  final String branch;
  final String semester;
  final List<Course> allCourses;

  @override
  Widget build(BuildContext context) {
    final subjects = allCourses
        .where(
          (c) =>
              (c.program ?? '') == program &&
              (c.branch ?? '') == branch &&
              (c.semester ?? '') == semester,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(semester)),
      body: subjects.isEmpty
          ? const EmptyBox('No subjects added yet.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: subjects
                  .map(
                    (c) => CourseCard(
                      course: c,
                      onTap: () => openCourse(context, c.slug),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
