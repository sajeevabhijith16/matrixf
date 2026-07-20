import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_models.dart';

class ChatSession {
  ChatSession({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.messages,
    required this.lastUpdated,
  });

  final String id;
  final String courseId;
  final String courseTitle;
  final List<ChatMessage> messages;
  final DateTime lastUpdated;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'courseTitle': courseTitle,
        'lastUpdated': lastUpdated.toIso8601String(),
        'messages': messages
            .where((m) => !m.isLoading) // don't persist transient loading bubbles
            .map((m) => {
                  'role': m.role.name,
                  'content': m.content,
                  'timestamp': m.timestamp.toIso8601String(),
                  'isError': m.isError,
                  'isConfirm': m.isConfirm,
                  'isQuiz': m.isQuiz,
                  'quizCorrectAnswer': m.quizCorrectAnswer,
                  // Note: quizResult could be saved too if we wanted to persist correct/incorrect status
                  // For now, following the exact spec from G1
                })
            .toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        courseTitle: json['courseTitle'] as String,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        messages: (json['messages'] as List).map((m) {
          final map = m as Map<String, dynamic>;
          return ChatMessage(
            role: (map['role'] as String) == 'user' ? ChatRole.user : ChatRole.assistant,
            content: map['content'] as String,
            timestamp: DateTime.parse(map['timestamp'] as String),
            isError: map['isError'] as bool? ?? false,
            isConfirm: map['isConfirm'] as bool? ?? false,
            isQuiz: map['isQuiz'] as bool? ?? false,
            quizCorrectAnswer: map['quizCorrectAnswer'] as String?,
          );
        }).toList(),
      );
}

class LocalChatHistory {
  static const _storageKey = 'ai_chat_sessions';
  static const _maxSessions = 20;

  Future<List<ChatSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final sessions = list
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList();
      sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      return sessions;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSession(ChatSession session) async {
    final sessions = await loadAll();
    sessions.removeWhere((s) => s.id == session.id);
    sessions.insert(0, session);
    if (sessions.length > _maxSessions) {
      sessions.removeRange(_maxSessions, sessions.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> deleteSession(String id) async {
    final sessions = await loadAll();
    sessions.removeWhere((s) => s.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }
}
