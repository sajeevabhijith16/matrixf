enum ChatRole { user, assistant }

enum ValidationResult { correct, incorrect }

class QuizValidation {
  const QuizValidation({
    required this.result,
    required this.correctAnswer,
    required this.similarity,
  });
  final ValidationResult result;
  final String correctAnswer;
  final double similarity;
}

class QuizQuestion {
  const QuizQuestion({required this.question, required this.correctAnswer});
  final String question;
  final String correctAnswer;
}

class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final bool isConfirm;
  final bool isQuiz;              // true = show quiz question + answer input
  final String? quizCorrectAnswer; // hidden from UI until validated
  final QuizValidation? quizResult; // null until student submits an answer

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.isConfirm = false,
    this.isQuiz = false,
    this.quizCorrectAnswer,
    this.quizResult,
  });

  ChatMessage copyWith({QuizValidation? quizResult}) => ChatMessage(
        role: role,
        content: content,
        timestamp: timestamp,
        isLoading: isLoading,
        isError: isError,
        isConfirm: isConfirm,
        isQuiz: isQuiz,
        quizCorrectAnswer: quizCorrectAnswer,
        quizResult: quizResult ?? this.quizResult,
      );
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

