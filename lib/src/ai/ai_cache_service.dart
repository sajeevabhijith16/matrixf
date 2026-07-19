import 'dart:math';

import 'ai_models.dart';
import 'gemini_embedding_api.dart';
import '../api.dart';

class AiCacheService {
  AiCacheService({
    required GeminiEmbeddingApi embeddingApi,
    required MatrixApi matrixApi,
  })  : _embeddingApi = embeddingApi,
        _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final MatrixApi _matrixApi;
  final Random _random = Random();

  static const double _exactThreshold = 0.93;   // same question → return cached
  static const double _similarThreshold = 0.85; // related → ask "Did you mean?"
  // below 0.85 → CacheMiss → call Gemini

  Future<CacheResult> lookup(String courseId, String question) async {
    final embedding = await _embeddingApi.embed(question);

    // Fetch a few candidates (not just the top one) so we can pick among
    // multiple qualifying variants instead of always the single best match.
    final rows = await _matrixApi.callMatchAiCache(
      courseId: courseId,
      embedding: embedding,
      threshold: _similarThreshold,
      count: 5,
    );

    if (rows.isEmpty) return CacheMiss();

    final entries = rows.map((r) => CacheEntry.fromRow(r)).toList();
    final exactMatches =
        entries.where((e) => e.similarity >= _exactThreshold).toList();

    if (exactMatches.isNotEmpty) {
      final chosen = exactMatches[_random.nextInt(exactMatches.length)];
      return CacheHit(chosen);
    }

    // No exact match — offer the closest "similar" candidate for confirmation.
    return CacheSimilar(entries.first);
  }

  /// Same as lookup(), but uses a pre-computed embedding instead of
  /// calling the embedding API again. Use this when the caller already
  /// has the question's embedding for another purpose (e.g. RAG retrieval).
  Future<CacheResult> lookupWithEmbedding(
    String courseId,
    List<double> embedding,
  ) async {
    final rows = await _matrixApi.callMatchAiCache(
      courseId: courseId,
      embedding: embedding,
      threshold: _similarThreshold,
      count: 5,
    );

    if (rows.isEmpty) return CacheMiss();

    final entries = rows.map((r) => CacheEntry.fromRow(r)).toList();
    final exactMatches =
        entries.where((e) => e.similarity >= _exactThreshold).toList();

    if (exactMatches.isNotEmpty) {
      final chosen = exactMatches[_random.nextInt(exactMatches.length)];
      return CacheHit(chosen);
    }

    return CacheSimilar(entries.first);
  }

  Future<void> save(
    String courseId,
    String question,
    String answer, {
    bool bypassDedupGuard = false,
  }) async {
    final embedding = await _embeddingApi.embed(question);

    if (!bypassDedupGuard) {
      // Guard: skip insert if a near-duplicate already exists.
      final quick = await _matrixApi.callMatchAiCache(
        courseId: courseId,
        embedding: embedding,
        threshold: _exactThreshold,
        count: 1,
      );
      if (quick.isNotEmpty) return;
    }

    await _matrixApi.insertAiCache({
      'course_id': courseId,
      'question': question,
      'answer': answer,
      'embedding': embedding,
    });
  }

  Future<void> incrementHit(String entryId) async {
    await _matrixApi.patchAiCacheHitCount(entryId);
  }
}
