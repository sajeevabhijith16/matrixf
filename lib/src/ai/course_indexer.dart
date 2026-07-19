import 'content_chunker.dart';
import 'gemini_embedding_api.dart';
import '../api.dart';

/// Progress callback: (modulesDone, totalModules, chunksIndexedSoFar)
typedef IndexProgressCallback = void Function(
    int modulesDone, int totalModules, int chunksIndexed);

class AiCourseIndexer {
  AiCourseIndexer({
    required GeminiEmbeddingApi embeddingApi,
    required MatrixApi matrixApi,
  })  : _embeddingApi = embeddingApi,
        _matrixApi = matrixApi;

  final GeminiEmbeddingApi _embeddingApi;
  final MatrixApi _matrixApi;

  /// Reindexes an entire course: deletes existing chunks, then chunks and
  /// embeds every module's content, inserting fresh rows.
  /// Returns the total number of chunks indexed.
  Future<int> reindexCourse(
    String courseId, {
    IndexProgressCallback? onProgress,
  }) async {
    await _matrixApi.adminDeleteCourseChunks(courseId);

    final modules = await _matrixApi.listModulesByCourseId(courseId);
    var chunksIndexed = 0;

    for (var i = 0; i < modules.length; i++) {
      final module = modules[i];
      final moduleText = await _matrixApi.getModuleText(module.id);
      final chunks = chunkCourseContent(
        '${module.title}\n${moduleText.content}',
      );

      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunkText = chunks[chunkIndex];
        final embedding = await _embeddingApi.embed(chunkText);
        await _matrixApi.adminInsertCourseChunk(
          courseId: courseId,
          moduleId: module.id,
          chunkIndex: chunkIndex,
          chunkText: chunkText,
          embedding: embedding,
        );
        chunksIndexed++;
      }

      onProgress?.call(i + 1, modules.length, chunksIndexed);
    }

    return chunksIndexed;
  }
}
