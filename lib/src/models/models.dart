class Session {
  Session({
    required this.accessToken,
    required this.userId,
    this.email,
    this.refreshToken,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return Session(
      accessToken: json['access_token']?.toString() ?? '',
      refreshToken: json['refresh_token']?.toString(),
      userId: user?['id']?.toString() ?? json['user_id']?.toString() ?? '',
      email: user?['email']?.toString() ?? json['email']?.toString(),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final String userId;
  final String? email;

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'email': email,
  };
}

class Course {
  Course({
    required this.id,
    required this.slug,
    required this.title,
    this.subtitle,
    this.description,
    this.coverImageUrl,
    this.category,
    required this.priceInr,
    this.program,
    this.branch,
    this.semester,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Untitled course',
    subtitle: json['subtitle']?.toString(),
    description: json['description']?.toString(),
    coverImageUrl: json['cover_image_url']?.toString(),
    category: json['category']?.toString(),
    priceInr: (json['price_inr'] as num?)?.toInt() ?? 0,
    program: json['program']?.toString(),
    branch: json['branch']?.toString(),
    semester: json['semester']?.toString(),
  );

  final String id;
  final String slug;
  final String title;
  final String? subtitle;
  final String? description;
  final String? coverImageUrl;
  final String? category;
  final int priceInr;
  final String? program;
  final String? branch;
  final String? semester;
}

class CourseDetail {
  CourseDetail({required this.course, required this.modules});
  final Course course;
  final List<TextModule> modules;
}

class TextModule {
  TextModule({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    required this.order,
    required this.priceInr,
    this.pageCount,
    required this.isFreePreview,
    required this.isFreeForMembers,
    required this.moduleType,
  });

  factory TextModule.fromJson(Map<String, dynamic> json) => TextModule(
    id: json['id']?.toString() ?? '',
    courseId: json['course_id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Untitled module',
    description: json['description']?.toString(),
    order: (json['display_order'] as num?)?.toInt() ?? 0,
    priceInr: (json['price_inr'] as num?)?.toInt() ?? 0,
    pageCount: (json['page_count'] as num?)?.toInt(),
    isFreePreview: json['is_free_preview'] == true,
    isFreeForMembers: json['is_free_for_members'] == true,
    moduleType: json['module_type']?.toString() ?? 'text',
  );

  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int order;
  final int priceInr;
  final int? pageCount;
  final bool isFreePreview;
  final bool isFreeForMembers;
  final String moduleType;
}

class ModuleText {
  ModuleText({
    required this.module,
    required this.content,
    required this.questions,
    this.mediaMap = const {},
  });

  final TextModule module;
  final String content;
  final List<ModuleQa> questions;
  final Map<String, ModuleMedia> mediaMap;
}

class ModuleMedia {
  ModuleMedia({required this.url, this.mimeType});
  final String url;
  final String? mimeType;
}

class ModuleQa {
  ModuleQa({
    required this.id,
    required this.question,
    required this.answer,
    this.answerImages = const [],
    this.displayOrder = 0,
    this.embedding,
  });

  factory ModuleQa.fromJson(Map<String, dynamic> json) => ModuleQa(
    id: json['id']?.toString() ?? '',
    question: json['question']?.toString() ?? '',
    answer: json['answer_text']?.toString() ?? '',
    answerImages: (json['answer_images'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    embedding: _parseEmbedding(json['embedding']),
  );

  final String id;
  final String question;
  final String answer;
  final List<String> answerImages;
  final int displayOrder;
  final List<double>? embedding; // null if not yet computed (older rows)
}

/// PostgREST returns pgvector columns as a bracketed string like
/// "[0.1,0.2,...]", not a native JSON array — this handles both that
/// string form and, defensively, a real List in case that ever changes.
List<double>? _parseEmbedding(dynamic raw) {
  if (raw == null) return null;
  if (raw is List) {
    return raw.map((e) => (e as num).toDouble()).toList();
  }
  if (raw is String) {
    final cleaned = raw.replaceAll('[', '').replaceAll(']', '').trim();
    if (cleaned.isEmpty) return null;
    try {
      return cleaned.split(',').map((s) => double.parse(s.trim())).toList();
    } catch (_) {
      return null;
    }
  }
  return null;
}

class ModuleTextVersion {
  ModuleTextVersion({
    required this.id,
    required this.version,
    required this.isLatest,
    required this.createdAt,
  });

  factory ModuleTextVersion.fromJson(Map<String, dynamic> json) =>
      ModuleTextVersion(
        id: json['id']?.toString() ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
        isLatest: json['is_latest'] == true,
        createdAt: json['created_at']?.toString() ?? '',
      );

  final String id;
  final int version;
  final bool isLatest;
  final String createdAt;
}

class Profile {
  Profile({
    required this.id,
    this.matrixId,
    this.email,
    this.fullName,
    required this.isAdmin,
  });

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    required bool isAdmin,
  }) => Profile(
    id: json['id']?.toString() ?? '',
    matrixId: json['matrix_id']?.toString(),
    email: json['email']?.toString(),
    fullName: json['full_name']?.toString(),
    isAdmin: isAdmin,
  );

  final String id;
  final String? matrixId;
  final String? email;
  final String? fullName;
  final bool isAdmin;
}

class Purchase {
  Purchase({
    required this.id,
    this.courseId,
    this.moduleId,
    required this.amountInr,
    required this.status,
    this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: json['id']?.toString() ?? '',
    courseId: json['course_id']?.toString(),
    moduleId: json['module_id']?.toString(),
    amountInr: (json['amount_inr'] as num?)?.toInt() ?? 0,
    status: json['status']?.toString() ?? '',
    createdAt: json['created_at']?.toString(),
  );

  final String id;
  final String? courseId;
  final String? moduleId;
  final int amountInr;
  final String status;
  final String? createdAt;
}

class Library {
  Library({
    required this.courses,
    required this.modules,
    required this.purchases,
  });

  final List<Course> courses;
  final List<TextModule> modules;
  final List<Purchase> purchases;
}

class CourseDraft {
  CourseDraft({
    this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.category,
    required this.priceInr,
    required this.isPublished,
    this.coverImageUrl,
    this.program,
    this.branch,
    this.semester,
  });

  final String? id;
  final String slug;
  final String title;
  final String subtitle;
  final String description;
  final String category;
  final int priceInr;
  final bool isPublished;
  final String? coverImageUrl;
  final String? program;
  final String? branch;
  final String? semester;

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'category': category,
    'price_inr': priceInr,
    'is_published': isPublished,
    if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
    'program': (program ?? '').trim().isEmpty ? null : program!.trim(),
    'branch': (branch ?? '').trim().isEmpty ? null : branch!.trim(),
    'semester': (semester ?? '').trim().isEmpty ? null : semester!.trim(),
  };
}

class ModuleDraft {
  ModuleDraft({
    this.id,
    required this.courseId,
    required this.title,
    required this.description,
    required this.order,
    required this.priceInr,
    required this.isFreePreview,
    required this.isFreeForMembers,
  });

  final String? id;
  final String courseId;
  final String title;
  final String description;
  final int order;
  final int priceInr;
  final bool isFreePreview;
  final bool isFreeForMembers;

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'title': title,
    'description': description,
    'display_order': order,
    'price_inr': priceInr,
    'is_free_preview': isFreePreview,
    'is_free_for_members': isFreeForMembers,
    'module_type': 'text',
  };
}

String formatInr(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 2 == 0 && text.length > 3) {
      buffer.write(',');
    }
  }
  return 'Rs ${buffer.toString()}';
}

// Banner stores redirect target as a course SLUG (not id) so tapping a
// banner can call your existing openCourse(context, slug) helper directly,
// with no extra lookup needed at tap time.

class AppBanner {
  final String id;
  final String imageUrl;
  final bool isActive;
  final int displayOrder;
  final String? redirectCourseSlug; // null => decorative, no tap action
  final DateTime createdAt;

  const AppBanner({
    required this.id,
    required this.imageUrl,
    required this.isActive,
    required this.displayOrder,
    this.redirectCourseSlug,
    required this.createdAt,
  });

  factory AppBanner.fromJson(Map<String, dynamic> json) {
    return AppBanner(
      id: json['id'] as String,
      imageUrl: json['image_url'] as String,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
      redirectCourseSlug: json['redirect_course_slug'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class BannerDraft {
  String? id;
  String imageUrl;
  bool isActive;
  int displayOrder;
  bool redirectEnabled;
  String? redirectCourseSlug;
  String?
  redirectCourseTitle; // UI-only, not persisted — label for the picker button

  BannerDraft({
    this.id,
    this.imageUrl = '',
    this.isActive = true,
    this.displayOrder = 0,
    this.redirectEnabled = false,
    this.redirectCourseSlug,
    this.redirectCourseTitle,
  });

  BannerDraft.fromBanner(AppBanner b)
    : id = b.id,
      imageUrl = b.imageUrl,
      isActive = b.isActive,
      displayOrder = b.displayOrder,
      redirectEnabled = b.redirectCourseSlug != null,
      redirectCourseSlug = b.redirectCourseSlug,
      redirectCourseTitle = null;

  bool get isValid =>
      imageUrl.trim().isNotEmpty &&
      (!redirectEnabled || redirectCourseSlug != null);

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'image_url': imageUrl.trim(),
    'is_active': isActive,
    'display_order': displayOrder,
    'redirect_course_slug': redirectEnabled ? redirectCourseSlug : null,
  };
}
