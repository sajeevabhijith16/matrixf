import '../widgets/ai_chat_overlay.dart';
import '../ai/ai_models.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';
import '../components/module_text_renderer.dart';
import 'dart:async';

// ─── Reader Screen ────────────────────────────────────────────────────────────

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.moduleId});
  final String moduleId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Future<ModuleText> _future;
  bool _initialized = false;
  List<Block>? _blocks;

  // ── Scroll / progress ──────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _readPercent = ValueNotifier(0.0);
  static const double _minSavedOffset = 50.0;

  // ── Shared-prefs key ───────────────────────────────────────────────────────
  String get _prefKey => 'reader_progress_${widget.moduleId}';

  // ── Search ─────────────────────────────────────────────────────────────────
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _activeMatchIndex = -1;
  int _totalMatches = 0;

  /// Block GlobalKeys, populated once the renderer builds.
  List<GlobalKey> _blockKeys = [];

  /// Flat match list (block index + char offsets) — mirrors what the renderer computed.
  List<_MatchRef> _matchRefs = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = MatrixScope.of(context).api.getModuleText(widget.moduleId);
      _future.then((data) {
        if (mounted) _onDataLoaded(data);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _saveProgress();
    _scrollController.dispose();
    _readPercent.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Scroll listener ────────────────────────────────────────────────────────
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    final pct = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
    if ((pct - _readPercent.value).abs() > 0.001) {
      _readPercent.value = pct;
    }
  }

  // ── SharedPreferences helpers ──────────────────────────────────────────────
  Future<void> _onDataLoaded(ModuleText data) async {
    _blocks = parseBlocks(data.content);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefKey) ?? 0.0;
    if (!mounted) return;
    if (saved > _minSavedOffset) {
      _showContinueDialog(saved);
    }
  }

  Future<void> _saveProgress() async {
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if (offset > _minSavedOffset) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKey, offset);
    } else {
      // Clear if at the top (start over was pressed or minimal scroll).
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    }
  }

  void _showContinueDialog(double savedOffset) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bookmark_rounded,
                  size: 28,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome back!',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'You were ${(_readPercent.value * 100).toStringAsFixed(0)}% through this module.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  ctx,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _clearProgress();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Start Over'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _jumpToOffset(savedOffset);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _jumpToOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          offset.clamp(0.0, maxExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Search helpers ─────────────────────────────────────────────────────────
  Timer? _searchDebounce;

  void _onSearchChanged(String query, ModuleText data) {
    final q = query.toLowerCase().trim();
    if (q == _searchQuery) return;

    final blocks = _blocks ?? parseBlocks(data.content);
    final refs = <_MatchRef>[];

    if (q.isNotEmpty) {
      for (int bi = 0; bi < blocks.length; bi++) {
        final text = _blockPlainTextForSearch(blocks[bi]).toLowerCase();
        int start = 0;
        while (true) {
          final idx = text.indexOf(q, start);
          if (idx == -1) break;
          refs.add(_MatchRef(bi, idx, idx + q.length));
          start = idx + 1;
        }
      }
    }

    setState(() {
      _searchQuery = q;
      _matchRefs = refs;
      _totalMatches = refs.length;
      _activeMatchIndex = refs.isEmpty ? -1 : 0;
    });

    if (refs.isNotEmpty) {
      _scrollToMatch(0);
    }
  }

  void _stepMatch(int delta) {
    if (_totalMatches == 0) return;
    final next = (_activeMatchIndex + delta) % _totalMatches;
    setState(() => _activeMatchIndex = next);
    _scrollToMatch(next);
  }

  void _scrollToMatch(int matchIdx) {
    if (matchIdx < 0 || matchIdx >= _matchRefs.length) return;
    final blockIdx = _matchRefs[matchIdx].blockIndex;
    if (blockIdx >= _blockKeys.length) return;
    final key = _blockKeys[blockIdx];
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.3, // show near top
    );
  }

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
      _searchCtrl.clear();
      _activeMatchIndex = -1;
      _totalMatches = 0;
      _matchRefs = [];
    });
  }

  String _blockPlainTextForSearch(dynamic b) {
    if (b is HeadingBlock) return b.text;
    if (b is ParagraphBlock) return b.text;
    if (b is QuoteBlock) return b.text;
    if (b is CodeBlock) return b.text;
    if (b is UlBlock) return b.items.join(' ');
    if (b is OlBlock) return b.items.join(' ');
    return '';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ModuleText>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: _buildAppBar(context, data),
          body: Column(
            children: [
              // ── Search bar ──────────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _searchOpen && data != null
                    ? _buildSearchBar(context, data)
                    : const SizedBox.shrink(),
              ),
              // ── Content ─────────────────────────────────────────────────
              Expanded(child: _buildBody(context, snapshot)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAiTutor(BuildContext context, ModuleText data) async {
    final api = MatrixScope.of(context).api;
    var courseTitle = data.module.title; // fallback if lookup fails
    try {
      final courses = await api.listCourses();
      final match = courses.where((c) => c.id == data.module.courseId);
      if (match.isNotEmpty) {
        courseTitle = match.first.title;
      }
    } catch (e) {
      debugPrint('[ReaderScreen] Failed to resolve course title: $e');
      // Non-fatal: falls back to module title, chat still works.
    }
    if (!context.mounted) return;
    openAiChatSheet(
      context,
      initialCourse: AiCourse(
        id: data.module.courseId,
        title: courseTitle,
        slug: '',
      ),
      initialModuleId: data.module.id,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ModuleText? data) {
    return AppBar(
      title: Text(
        data?.module.title ?? 'Reader',
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // ── Progress badge ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ValueListenableBuilder<double>(
            valueListenable: _readPercent,
            builder: (context, percent, _) => _ProgressBadge(percent: percent),
          ),
        ),

        // ── Search button ─────────────────────────────────────────────────
        IconButton(
          tooltip: 'Search',
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchOpen
                ? const Icon(Icons.search_off, key: ValueKey('off'))
                : const Icon(Icons.search, key: ValueKey('on')),
          ),
          onPressed: data == null
              ? null
              : () {
                  if (_searchOpen) {
                    _closeSearch();
                  } else {
                    setState(() => _searchOpen = true);
                  }
                },
        ),

        // ── Q&A button ────────────────────────────────────────────────────
        IconButton(
          tooltip: 'Q & A',
          icon: const Icon(Icons.help_outline),
          onPressed: data == null
              ? null
              : () => showQaSheet(context, data.questions),
        ),
        // ── AI Tutor button ──────────────────────────────────────────────
        IconButton(
          tooltip: 'AI Tutor',
          icon: const Icon(Icons.auto_awesome),
          onPressed: data == null ? null : () => _openAiTutor(context, data),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, ModuleText data) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          // ── Text field ─────────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Find in module…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('', data);
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                  if (mounted) _onSearchChanged(v, data);
                });
              },
              onSubmitted: (v) => _stepMatch(1),
            ),
          ),
          const SizedBox(width: 6),

          // ── Match count ────────────────────────────────────────────────
          if (_searchQuery.isNotEmpty)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _totalMatches == 0
                      ? cs.errorContainer
                      : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _totalMatches == 0
                      ? 'No results'
                      : '${_activeMatchIndex + 1} / $_totalMatches',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _totalMatches == 0
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),

          // ── Prev / Next arrows ─────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: 'Previous match',
            onPressed: _totalMatches > 0 ? () => _stepMatch(-1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Next match',
            onPressed: _totalMatches > 0 ? () => _stepMatch(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<ModuleText> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return CenteredError(snapshot.error.toString());
    }
    final data = snapshot.data;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 80),
      children: [
        Text(
          data.module.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (_blocks == null) const Center(child: CircularProgressIndicator()) else
        MatrixTextRenderer.fromBlocks(
          blocks: _blocks!,
          mediaMap: data.mediaMap,
          searchQuery: _searchQuery,
          activeMatchIndex: _activeMatchIndex,
          onBlockKeysReady: (keys) => _blockKeys = keys,
        ),
      ],
    );
  }
}

// ── Progress badge widget ─────────────────────────────────────────────────────

class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (percent * 100).round();
    final isDone = pct >= 100;

    return Tooltip(
      message: isDone ? 'Module complete!' : '$pct% read',
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Circular track
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                strokeWidth: 3.5,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDone ? Colors.green : cs.primary,
                ),
                strokeCap: StrokeCap.round,
              ),
            ),
            // Label
            Text(
              isDone ? '✓' : '$pct%',
              style: TextStyle(
                fontSize: isDone ? 13 : 9,
                fontWeight: FontWeight.w700,
                color: isDone ? Colors.green : cs.onSurface,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal match reference ──────────────────────────────────────────────────

class _MatchRef {
  final int blockIndex;
  final int start;
  final int end;
  _MatchRef(this.blockIndex, this.start, this.end);
}
