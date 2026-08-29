import 'package:flutter/material.dart';
import 'package:matrixf/src/models/models.dart';

import '../app.dart';
import '../ai/ai_models.dart';
import '../ai/ai_cache_service.dart';
import '../ai/gemini_chat_api.dart';
import '../ai/gemini_embedding_api.dart';
import '../ai/ai_quiz_service.dart';
import '../ai/local_chat_history.dart';
import '../components/text_blocks.dart';
import 'course_picker.dart';
import 'ai_answer_renderer.dart';

class AiChatOverlay extends StatelessWidget {
  const AiChatOverlay({super.key, required this.child, this.initialCourse});

  final Widget child;
  final AiCourse? initialCourse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          bottom: 96, // 80 (NavigationBar height) + 16 margin
          right: 16,
          child: _AiFab(initialCourse: initialCourse),
        ),
      ],
    );
  }
}

class _AiFab extends StatefulWidget {
  const _AiFab({this.initialCourse});
  final AiCourse? initialCourse;

  @override
  State<_AiFab> createState() => _AiFabState();
}

class _AiFabState extends State<_AiFab> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onTap() {
    openAiChatSheet(context, initialCourse: widget.initialCourse);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pressed ? 1.0 : _pulseAnimation.value,
              child: child,
            );
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF18664B), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Opens the AI chat sheet. Call this from anywhere with a BuildContext
/// (the FAB, or later, ReaderScreen's AppBar icon in Module 9).
void openAiChatSheet(BuildContext context, {AiCourse? initialCourse, String? initialModuleId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(initialCourse: initialCourse, initialModuleId: initialModuleId),
  );
}

enum _ChatPhase {
  courseSelect, // showing CoursePicker
  awaitingConfirm, // showing "Did you mean?" bubble, input locked
  chatting, // normal Q&A conversation
}

