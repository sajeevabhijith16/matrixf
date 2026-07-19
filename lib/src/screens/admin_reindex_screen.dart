import 'package:flutter/material.dart';

import '../ai/course_indexer.dart';
import '../ai/gemini_embedding_api.dart';
import '../app.dart';
import '../models/models.dart';

class AdminReindexScreen extends StatefulWidget {
  const AdminReindexScreen({super.key});

  @override
  State<AdminReindexScreen> createState() => _AdminReindexScreenState();
}

class _AdminReindexScreenState extends State<AdminReindexScreen> {
  List<Course> _courses = [];
  bool _loading = true;
  String? _activeCourseId;
  String _statusText = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      final courses = await MatrixScope.of(context).api.adminListCourses();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Failed to load courses: $e';
        _loading = false;
      });
    }
  }

  Future<void> _reindex(Course course) async {
    setState(() {
      _activeCourseId = course.id;
      _statusText = 'Starting...';
    });
    try {
      final indexer = AiCourseIndexer(
        embeddingApi: GeminiEmbeddingApi(),
        matrixApi: MatrixScope.of(context).api,
      );
      final count = await indexer.reindexCourse(
        course.id,
        onProgress: (done, total, chunks) {
          if (!mounted) return;
          setState(() => _statusText = 'Module $done/$total — $chunks chunks so far');
        },
      );
      if (!mounted) return;
      setState(() => _statusText = 'Done — $count chunks indexed for "${course.title}"');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error: $e');
    } finally {
      if (mounted) setState(() => _activeCourseId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reindex Courses (AI RAG)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_statusText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_statusText),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _courses.length,
                    itemBuilder: (context, index) {
                      final course = _courses[index];
                      final isActive = _activeCourseId == course.id;
                      return ListTile(
                        title: Text(course.title),
                        subtitle: Text(course.id),
                        trailing: isActive
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton(
                                onPressed: _activeCourseId == null ? () => _reindex(course) : null,
                                child: const Text('Reindex'),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
