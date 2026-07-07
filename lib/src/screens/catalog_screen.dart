import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';

// ─── Catalog Screen ───────────────────────────────────────────────────────────

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<Course>> future;
  String query = '';
  String? category;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = MatrixScope.of(context).api.listCourses();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('Catalog', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search courses',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Course>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LoadingList();
            if (snapshot.hasError) return ErrorBox(snapshot.error.toString());
            final all = snapshot.data ?? [];
            final categories = all
                .map((c) => c.category)
                .whereType<String>()
                .where((v) => v.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            final filtered = all.where((c) {
              final haystack = '${c.title} ${c.subtitle ?? ''}'.toLowerCase();
              return (category == null || c.category == category) &&
                  haystack.contains(query.toLowerCase());
            }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categories.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: category == null,
                        onSelected: (_) => setState(() => category = null),
                      ),
                      const SizedBox(width: 8),
                      ...categories.map((item) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(item),
                              selected: category == item,
                              onSelected: (_) => setState(() => category = item),
                            ),
                          )),
                    ]),
                  ),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  const EmptyBox('No courses match your filters.')
                else
                  ...filtered.map((c) => CourseCard(
                        course: c,
                        onTap: () => openCourse(context, c.slug),
                      )),
              ],
            );
          },
        ),
      ],
    );
  }
}