class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet({this.initialCourse, this.initialModuleId});
  final AiCourse? initialCourse;
  final String? initialModuleId;

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  late _ChatPhase _phase;
  AiCourse? _selectedCourse;
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String? _currentModuleId;
  final Map<String, List<ModuleQa>> _qaByModule = {};
  List<ModuleQa> get _allQaPool => _qaByModule.values.expand((l) => l).toList();
  List<ModuleQa> get _revisionPool {
    if (_currentModuleId != null && _qaByModule.containsKey(_currentModuleId)) {
      return _qaByModule[_currentModuleId!] ?? [];
    }
    return _allQaPool;
  }

  bool _revisionMode = false;
  List<ModuleQa> _revisionRemaining = [];
  List<ModuleQa> _revisionRetryQueue = [];
  int _revisionCorrectCount = 0;
  int _revisionTotalAnswered = 0;

  final LocalChatHistory _history = LocalChatHistory();
  late String _sessionId;

  bool _isSending = false;
  String _lastFailedQuestion = '';
  String _pendingQuestion = '';
  CacheEntry? _pendingSimilar;
  String _courseContext = '';
  bool _courseIsIndexed = false;
  Map<String, ModuleMedia> _courseMediaMap = {};
  // ignore: unused_field
  Map<String, String> _availableMedia = {}; // token -> description

  // Course picker state
  List<AiCourse> _courses = [];
  bool _loadingCourses = false;

  bool _servicesInitialized = false;
  late final GeminiEmbeddingApi _embeddingApi;
  late final GeminiChatApi _chatApi;
  late final AiCacheService _cacheService;
  late final AiQuizService _quizService;

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentModuleId = widget.initialModuleId;
    if (widget.initialCourse != null) {
      _selectedCourse = widget.initialCourse;
      _phase = _ChatPhase.chatting;
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content:
              'Hi! I\'m ready to help you with **${widget.initialCourse!.title}**. '
              'What would you like to learn today?',
          timestamp: DateTime.now(),
        ),
      );
    } else {
      _phase = _ChatPhase.courseSelect;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesInitialized) {
      _embeddingApi = GeminiEmbeddingApi();
      _chatApi = GeminiChatApi();
      _cacheService = AiCacheService(
        embeddingApi: _embeddingApi,
        matrixApi: MatrixScope.of(context).api,
      );
      _quizService = AiQuizService(
        embeddingApi: _embeddingApi,
        chatApi: _chatApi,
        matrixApi: MatrixScope.of(context).api,
      );
      _servicesInitialized = true;
      if (widget.initialCourse != null && _courseContext.isEmpty) {
        _loadCourseContext(widget.initialCourse!);
      }
      if (_phase == _ChatPhase.courseSelect) {
        _loadCourses();
      }
    }
  }

  Future<void> _loadCourses() async {
    setState(() => _loadingCourses = true);
    try {
      final rawCourses = await MatrixScope.of(context).api.listCourses();
      if (!mounted) return;
      setState(() {
        _courses = rawCourses
            .map((c) => AiCourse(id: c.id, title: c.title, slug: c.slug))
            .toList();
      });
    } catch (e) {
      debugPrint('[AiChatSheet] Failed to load courses: $e');
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onCourseSelected(AiCourse course) {
    final scope = MatrixScope.of(context);
    if (!scope.api.isSignedIn) {
      Navigator.of(context).pop(); // close the sheet
      scope.requestAiSignIn(
        course,
      ); // switches to Profile tab, remembers course
      return;
    }

    setState(() {
      _selectedCourse = course;
      _phase = _ChatPhase.chatting;
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content:
              'Hi! I\'m ready to help you with **${course.title}**. '
              'What would you like to learn today?',
          timestamp: DateTime.now(),
        ),
      );
    });
    _loadCourseContext(course);
    _persistSession();
  }

  void _persistSession() {
    if (_selectedCourse == null) return;
    _history.saveSession(
      ChatSession(
        id: _sessionId,
        courseId: _selectedCourse!.id,
        courseTitle: _selectedCourse!.title,
        messages: List.of(_messages),
        lastUpdated: DateTime.now(),
      ),
    );
  }

  Future<void> _resumeSession(ChatSession session) async {
    setState(() {
      _sessionId = session.id;
      _selectedCourse = AiCourse(
        id: session.courseId,
        title: session.courseTitle,
        slug: '',
      );
      _messages
        ..clear()
        ..addAll(session.messages);
      _phase = _ChatPhase.chatting;
    });
    await _loadCourseContext(_selectedCourse!);
  }

  Future<void> _loadCourseContext(AiCourse course) async {
    try {
      final api = MatrixScope.of(context).api;
      final hasChunks = await api.courseHasChunks(course.id);

      if (!mounted) return;
      setState(() => _courseIsIndexed = hasChunks);

      if (hasChunks) {
        // RAG path: media map is still built from full module content since
        // images can appear anywhere; retrieval itself happens per-question
        // in _buildRetrievedContext(). No bulk course_context needed here.
        final modules = await api.listModulesByCourseId(course.id);
        final mergedMediaMap = <String, ModuleMedia>{};
        final allText = StringBuffer();
        for (final m in modules) {
          final text = await api.getModuleText(m.id);
          mergedMediaMap.addAll(text.mediaMap);
          _qaByModule[m.id] = text.questions.where((q) => q.embedding != null).toList();
          allText.write(text.content);
        }
        final tokenMap = extractMediaTokensWithDescriptions(allText.toString());
        final referencedKeys = tokenMap.keys.toList();
        final dbDescriptions = referencedKeys.isEmpty
            ? <String, String>{}
            : await api.getImageDescriptions(referencedKeys);

        final mergedDescriptions = <String, String>{};
        for (final key in referencedKeys) {
          final dbDesc = dbDescriptions[key];
          final inlineDesc = tokenMap[key];
          if (dbDesc != null && dbDesc.trim().isNotEmpty) {
            mergedDescriptions[key] = dbDesc;
          } else if (inlineDesc != null && inlineDesc.trim().isNotEmpty) {
            mergedDescriptions[key] = inlineDesc;
          }
        }
        if (!mounted) return;
        setState(() {
          _courseMediaMap = mergedMediaMap;
          _availableMedia = mergedDescriptions;
        });
      } else {
        // Fallback: course not yet reindexed — use the old bulk-context
        // approach so chat still works, just without retrieval precision.
        final modules = await api.listModulesByCourseId(course.id);
        final buffer = StringBuffer();
        final mergedMediaMap = <String, ModuleMedia>{};
        for (final m in modules.take(3)) {
          final text = await api.getModuleText(m.id);
          buffer.write('${m.title}\n${text.content}\n\n');
          mergedMediaMap.addAll(text.mediaMap);
          _qaByModule[m.id] = text.questions.where((q) => q.embedding != null).toList();
          if (buffer.length > 20000) break;
        }
        final trimmedContext = buffer.toString().substring(
          0,
          buffer.length.clamp(0, 20000),
        );
        final tokenMap = extractMediaTokensWithDescriptions(trimmedContext);
        final referencedKeys = tokenMap.keys.toList();
        final dbDescriptions = referencedKeys.isEmpty
            ? <String, String>{}
            : await api.getImageDescriptions(referencedKeys);

        final mergedDescriptions = <String, String>{};
        for (final key in referencedKeys) {
          final dbDesc = dbDescriptions[key];
          final inlineDesc = tokenMap[key];
          if (dbDesc != null && dbDesc.trim().isNotEmpty) {
            mergedDescriptions[key] = dbDesc;
          } else if (inlineDesc != null && inlineDesc.trim().isNotEmpty) {
            mergedDescriptions[key] = inlineDesc;
          }
        }
        if (!mounted) return;
        setState(() {
          _courseContext = trimmedContext;
          _courseMediaMap = mergedMediaMap;
          _availableMedia = mergedDescriptions;
        });
      }
    } catch (e) {
      debugPrint('[AiChatSheet] Failed to load course context: $e');
    }
  }

  /// Retrieves the most relevant chunks for [questionEmbedding] and joins
  /// them into a context string for this specific question. Falls back to
  /// the static _courseContext if the course isn't indexed yet.
  Future<String> _buildRetrievedContext(List<double> questionEmbedding) async {
    if (!_courseIsIndexed) return _courseContext;

    final rows = await MatrixScope.of(context).api.callMatchCourseChunks(
      courseId: _selectedCourse!.id,
      embedding: questionEmbedding,
      count: 5,
    );
    if (rows.isEmpty) return '';
    return rows
        .map((r) => r['chunk_text']?.toString() ?? '')
        .join('\n\n---\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        height: mediaQuery.size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(),
            Expanded(
              child: _phase == _ChatPhase.courseSelect
                  ? _buildCoursePickerPhase(context)
                  : _buildChatList(),
            ),
            if (_phase != _ChatPhase.courseSelect) _buildInputRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _showHistoryMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 22,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(_revisionMode ? Icons.school : Icons.school_outlined),
            tooltip: _revisionMode ? 'Exit Revision Mode' : 'Start Revision Mode',
            onPressed: _phase == _ChatPhase.chatting
                ? () => _revisionMode ? _endRevisionMode() : _startRevisionMode()
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 22,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF18664B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedCourse == null
                  ? 'AI Tutor'
                  : 'AI Tutor — ${_selectedCourse!.title}',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursePickerPhase(BuildContext context) {
    if (_loadingCourses) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF18664B)),
            SizedBox(height: 16),
            Text('Loading courses...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_courses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No courses available',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 4),
              Text(
                'Check your connection and try again.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CoursePicker(courses: _courses, onSelected: _onCourseSelected),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildBubble(_messages[index]),
    );
  }

  Widget _buildBubble(ChatMessage m) {
    if (m.isLoading) return _LoadingBubble();
    if (m.isError) {
      return _ErrorBubble(message: m.content, onRetry: _onRetryLastMessage);
    }
    if (m.isQuiz) {
      return _QuizBubble(
        message: m,
        onSubmit: (answer) => _onQuizSubmit(m, answer),
      );
    }
    if (m.isConfirm) {
      return _ConfirmBubble(
        originalQuestion: m.content,
        onYes: _onConfirmYes,
        onNo: _onConfirmNo,
      );
    }
    if (m.role == ChatRole.user) return _UserBubble(text: m.content);
    return _AssistantBubble(text: m.content, mediaMap: _courseMediaMap);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  bool _wasAnswerAlreadyShown(String answer) {
    return _messages.any(
      (m) =>
          m.role == ChatRole.assistant &&
          !m.isLoading &&
          !m.isError &&
          !m.isConfirm &&
          m.content == answer,
    );
  }

  Future<void> _onSend(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _isSending || _selectedCourse == null) return;
    _inputCtrl.clear();

    setState(() {
      _isSending = true;
      _messages.add(
        ChatMessage(
          role: ChatRole.user,
          content: trimmed,
          timestamp: DateTime.now(),
        ),
      );
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content: '',
          timestamp: DateTime.now(),
          isLoading: true,
        ),
      );
    });
    _scrollToBottom();

    try {
      final questionEmbedding = await _embeddingApi.embed(trimmed);
      final result = await _cacheService.lookupWithEmbedding(
        _selectedCourse!.id,
        questionEmbedding,
      );
      if (!mounted) return;
      setState(() => _messages.removeLast()); // remove loading bubble

      switch (result) {
        case CacheHit(:final entry):
          if (_wasAnswerAlreadyShown(entry.answer)) {
            // Same answer already shown in this conversation — force a
            // fresh Gemini call instead of repeating it verbatim.
            final retrievedContext = await _buildRetrievedContext(
              questionEmbedding,
            );
            final answer = await _chatApi.sendMessage(
              courseTitle: _selectedCourse!.title,
              courseContext: retrievedContext,
              history: _messages
                  .where((m) => !m.isLoading && !m.isError && !m.isConfirm)
                  .toList(),
              question:
                  '$trimmed\n\n(Note: I asked something very similar '
                  'earlier in this chat and already have that answer — '
                  'please explain it differently, e.g. with a new example '
                  'or a different angle, rather than repeating the same '
                  'explanation.)',
              availableMedia: _availableMedia,
            );
            if (!mounted) return;
            setState(() {
              _messages.add(
                ChatMessage(
                  role: ChatRole.assistant,
                  content: answer,
                  timestamp: DateTime.now(),
                ),
              );
            });
            await _cacheService.save(
              _selectedCourse!.id,
              trimmed,
              answer,
              bypassDedupGuard: true,
            );
          } else {
            setState(() {
              _messages.add(
                ChatMessage(
                  role: ChatRole.assistant,
                  content: entry.answer,
                  timestamp: DateTime.now(),
                ),
              );
            });
            await _cacheService.incrementHit(entry.id);
          }

        case CacheSimilar(:final best):
          if (_wasAnswerAlreadyShown(best.answer)) {
            // Would just confirm into a repeat — skip the "Did you mean?"
            // step entirely and get a fresh, differently-angled answer.
            final retrievedContext = await _buildRetrievedContext(
              questionEmbedding,
            );
            final answer = await _chatApi.sendMessage(
              courseTitle: _selectedCourse!.title,
              courseContext: retrievedContext,
              history: _messages
                  .where((m) => !m.isLoading && !m.isError && !m.isConfirm)
                  .toList(),
              question:
                  '$trimmed\n\n(Note: I asked something very similar '
                  'earlier in this chat and already have that answer — '
                  'please explain it differently, e.g. with a new example '
                  'or a different angle, rather than repeating the same '
                  'explanation.)',
              availableMedia: _availableMedia,
            );
            if (!mounted) return;
            setState(() {
              _messages.add(
                ChatMessage(
                  role: ChatRole.assistant,
                  content: answer,
                  timestamp: DateTime.now(),
                ),
              );
            });
            await _cacheService.save(
              _selectedCourse!.id,
              trimmed,
              answer,
              bypassDedupGuard: true,
            );
          } else {
            _pendingSimilar = best;
            _pendingQuestion = trimmed;
            setState(() {
              _messages.add(
                ChatMessage(
                  role: ChatRole.assistant,
                  content: best.question,
                  timestamp: DateTime.now(),
                  isConfirm: true,
                ),
              );
              _phase = _ChatPhase.awaitingConfirm;
            });
          }

        case CacheMiss():
          final retrievedContext = await _buildRetrievedContext(
            questionEmbedding,
          );
          final answer = await _chatApi.sendMessage(
            courseTitle: _selectedCourse!.title,
            courseContext: retrievedContext,
            history: _messages
                .where((m) => !m.isLoading && !m.isError && !m.isConfirm)
                .toList(),
            question: trimmed,
            availableMedia: _availableMedia,
          );
          if (!mounted) return;
          setState(() {
            _messages.add(
              ChatMessage(
                role: ChatRole.assistant,
                content: answer,
                timestamp: DateTime.now(),
              ),
            );
          });
          await _cacheService.save(_selectedCourse!.id, trimmed, answer);
          _generateQuizFor(
            originalQuestion: trimmed,
            originalQuestionEmbedding: questionEmbedding,
            answerText: answer,
          );
      }
    } catch (e) {
      _lastFailedQuestion = trimmed;
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isLoading) {
          _messages.removeLast();
        }
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: e.toString(),
            timestamp: DateTime.now(),
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
      _persistSession();
    }
  }

  void _onRetryLastMessage() {
    if (_lastFailedQuestion.isEmpty) return;
    setState(() => _messages.removeLast()); // remove the error bubble
    _onSend(_lastFailedQuestion);
  }

  void _onConfirmYes() {
    if (_pendingSimilar == null) return;
    final answer = _pendingSimilar!.answer;
    final id = _pendingSimilar!.id;
    setState(() {
      _messages.removeLast(); // remove isConfirm bubble
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content: answer,
          timestamp: DateTime.now(),
        ),
      );
      _phase = _ChatPhase.chatting;
      _pendingSimilar = null;
      _pendingQuestion = '';
    });
    _cacheService.incrementHit(id);
    _scrollToBottom();
    _persistSession();
  }

  Future<void> _onConfirmNo() async {
    if (_pendingSimilar == null) return;
    final question = _pendingQuestion;
    setState(() {
      _messages.removeLast(); // remove isConfirm bubble
      _phase = _ChatPhase.chatting;
      _pendingSimilar = null;
      _pendingQuestion = '';
    });
    // Skip cache entirely — user said this is NOT the cached question,
    // so go straight to Gemini and save a new entry.
    await _sendDirect(question);
  }

  /// Sends [question] directly to Gemini, bypassing the cache lookup.
  /// Used by _onConfirmNo to avoid re-triggering "Did you mean?".
  Future<void> _sendDirect(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _isSending || _selectedCourse == null) return;

    setState(() {
      _isSending = true;
      _messages.add(
        ChatMessage(
          role: ChatRole.user,
          content: trimmed,
          timestamp: DateTime.now(),
        ),
      );
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          content: '',
          timestamp: DateTime.now(),
          isLoading: true,
        ),
      );
    });
    _scrollToBottom();

    try {
      final questionEmbedding = await _embeddingApi.embed(trimmed);
      final retrievedContext = await _buildRetrievedContext(questionEmbedding);
      final answer = await _chatApi.sendMessage(
        courseTitle: _selectedCourse!.title,
        courseContext: retrievedContext,
        history: _messages
            .where((m) => !m.isLoading && !m.isError && !m.isConfirm)
            .toList(),
        question: trimmed,
        availableMedia: _availableMedia,
      );
      if (!mounted) return;
      setState(() {
        _messages.removeLast(); // remove loading bubble
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: answer,
            timestamp: DateTime.now(),
          ),
        );
      });
      await _cacheService.save(_selectedCourse!.id, trimmed, answer);
    } catch (e) {
      _lastFailedQuestion = trimmed;
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isLoading)
          _messages.removeLast();
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: e.toString(),
            timestamp: DateTime.now(),
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
      _persistSession();
    }
  }

  Future<void> _generateQuizFor({
    required String originalQuestion,
    required List<double> originalQuestionEmbedding,
    required String answerText,
  }) async {
    if (_selectedCourse == null) return;
    try {
      final quiz = await _quizService.getQuizQuestion(
        courseId: _selectedCourse!.id,
        courseTitle: _selectedCourse!.title,
        courseContext: _courseContext,
        originalQuestion: originalQuestion,
        originalQuestionEmbedding: originalQuestionEmbedding,
        answerText: answerText,
      );
      if (quiz == null || !mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: quiz.question,
            timestamp: DateTime.now(),
            isQuiz: true,
            quizCorrectAnswer: quiz.correctAnswer,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[AiChatSheet] Quiz generation failed (non-fatal): $e');
    }
  }

  void _startRevisionMode() {
    if (_revisionPool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No revision questions available yet for this course.')),
      );
      return;
    }
    setState(() {
      _revisionMode = true;
      _revisionRemaining = List.of(_revisionPool)..shuffle();
      _revisionRetryQueue = [];
      _revisionCorrectCount = 0;
      _revisionTotalAnswered = 0;
    });
    _nextRevisionQuestion();
  }

  void _nextRevisionQuestion() {
    if (_revisionRemaining.isEmpty && _revisionRetryQueue.isNotEmpty) {
      _revisionRemaining = List.of(_revisionRetryQueue)..shuffle();
      _revisionRetryQueue = [];
    }
    if (_revisionRemaining.isEmpty) {
      _endRevisionMode();
      return;
    }
    final next = _revisionRemaining.removeAt(0);
    setState(() {
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        content: next.question,
        timestamp: DateTime.now(),
        isQuiz: true,
        isRevisionQuestion: true,
        quizCorrectAnswer: next.answer,
      ));
    });
    _scrollToBottom();
  }

  void _endRevisionMode() {
    final total = _revisionTotalAnswered;
    final correct = _revisionCorrectCount;
    setState(() {
      _revisionMode = false;
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        content: total == 0
            ? 'Revision session ended.'
            : 'Revision complete! You got $correct/$total correct.',
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  Future<void> _onQuizSubmit(ChatMessage quizMessage, String studentAnswer) async {
    if (quizMessage.quizCorrectAnswer == null) return;
    try {
      List<double>? correctEmbedding;
      if (quizMessage.isRevisionQuestion) {
        // Find the original ModuleQa to get its cached embedding.
        final match = _allQaPool.where((q) => q.answer == quizMessage.quizCorrectAnswer);
        if (match.isNotEmpty) correctEmbedding = match.first.embedding;
      }

      final result = await _quizService.validateAnswer(
        studentAnswer: studentAnswer,
        correctAnswer: quizMessage.quizCorrectAnswer!,
        correctAnswerEmbedding: correctEmbedding,
      );
      if (!mounted) return;

      setState(() {
        final index = _messages.indexOf(quizMessage);
        if (index != -1) {
          _messages[index] = quizMessage.copyWith(quizResult: result);
        }
      });

      if (quizMessage.isRevisionQuestion) {
        _revisionTotalAnswered++;
        if (result.result == ValidationResult.correct) {
          _revisionCorrectCount++;
        } else {
          // Find the original ModuleQa to requeue it.
          final match = _allQaPool.where((q) => q.question == quizMessage.content);
          if (match.isNotEmpty) _revisionRetryQueue.add(match.first);
        }
        // Brief pause so the student can see the result before advancing.
        await Future.delayed(const Duration(seconds: 2));
        if (mounted && _revisionMode) _nextRevisionQuestion();
      }
    } catch (e) {
      debugPrint('[AiChatSheet] Quiz validation failed: $e');
    }
  }

  Future<void> _showHistoryMenu() async {
    final sessions = await _history.loadAll();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) {
          if (sessions.isEmpty) {
            return const Center(child: Text('No past conversations yet.'));
          }
          return ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final firstUserMessage = s.messages.firstWhere(
                (m) => m.role == ChatRole.user,
                orElse: () => ChatMessage(
                  role: ChatRole.user,
                  content: 'New conversation',
                  timestamp: s.lastUpdated,
                ),
              );
              return ListTile(
                title: Text(
                  firstUserMessage.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  s.courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    await _history.deleteSession(s.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _resumeSession(s);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInputRow() {
    final canSend = _phase == _ChatPhase.chatting && !_isSending && !_revisionMode;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: canSend,
              onSubmitted: canSend ? (_) => _onSend(_inputCtrl.text) : null,
              decoration: const InputDecoration(
                hintText: 'Ask a question...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: canSend ? () => _onSend(_inputCtrl.text) : null,
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF18664B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, this.mediaMap = const {}});
  final String text;
  final Map<String, ModuleMedia> mediaMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFF18664B),
              ),
              const SizedBox(width: 6),
              Text(
                'AI Tutor',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF18664B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AiAnswerRenderer(content: text, mediaMap: mediaMap),
        ],
      ),
    );
  }
}

class _LoadingBubble extends StatefulWidget {
  @override
  State<_LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<_LoadingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_controller.value - i * 0.2) % 1.0;
                final opacity = (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2)).clamp(
                  0.3,
                  1.0,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF18664B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmBubble extends StatelessWidget {
  const _ConfirmBubble({
    required this.originalQuestion,
    required this.onYes,
    required this.onNo,
  });
  final String originalQuestion;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Did you mean:',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
            const SizedBox(height: 4),
            Text(
              '"$originalQuestion"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(onPressed: onYes, child: const Text('Yes')),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onNo,
                  child: const Text('No, ask something new'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizBubble extends StatefulWidget {
  const _QuizBubble({required this.message, required this.onSubmit});
  final ChatMessage message;
  final void Function(String studentAnswer) onSubmit;

  @override
  State<_QuizBubble> createState() => _QuizBubbleState();
}

class _QuizBubbleState extends State<_QuizBubble> {
  final TextEditingController _answerCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.message.quizResult;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Quick check',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(widget.message.content),
          const SizedBox(height: 10),
          if (result == null) ...[
            TextField(
              controller: _answerCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                hintText: 'Your answer...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _submitting || _answerCtrl.text.trim().isEmpty
                      ? null
                      : () {
                          setState(() => _submitting = true);
                          widget.onSubmit(_answerCtrl.text.trim());
                        },
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  result.result == ValidationResult.correct
                      ? Icons.check_circle
                      : Icons.cancel,
                  color: result.result == ValidationResult.correct
                      ? Colors.green
                      : Colors.orange,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  result.result == ValidationResult.correct
                      ? 'Correct!'
                      : 'Not quite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: result.result == ValidationResult.correct
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Correct answer: ${result.correctAnswer}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
