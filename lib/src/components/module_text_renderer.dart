import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'dart:io';
export 'text_blocks.dart';
import 'text_blocks.dart';

// ── Search match model ────────────────────────────────────────────────────────

/// A single text match within a block.
class _SearchMatch {
  final int blockIndex;
  final int start;
  final int end;
  _SearchMatch(this.blockIndex, this.start, this.end);
}

/// Extracts the searchable plain text from a block (headings, paragraphs, lists, etc.)
String _blockPlainText(Block b) {
  if (b is HeadingBlock) return b.text;
  if (b is ParagraphBlock) return b.text;
  if (b is QuoteBlock) return b.text;
  if (b is CodeBlock) return b.text;
  if (b is UlBlock) return b.items.join(' ');
  if (b is OlBlock) return b.items.join(' ');
  return '';
}

/// Returns all match positions across all blocks for [query].
List<_SearchMatch> _findAllMatches(List<Block> blocks, String query) {
  if (query.isEmpty) return [];
  final q = query.toLowerCase();
  final matches = <_SearchMatch>[];
  for (int i = 0; i < blocks.length; i++) {
    final text = _blockPlainText(blocks[i]).toLowerCase();
    int start = 0;
    while (true) {
      final idx = text.indexOf(q, start);
      if (idx == -1) break;
      matches.add(_SearchMatch(i, idx, idx + q.length));
      start = idx + 1;
    }
  }
  return matches;
}

// ─── MatrixTextRenderer ───────────────────────────────────────────────────────

class MatrixTextRenderer extends StatefulWidget {
  const MatrixTextRenderer.fromBlocks({
    super.key,
    required List<Block> blocks,
    required this.mediaMap,
    required this.searchQuery,
    required this.activeMatchIndex,
    required this.onBlockKeysReady,
  })  : blocks = blocks,
        content = null;

  const MatrixTextRenderer.fromContent({
    super.key,
    required String content,
    required this.mediaMap,
    this.searchQuery = '',
    this.activeMatchIndex = -1,
    this.onBlockKeysReady,
  })  : content = content,
        blocks = null;

  final List<Block>? blocks;
  final String? content;
  final Map<String, dynamic> mediaMap;
  final String searchQuery;
  final int activeMatchIndex;
  final ValueChanged<List<GlobalKey>>? onBlockKeysReady;

  @override
  State<MatrixTextRenderer> createState() => _MatrixTextRendererState();
}

class _MatrixTextRendererState extends State<MatrixTextRenderer> {
  late List<Block> _resolvedBlocks;
  List<GlobalKey> _blockKeys = [];
  List<_SearchMatch> _matches = [];

  @override
  void initState() {
    super.initState();
    _resolvedBlocks = widget.blocks ?? parseBlocks(widget.content!);
    _blockKeys = List.generate(_resolvedBlocks.length, (_) => GlobalKey());
    _recomputeMatches();
  }

  @override
  void didUpdateWidget(covariant MatrixTextRenderer old) {
    super.didUpdateWidget(old);
    final blocksChanged = widget.blocks != null
        ? !identical(widget.blocks, old.blocks)
        : widget.content != old.content;
    if (blocksChanged) {
      _resolvedBlocks = widget.blocks ?? parseBlocks(widget.content!);
      _blockKeys = List.generate(_resolvedBlocks.length, (_) => GlobalKey());
      _recomputeMatches();
    } else if (widget.searchQuery != old.searchQuery) {
      _recomputeMatches();
    }
  }

