

import 'ai_models.dart';
import 'gemini_embedding_api.dart';
import 'gemini_chat_api.dart';
import 'embedding_utils.dart';
import '../api.dart';

class AiQuizService {
  AiQuizService({
    required GeminiEmbeddingApi embeddingApi,
    required GeminiChatApi chatApi,
    required MatrixApi matrixApi,
  })  : _embeddingApi = embeddingApi,
        _chatApi = chatApi,
        _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final GeminiChatApi _chatApi;
  final MatrixApi _matrixApi;

  static const double _reuseThreshold = 0.90; // original question similar enough to reuse its quiz
  static const double _correctThreshold = 0.80; // student answer similarity to count as correct

  /// Gets a quiz question tied to [originalQuestion] (the student's actual
  /// question, e.g. "What is integration?") — checking the cache FIRST via
  /// [originalQuestionEmbedding] (the SAME embedding already computed for
  /// the main answer cache lookup in _onSend — pass it in, don't re-embed).
  /// Only calls Gemini if no similar quiz is cached yet for this question,
  /// exactly mirroring how the main answer cache avoids redundant Gemini
  /// calls for repeat/similar questions.
  Future<QuizQuestion?> getQuizQuestion({
    required String courseId,
    required String courseTitle,
    required String courseContext,
    required String originalQuestion,
    required List<double> originalQuestionEmbedding,
    required String answerText,
  }) async {
    // 1. Check cache FIRST — zero Gemini calls on a hit.
    final existing = await _matrixApi.callMatchQuizCache(
      courseId: courseId,
      embedding: originalQuestionEmbedding,
      threshold: _reuseThreshold,
      count: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      final question = row['quiz_question']?.toString();
      final answer = row['correct_answer']?.toString();
      if (question != null && answer != null) {
        return QuizQuestion(question: question, correctAnswer: answer);
      }
    }

    // 2. Cache miss — generate a fresh quiz via Gemini.
    final generated = await _chatApi.generateQuizQuestion(
      courseTitle: courseTitle,
      courseContext: courseContext,
      answerText: answerText,
    );
    if (generated == null) return null;

    // 3. Cache it keyed by the ORIGINAL question's embedding (already have
    //    it — no extra embedding call needed here).
    await _matrixApi.insertQuizCache({
      'course_id': courseId,
      'original_question': originalQuestion,
      'quiz_question': generated.question,
      'correct_answer': generated.correctAnswer,
      'embedding': originalQuestionEmbedding,
    });
    return generated;
  }

  /// Validates [studentAnswer] against [correctAnswer]. If
  /// [correctAnswerEmbedding] is provided (e.g. a cached embedding from
  /// module_qa), it's used directly instead of re-embedding correctAnswer —
  /// this is what Revision Mode uses to avoid redundant embedding calls.
  Future<QuizValidation> validateAnswer({
    required String studentAnswer,
    required String correctAnswer,
    List<double>? correctAnswerEmbedding,
  }) async {
    final studentEmbedding = await _embeddingApi.embed(studentAnswer);
    final correctEmbedding = correctAnswerEmbedding ?? await _embeddingApi.embed(correctAnswer);
    final similarity = cosineSimilarity(studentEmbedding, correctEmbedding);
    return QuizValidation(
      result: similarity >= _correctThreshold ? ValidationResult.correct : ValidationResult.incorrect,
      correctAnswer: correctAnswer,
      similarity: similarity,
    );
  }
}
