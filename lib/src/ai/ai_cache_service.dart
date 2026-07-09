import 'ai_models.dart';
import 'gemini_embedding_api.dart';
import '../api.dart';

class AiCacheService {
  AiCacheService({
    required GeminiEmbeddingApi embeddingApi,
    required MatrixApi matrixApi,
  }) : _embeddingApi = embeddingApi,
       _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final MatrixApi _matrixApi;

  // Calibrated for gemini-embedding-001 (SEMANTIC_SIMILARITY, 768-dim).
  // Real measurements: identical=1.0, rephrase=0.954, related-different-intent=0.906,
  // unrelated-topic=0.802, totally-unrelated=0.679.
  static const double _exactThreshold = 0.93; // same question → return cached
  static const double _similarThreshold = 0.85; // related → ask "Did you mean?"

  Future<CacheResult> lookup(String courseId, String question) async {
    final embedding = await _embeddingApi.embed(question);

    final rows = await _matrixApi.callMatchAiCache(
      courseId: courseId,
      embedding: embedding,
      threshold: _similarThreshold,
      count: 3,
    );

    if (rows.isEmpty) return CacheMiss();

    final best = rows.first;
    final entry = CacheEntry.fromRow(best);

    if (entry.similarity >= _exactThreshold) {
      return CacheHit(entry);
    }
    return CacheSimilar(entry);
  }

  Future<void> save(String courseId, String question, String answer) async {
    final embedding = await _embeddingApi.embed(question);

    // Guard: skip insert if a near-duplicate already exists.
    final quick = await _matrixApi.callMatchAiCache(
      courseId: courseId,
      embedding: embedding,
      threshold: _exactThreshold,
      count: 1,
    );
    if (quick.isNotEmpty) return;

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
