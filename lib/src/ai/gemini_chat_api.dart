import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
    Map<String, String> availableMedia = const {},
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
        'FORMATTING: Use the following formatting only where it genuinely '
        'improves clarity — do not force it into every answer:\n'
        '- Headings: # for main heading, ## for subheading, ### for minor '
        'heading (use sparingly, only for longer multi-part answers)\n'
        '- **bold**, *italic*, `inline code` for emphasis\n'
        '- Bullet lists with "- " and numbered lists with "1. "\n'
        '- Tables: use markdown pipe format only, e.g.:\n'
        '  | Header 1 | Header 2 |\n'
        '  |----------|----------|\n'
        '  | value    | value    |\n'
        '  Do NOT use ASCII box-drawing tables (with +---+ borders).\n'
        '- Math: wrap inline math in single dollar signs like \$x^2\$, and '
        'standalone equations in double dollar signs on their own lines '
        'like \$\$\\int x^2 dx = \\frac{x^3}{3} + C\$\$. Use standard LaTeX '
        'syntax inside the dollar signs.\n'
        '- Code: use triple-backtick fenced blocks for code snippets.\n'
        'For a short, simple answer, plain sentences are fine — do not add '
        'headings or tables to a one-line answer.\n\n'
        '${_buildMediaSection(availableMedia)}'
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
      if (response.statusCode == 429) {
        debugPrint(
          '[GeminiChatApi] ⚠️  QUOTA EXCEEDED (429) — '
          'Gemini API rate limit hit. '
          'Wait a minute or check your quota at https://aistudio.google.com. '
          'Raw body: $body',
        );
      }
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

  /// Generates one comprehension-check question (and its correct answer)
  /// testing understanding of [answerText], grounded in [courseContext].
  /// Returns null if parsing fails (caller should treat as "skip quiz
  /// this time" rather than erroring the whole chat flow).
  Future<QuizQuestion?> generateQuizQuestion({
    required String courseTitle,
    required String courseContext,
    required String answerText,
  }) async {
    if (_geminiApiKey.isEmpty) return null;

    final prompt =
        'Based on this explanation given to a student studying '
        '"$courseTitle":\n\n$answerText\n\n'
        'Write ONE short comprehension-check question testing whether the '
        'student understood this specific explanation. Then write the '
        'correct answer to that question.\n'
        'Respond in EXACTLY this format, nothing else:\n'
        'QUESTION: <the question>\n'
        'ANSWER: <the correct answer>';

    try {
      final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final data = jsonDecode(body) as Map<String, dynamic>;
      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = candidates.first['content'];
      if (content is! Map<String, dynamic> || content['parts'] is! List) return null;
      final text = (content['parts'] as List)
          .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
          .join();

      final qMatch = RegExp(r'QUESTION:\s*(.+?)(?=\nANSWER:|$)', dotAll: true).firstMatch(text);
      final aMatch = RegExp(r'ANSWER:\s*(.+)$', dotAll: true).firstMatch(text);
      if (qMatch == null || aMatch == null) return null;

      final question = qMatch.group(1)!.trim();
      final answer = aMatch.group(1)!.trim();
      if (question.isEmpty || answer.isEmpty) return null;

      return QuizQuestion(question: question, correctAnswer: answer);
    } catch (e) {
      return null;
    }
  }

  String _buildMediaSection(Map<String, String> availableMedia) {
    if (availableMedia.isEmpty) return '';
    final lines = availableMedia.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');
    return 'AVAILABLE IMAGES: You may reference at most ONE of the '
        'following existing course images if — and only if — it is '
        'directly relevant to your answer. To include one, put it on its '
        'own line using EXACTLY this format: [IMG: the_exact_key]\n'
        'Do NOT invent keys that are not in this list. Do NOT include an '
        'image unless it genuinely helps explain your answer.\n'
        '$lines\n\n';
  }
}
