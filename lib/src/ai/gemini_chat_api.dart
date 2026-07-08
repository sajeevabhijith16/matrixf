import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';

const _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

class GeminiChatApiException implements Exception {
  GeminiChatApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GeminiChatApi {
  GeminiChatApi({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  // gemini-2.0-flash was shut down June 1, 2026.
  // gemini-2.5-flash is the current stable replacement (free-tier friendly).
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash:generateContent';

  static const int _maxContextChars = 20000;

  /// [courseTitle]   – shown in system instruction
  /// [courseContext] – raw module text, trimmed to 20 000 chars
  /// [history]       – prior ChatMessages for multi-turn context
  /// [question]      – the current user question
  Future<String> sendMessage({
    required String courseTitle,
    required String courseContext,
    required List<ChatMessage> history,
    required String question,
  }) async {
    if (_geminiApiKey.isEmpty) {
      throw GeminiChatApiException(
        'GEMINI_API_KEY is not set. Use --dart-define=GEMINI_API_KEY=<key>.',
      );
    }

    final trimmedContext = courseContext.length > _maxContextChars
        ? courseContext.substring(0, _maxContextChars)
        : courseContext;

    final systemInstruction =
        'You are an AI tutor for the course "$courseTitle".\n'
        'Your job is to answer student questions ONLY about the content of '
        'this course.\n'
        'If a question is unrelated to the course, politely say:\n'
        '"I can only help with questions about $courseTitle. Please ask '
        'something related to the course."\n'
        'Do not make up information. Base all your answers solely on the '
        'course content below.\n\n'
        '--- COURSE CONTENT START ---\n'
        '$trimmedContext\n'
        '--- COURSE CONTENT END ---';

    final contents = <Map<String, dynamic>>[
      for (final m in history)
        {
          'role': m.role == ChatRole.user ? 'user' : 'model',
          'parts': [
            {'text': m.content},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': question},
        ],
      },
    ];

    final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
        'contents': contents,
      }),
    );

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      throw GeminiChatApiException(
        'Chat request failed: ${response.statusCode} — $body',
      );
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw GeminiChatApiException(
        'Chat request failed: invalid response body.',
      );
    }

    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw GeminiChatApiException(
        'Chat request failed: no candidates returned (possibly blocked by safety filters).',
      );
    }

    final content = candidates.first['content'];
    if (content is! Map<String, dynamic> || content['parts'] is! List) {
      throw GeminiChatApiException(
        'Chat request failed: unexpected response shape.',
      );
    }

    final parts = content['parts'] as List;
    final text = parts
        .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
        .join();

    if (text.isEmpty) {
      throw GeminiChatApiException('Chat request failed: empty response text.');
    }

    return text;
  }
}
