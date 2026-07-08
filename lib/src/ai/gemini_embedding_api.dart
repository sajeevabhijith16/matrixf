import 'dart:convert';
import 'dart:io';

const _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

class GeminiEmbeddingApiException implements Exception {
  GeminiEmbeddingApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GeminiEmbeddingApi {
  GeminiEmbeddingApi({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  // gemini-embedding-001 replaced text-embedding-004 (shut down Jan 14, 2026).
  // Default output is 3072 dims; we force 768 via outputDimensionality to
  // match the vector(768) column created in Module 1.
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-embedding-001:embedContent';

  /// Returns a 768-element embedding vector for [text].
  Future<List<double>> embed(String text) async {
    if (_geminiApiKey.isEmpty) {
      throw GeminiEmbeddingApiException(
        'GEMINI_API_KEY is not set. Use --dart-define=GEMINI_API_KEY=<key>.',
      );
    }

    final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': 'models/gemini-embedding-001',
        'content': {
          'parts': [
            {'text': text},
          ],
        },
        'taskType': 'SEMANTIC_SIMILARITY',
        'outputDimensionality': 768,
      }),
    );

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      throw GeminiEmbeddingApiException(
        'Embedding failed: ${response.statusCode} — $body',
      );
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw GeminiEmbeddingApiException(
        'Embedding failed: invalid response body.',
      );
    }

    final embedding = data['embedding'];
    if (embedding is! Map<String, dynamic> || embedding['values'] is! List) {
      throw GeminiEmbeddingApiException(
        'Embedding failed: unexpected response shape.',
      );
    }

    final values = (embedding['values'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    if (values.length != 768) {
      throw GeminiEmbeddingApiException(
        'Embedding failed: expected 768 values, got ${values.length}.',
      );
    }

    return values;
  }
}
