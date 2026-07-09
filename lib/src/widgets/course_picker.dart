import 'package:flutter/material.dart';

import '../ai/ai_models.dart';

/// A standalone autocomplete input for picking a course.
///
/// Shows matching courses as the user types (like a Google-Forms-style
/// dropdown picker). Pure UI — no network calls. The caller is responsible
/// for pre-loading [courses] (e.g. from `MatrixScope`) before building this
/// widget.
class CoursePicker extends StatefulWidget {
  const CoursePicker({
    super.key,
    required this.courses,
    required this.onSelected,
  });

  /// Pre-loaded list of courses to search against.
  final List<AiCourse> courses;

  /// Called when the user taps a suggestion.
  final void Function(AiCourse course) onSelected;

  @override
  State<CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends State<CoursePicker> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  List<AiCourse> get _filtered {
    final query = _query.trim();
    if (query.isEmpty) return const [];
    final lowerQuery = query.toLowerCase();
    return widget.courses
        .where((c) => c.title.toLowerCase().contains(lowerQuery))
        .take(6)
        .toList();
  }

  /// Builds a [TextSpan] with the first matching substring of [query]
  /// inside [title] rendered in bold.
  TextSpan _highlightMatch(String title, String query, TextStyle baseStyle) {
    final idx = title.toLowerCase().indexOf(query.toLowerCase());
    if (idx == -1) {
      return TextSpan(text: title, style: baseStyle);
    }
    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: title.substring(0, idx)),
        TextSpan(
          text: title.substring(idx, idx + query.length),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: title.substring(idx + query.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    final showEmptyState = _query.trim().isNotEmpty && filtered.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Which course would you like help with?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          onChanged: _onQueryChanged,
          decoration: const InputDecoration(
            hintText: 'Search courses...',
            prefixIcon: Icon(Icons.school_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: filtered.isEmpty && !showEmptyState
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: showEmptyState
                      ? _EmptyState(theme: theme)
                      : _DropdownCard(
                          courses: filtered,
                          query: _query.trim(),
                          highlightBuilder: _highlightMatch,
                          onSelected: widget.onSelected,
                        ),
                ),
        ),
      ],
    );
  }
}

class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.courses,
    required this.query,
    required this.highlightBuilder,
    required this.onSelected,
  });

  final List<AiCourse> courses;
  final String query;
  final TextSpan Function(String title, String query, TextStyle baseStyle)
  highlightBuilder;
  final void Function(AiCourse course) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: courses.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final course = courses[index];
            return ListTile(
              title: Text.rich(
                highlightBuilder(course.title, query, baseStyle),
              ),
              onTap: () => onSelected(course),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No courses match',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
      ),
    );
  }
}