  void _recomputeMatches() {
    _matches = _findAllMatches(_resolvedBlocks, widget.searchQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBlockKeysReady?.call(_blockKeys);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group matches by block index for quick lookup.
    final matchesByBlock = <int, List<_SearchMatch>>{};
    for (final m in _matches) {
      matchesByBlock.putIfAbsent(m.blockIndex, () => []).add(m);
    }

    // Which global match index maps to which block?
    // We'll pass the relevant subset of matches to each block renderer.
    int globalIdx = 0;
    final blockMatchStart = <int, int>{}; // blockIndex -> first global match idx in that block
    for (int bi = 0; bi < _resolvedBlocks.length; bi++) {
      final bm = matchesByBlock[bi];
      if (bm != null && bm.isNotEmpty) {
        blockMatchStart[bi] = globalIdx;
        globalIdx += bm.length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_resolvedBlocks.length, (index) {
        final blockMatches = matchesByBlock[index] ?? [];
        final startGlobal = blockMatchStart[index] ?? -1;
        // Which local match (within this block) is active?
        final localActive = (widget.activeMatchIndex >= 0 && startGlobal >= 0)
            ? widget.activeMatchIndex - startGlobal
            : -1;
        return KeyedSubtree(
          key: _blockKeys[index],
          child: _renderBlock(
            context,
            _resolvedBlocks[index],
            blockMatches,
            localActive,
          ),
        );
      }),
    );
  }

  Widget _renderBlock(
    BuildContext context,
    Block b,
    List<_SearchMatch> blockMatches,
    int localActiveMatch,
  ) {
    if (b is HeadingBlock) {
      final style = b.level == 1
          ? Theme.of(context).textTheme.headlineMedium
          : b.level == 2
          ? Theme.of(context).textTheme.headlineSmall
          : Theme.of(context).textTheme.titleLarge;
      return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: _renderInline(
          context,
          b.text,
          style,
          blockMatches,
          localActiveMatch,
        ),
      );
    } else if (b is ParagraphBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _renderInline(
          context,
          b.text,
          Theme.of(context).textTheme.bodyMedium,
          blockMatches,
          localActiveMatch,
        ),
      );
    } else if (b is UlBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: b.items.asMap().entries.map((entry) {
            // For list items, find matches that fall within this item's text range.
            final offset = b.items
                .take(entry.key)
                .fold(0, (s, t) => s + t.length + 1);
            final itemMatches = blockMatches
                .where(
                  (m) =>
                      m.start >= offset && m.end <= offset + entry.value.length,
                )
                .map(
                  (m) => _SearchMatch(
                    m.blockIndex,
                    m.start - offset,
                    m.end - offset,
                  ),
                )
                .toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Expanded(
                  child: _renderInline(
                    context,
                    entry.value,
                    Theme.of(context).textTheme.bodyMedium,
                    itemMatches,
                    localActiveMatch,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
    } else if (b is OlBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: b.items.asMap().entries.map((entry) {
            final offset = b.items
                .take(entry.key)
                .fold(0, (s, t) => s + t.length + 1);
            final itemMatches = blockMatches
                .where(
                  (m) =>
                      m.start >= offset && m.end <= offset + entry.value.length,
                )
                .map(
                  (m) => _SearchMatch(
                    m.blockIndex,
                    m.start - offset,
                    m.end - offset,
                  ),
                )
                .toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key + 1}. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: _renderInline(
                    context,
                    entry.value,
                    Theme.of(context).textTheme.bodyMedium,
                    itemMatches,
                    localActiveMatch,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
    } else if (b is QuoteBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.only(left: 16.0),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.grey.shade400, width: 4),
          ),
        ),
        child: _renderInline(
          context,
          b.text,
          Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: Colors.grey.shade700,
          ),
          blockMatches,
          localActiveMatch,
        ),
      );
    } else if (b is CodeBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            b.text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    } else if (b is MathBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              b.tex,
              mathStyle: MathStyle.display,
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    } else if (b is TableBlock) {
      // ── Custom table via Column+Row+Expanded ─────────────────────────────
      // We deliberately avoid Flutter's Table widget and IntrinsicColumnWidth
      // because IntrinsicColumnWidth calls getMaxIntrinsicWidth() on every
      // cell child. When a cell contains a Math.tex WidgetSpan, that call
      // propagates into flutter_math_fork which uses LayoutBuilder internally,
      // triggering "LayoutBuilder does not support returning intrinsic
      // dimensions". Using Row+Expanded instead distributes width
      // proportionally without ever querying intrinsic dimensions.
      final bodyStyle = Theme.of(context).textTheme.bodyMedium;
      final boldStyle = bodyStyle?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontWeight: FontWeight.bold);
      final borderColor = Colors.grey.shade300;
      final int colCount = b.headers.length;

      Widget buildCell(
        String text,
        TextStyle? style, {
        bool isHeader = false,
        bool isLastCol = false,
        bool isLastRow = false,
      }) {
        return Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isHeader ? Colors.grey.shade100 : null,
              border: Border(
                right: isLastCol
                    ? BorderSide.none
                    : BorderSide(color: borderColor),
                bottom: isLastRow
                    ? BorderSide.none
                    : BorderSide(color: borderColor),
              ),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 12.0, vertical: 10.0),
            child: _renderInline(context, text, style, [], -1),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(colCount, (i) {
                  return buildCell(
                    b.headers[i],
                    boldStyle,
                    isHeader: true,
                    isLastCol: i == colCount - 1,
                  );
                }),
              ),
              // Data rows
              ...List.generate(b.rows.length, (ri) {
                final row = b.rows[ri];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(colCount, (ci) {
                    return buildCell(
                      ci < row.length ? row[ci] : '',
                      bodyStyle,
                      isLastCol: ci == colCount - 1,
                      isLastRow: ri == b.rows.length - 1,
                    );
                  }),
                );
              }),
            ],
          ),
        ),
      );
    } else if (b is MediaBlock) {
      final path = widget.mediaMap[b.key]?.url;
      if (path == null) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(
              color: Colors.grey.shade300,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text(
            'Missing media: ${b.key}',
            style: const TextStyle(color: Colors.red),
          ),
        );
      }
      final isNetwork =
          path.startsWith('http://') || path.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: isNetwork
              ? Image.network(path, fit: BoxFit.contain)
              : Image.file(File(path), fit: BoxFit.contain),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _renderInline(
    BuildContext context,
    String text,
    TextStyle? defaultStyle, [
    List<_SearchMatch> blockMatches = const [],
    int localActiveMatch = -1,
  ]) {
    final inlineParts = <InlineSpan>[];

    // Split on inline media and math
    final splitRegex = RegExp(
      r'(\[(?:IMG|GIF):\s*[^\]]+\]|\$[^$\n]+?\$)',
      caseSensitive: false,
    );

    // We'll first expand inline-media/math, collecting plain-text segments
    // with their positions relative to the raw `text`, then layer the
    // search highlights on top of those plain-text segments.

    // Build a flat list of (start, end, span) after handling inline tokens.
    // For simplicity with search: apply search highlights only to plain-text
    // portions (not inside math/media tokens).

    int cursor = 0;
    text.splitMapJoin(
      splitRegex,
      onMatch: (m) {
        cursor += m.group(0)!.length;
        final matchText = m.group(0)!;
        final mediaMatch = RegExp(
          r'^\[(?:IMG|GIF):\s*([^\(\)\]]+?)\s*(?:\(([^)]*)\))?\s*\]$',
          caseSensitive: false,
        ).firstMatch(matchText);
        if (mediaMatch != null) {
          final key = mediaMatch.group(1)!.trim();
          final path = widget.mediaMap[key]?.url;
          if (path == null) {
            inlineParts.add(
              TextSpan(
                text: '[missing: $key]',
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else {
            final isNetwork =
                path.startsWith('http://') || path.startsWith('https://');
            inlineParts.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: isNetwork
                      ? Image.network(path, height: 24)
                      : Image.file(File(path), height: 24),
                ),
              ),
            );
          }
        } else {
          final mathMatch = RegExp(r'^\$([^$\n]+?)\$$').firstMatch(matchText);
          if (mathMatch != null) {
            inlineParts.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Math.tex(mathMatch.group(1)!, textStyle: defaultStyle),
              ),
            );
          }
        }
        return '';
      },
      onNonMatch: (n) {
        // Apply search highlight layering on this plain-text segment.
        // We need to know where in `text` this segment starts.
        final segStart =
            text.length - n.length - (text.length - cursor - n.length);
        _appendHighlightedSegment(
          inlineParts,
          n,
          segStart,
          defaultStyle,
          blockMatches,
          localActiveMatch,
        );
        cursor += n.length;
        return '';
      },
    );

    return Text.rich(TextSpan(children: inlineParts));
  }

  /// Appends [InlineSpan]s for the text [segment] (at [segStart] within the
  /// full block text), applying markdown bold/italic/code formatting AND
  /// search-match highlights.
  void _appendHighlightedSegment(
    List<InlineSpan> out,
    String segment,
    int segStart,
    TextStyle? defaultStyle,
    List<_SearchMatch> blockMatches,
    int localActiveMatch,
  ) {
    if (segment.isEmpty) return;

    // Collect all character ranges that are inside a search match.
    // Each entry: (start, end, isActive).
    final highlights = <(int, int, bool)>[];
    for (int mi = 0; mi < blockMatches.length; mi++) {
      final m = blockMatches[mi];
      // m.start/end are relative to full block plain text.
      // We need to find the overlap with [segStart, segStart+segment.length).
      final oStart = (m.start - segStart).clamp(0, segment.length);
      final oEnd = (m.end - segStart).clamp(0, segment.length);
      if (oEnd > oStart) {
        highlights.add((oStart, oEnd, mi == localActiveMatch));
      }
    }

    if (highlights.isEmpty) {
      // No search highlights â€” just do markdown inline.
      _appendMarkdownInline(out, segment, defaultStyle);
      return;
    }

    // Sort highlights by start.
    highlights.sort((a, b) => a.$1.compareTo(b.$1));

    int pos = 0;
    for (final (hStart, hEnd, isActive) in highlights) {
      if (pos < hStart) {
        _appendMarkdownInline(
          out,
          segment.substring(pos, hStart),
          defaultStyle,
        );
      }
      final hiStyle =
          defaultStyle?.copyWith(
            backgroundColor: isActive
                ? Colors.orange.shade300
                : Colors.yellow.shade300,
            color: Colors.black,
          ) ??
          TextStyle(
            backgroundColor: isActive
                ? Colors.orange.shade300
                : Colors.yellow.shade300,
            color: Colors.black,
          );
      out.add(TextSpan(text: segment.substring(hStart, hEnd), style: hiStyle));
      pos = hEnd;
    }
    if (pos < segment.length) {
      _appendMarkdownInline(out, segment.substring(pos), defaultStyle);
    }
  }

  void _appendMarkdownInline(
    List<InlineSpan> out,
    String text,
    TextStyle? defaultStyle,
  ) {
    var remaining = text;
    while (remaining.isNotEmpty) {
      final mdMatch = RegExp(
        r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)',
      ).firstMatch(remaining);
      if (mdMatch == null) {
        out.add(TextSpan(text: remaining, style: defaultStyle));
        break;
      }
      if (mdMatch.start > 0) {
        out.add(
          TextSpan(
            text: remaining.substring(0, mdMatch.start),
            style: defaultStyle,
          ),
        );
      }
      final tok = mdMatch.group(0)!;
      if (tok.startsWith('**')) {
        out.add(
          TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: defaultStyle?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (tok.startsWith('`')) {
        out.add(
          TextSpan(
            text: tok.substring(1, tok.length - 1),
            style: defaultStyle?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        );
      } else {
        out.add(
          TextSpan(
            text: tok.substring(1, tok.length - 1),
            style: defaultStyle?.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      remaining = remaining.substring(mdMatch.end);
    }
  }
}
