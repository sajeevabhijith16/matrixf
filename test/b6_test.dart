import 'package:flutter_test/flutter_test.dart';
import 'package:matrixf/src/ai/gemini_chat_api.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('GeminiChatApi returns image token when relevant', () async {
    final reply = await GeminiChatApi().sendMessage(
      courseTitle: 'Mathematics',
      courseContext: 'Integration is the area under a curve...',
      history: [],
      question: 'Show me a diagram of the area under a curve',
      availableMedia: {'integration_areaunderthecurve': 'area under the curve , integration'},
    );
    print('[AI-DEBUG-1] $reply');
  });

  test('GeminiChatApi ignores image token when irrelevant', () async {
    final reply = await GeminiChatApi().sendMessage(
      courseTitle: 'Mathematics',
      courseContext: 'Integration is the area under a curve...',
      history: [],
      question: 'What is the power rule?',
      availableMedia: {'integration_areaunderthecurve': 'area under the curve , integration'},
    );
    print('[AI-DEBUG-2] $reply');
  });
}
