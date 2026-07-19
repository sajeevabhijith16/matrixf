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
