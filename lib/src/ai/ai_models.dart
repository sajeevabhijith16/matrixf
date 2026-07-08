enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading; // true = show animated typing indicator
  final bool isError; // true = show error styling + retry button
  final bool isConfirm; // true = show "Did you mean?" bubble with Yes/No

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.isConfirm = false,
  });
}

class AiCourse {
  final String id;
  final String title;
  final String slug;
  const AiCourse({required this.id, required this.title, required this.slug});
}

class CacheEntry {
  final String id;
  final String courseId;
  final String question; // original text stored in cache
  final String answer;
  final double similarity; // cosine similarity score 0.0 – 1.0

  const CacheEntry({
    required this.id,
    required this.courseId,
    required this.question,
    required this.answer,
    required this.similarity,
  });

  factory CacheEntry.fromRow(Map<String, dynamic> row) => CacheEntry(
    id: row['id'] as String,
    courseId: '', // not returned by RPC
    question: row['question'] as String,
    answer: row['answer'] as String,
    similarity: (row['similarity'] as num).toDouble(),
  );
}

sealed class CacheResult {}

class CacheHit extends CacheResult {
  final CacheEntry entry;
  CacheHit(this.entry);
}

class CacheSimilar extends CacheResult {
  final CacheEntry best;
  CacheSimilar(this.best);
}

class CacheMiss extends CacheResult {}

void testSealed(CacheResult r) {
  switch (r) {
    case CacheHit(:final entry):
      print(entry.answer);
    case CacheSimilar(:final best):
      print(best.question);
    case CacheMiss():
      print('miss');
  }
}
