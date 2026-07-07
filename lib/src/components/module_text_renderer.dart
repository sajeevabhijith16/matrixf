import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'dart:io';
import 'package:matrixf/src/models/models.dart';


abstract class Block {}

class HeadingBlock extends Block {
  final int level;
  final String text;
  HeadingBlock(this.level, this.text);
}

class ParagraphBlock extends Block {
  final String text;
  ParagraphBlock(this.text);
}

class UlBlock extends Block {
  final List<String> items;
  UlBlock(this.items);
}

class OlBlock extends Block {
  final List<String> items;
  OlBlock(this.items);
}

class QuoteBlock extends Block {
  final String text;
  QuoteBlock(this.text);
}

class CodeBlock extends Block {
  final String lang;
  final String text;
  CodeBlock(this.lang, this.text);
}

class MathBlock extends Block {
  final String tex;
  MathBlock(this.tex);
}

class TableBlock extends Block {
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> align;
  TableBlock(this.headers, this.rows, this.align);
}

class MediaBlock extends Block {
  final String key;
  MediaBlock(this.key);
}

bool _isTableSeparator(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('-')) return false;
  return trimmed.replaceAll(RegExp(r'[\s|:\-]'), '').isEmpty;
}

List<String> _splitPipeCells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => c.trim()).toList();
}

List<Block> parseBlocks(String src) {
  final out = <Block>[];
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  int i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // Fenced code
    final fenceMatch = RegExp(r'^```(\w+)?\s*$').firstMatch(line);
    if (fenceMatch != null) {
      final lang = fenceMatch.group(1) ?? '';
      final buf = <String>[];
      i++;
      while (i < lines.length && !RegExp(r'^```\s*$').hasMatch(lines[i])) {
        buf.add(lines[i]);
        i++;
      }
      i++; // closing fence
      out.add(CodeBlock(lang, buf.join('\n')));
      continue;
    }

    // Math block single line
    final mathSingleMatch = RegExp(r'^\s*\$\$(.+)\$\$\s*$').firstMatch(line);
    if (mathSingleMatch != null) {
      out.add(MathBlock(mathSingleMatch.group(1)!.trim()));
      i++;
      continue;
    }
    
    // Math block multi-line
    if (RegExp(r'^\s*\$\$\s*$').hasMatch(line)) {
      final buf = <String>[];
      i++;
      while (i < lines.length && !RegExp(r'^\s*\$\$\s*$').hasMatch(lines[i])) {
        buf.add(lines[i]);
        i++;
      }
      i++; // closing
      out.add(MathBlock(buf.join('\n').trim()));
      continue;
    }

    // Blank
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // Standalone media token => block image
    final mediaMatch = RegExp(r'^\s*\[(?:IMG|GIF):\s*([^\]]+)\]\s*$', caseSensitive: false).firstMatch(line);
    if (mediaMatch != null) {
      out.add(MediaBlock(mediaMatch.group(1)!.trim()));
      i++;
      continue;
    }

    // ASCII box table
    if (RegExp(r'^\s*\+[-+]+\+\s*$').hasMatch(line)) {
      final rows = <List<String>>[];
      i++;
      while (i < lines.length) {
        final l = lines[i];
        if (RegExp(r'^\s*\+[-+]+\+\s*$').hasMatch(l)) { i++; continue; }
        if (RegExp(r'^\s*\|.*\|\s*$').hasMatch(l)) {
          rows.add(_splitPipeCells(l));
          i++;
          continue;
        }
        break;
      }
      if (rows.isNotEmpty) {
        final headers = rows[0];
        final body = rows.sublist(1);
        final align = List.filled(headers.length, 'left');
        out.add(TableBlock(headers, body, align));
        continue;
      }
    }

    // Markdown pipe table
    if (line.contains('|') && i + 1 < lines.length && _isTableSeparator(lines[i + 1])) {
      final headers = _splitPipeCells(line);
      final sepCells = _splitPipeCells(lines[i + 1]);
      final align = sepCells.map((c) {
        final t = c.trim();
        final l = t.startsWith(':');
        final r = t.endsWith(':');
        return l && r ? 'center' : r ? 'right' : 'left';
      }).toList();
      i += 2;
      final body = <List<String>>[];
      while (i < lines.length && lines[i].contains('|') && !_isTableSeparator(lines[i]) && lines[i].trim().isNotEmpty) {
        body.add(_splitPipeCells(lines[i]));
        i++;
      }
      out.add(TableBlock(headers, body, align));
      continue;
    }

    // Heading
    final hMatch = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (hMatch != null) {
      out.add(HeadingBlock(hMatch.group(1)!.length, hMatch.group(2)!));
      i++;
      continue;
    }

    // Quote
    if (RegExp(r'^>\s?').hasMatch(line)) {
      final buf = <String>[];
      while (i < lines.length && RegExp(r'^>\s?').hasMatch(lines[i])) {
        buf.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      out.add(QuoteBlock(buf.join('\n')));
      continue;
    }

    // Unordered list
    if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), ''));
        i++;
      }
      out.add(UlBlock(items));
      continue;
    }

    // Ordered list
    if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
      final items = <String>[];
      while (i < lines.length && RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
        items.add(lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), ''));
        i++;
      }
      out.add(OlBlock(items));
      continue;
    }

    // Paragraph
    final buf = <String>[line];
    i++;
    while (i < lines.length && 
           lines[i].trim().isNotEmpty && 
           !RegExp(r'^(#{1,3}\s|>\s?|```|\s*[-*]\s+|\s*\d+\.\s+)').hasMatch(lines[i]) &&
           !RegExp(r'^\s*\[(?:IMG|GIF):', caseSensitive: false).hasMatch(lines[i]) &&
           !RegExp(r'^\s*\$\$').hasMatch(lines[i]) &&
           !(lines[i].contains('|') && i + 1 < lines.length && _isTableSeparator(lines[i + 1])) &&
           !RegExp(r'^\s*\+[-+]+\+\s*$').hasMatch(lines[i])) {
      buf.add(lines[i]);
      i++;
    }
    out.add(ParagraphBlock(buf.join(' ')));
  }
  return out;
}

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

class MatrixTextRenderer extends StatelessWidget {
  final String content;
  final Map<String, ModuleMedia> mediaMap;

  /// When non-empty, matching text segments are highlighted.
  final String searchQuery;

  /// The index (into the full match list) that is currently active (orange highlight).
  final int activeMatchIndex;

  /// Called once after build with the list of GlobalKeys for each block widget.
  /// The reader screen uses these to scroll to the active match.
  final void Function(List<GlobalKey>)? onBlockKeysReady;

  const MatrixTextRenderer({
    super.key,
    required this.content,
    required this.mediaMap,
    this.searchQuery = '',
    this.activeMatchIndex = -1,
    this.onBlockKeysReady,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(content);
    final matches = _findAllMatches(blocks, searchQuery);

    // Build a GlobalKey for every block so we can scroll to any match.
    final keys = List.generate(blocks.length, (_) => GlobalKey());

    // Notify the parent of the keys after the frame.
    if (onBlockKeysReady != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onBlockKeysReady!(keys);
      });
    }

    // Group matches by block index for quick lookup.
    final matchesByBlock = <int, List<_SearchMatch>>{};
    for (final m in matches) {
      matchesByBlock.putIfAbsent(m.blockIndex, () => []).add(m);
    }

    // Which global match index maps to which block?
    // We'll pass the relevant subset of matches to each block renderer.
    int globalIdx = 0;
    final blockMatchStart = <int, int>{}; // blockIndex -> first global match idx in that block
    for (int bi = 0; bi < blocks.length; bi++) {
      final bm = matchesByBlock[bi];
      if (bm != null && bm.isNotEmpty) {
        blockMatchStart[bi] = globalIdx;
        globalIdx += bm.length;
      }
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final blockMatches = matchesByBlock[index] ?? [];
        final startGlobal = blockMatchStart[index] ?? -1;
        // Which local match (within this block) is active?
        final localActive = (activeMatchIndex >= 0 && startGlobal >= 0)
            ? activeMatchIndex - startGlobal
            : -1;
        return KeyedSubtree(
          key: keys[index],
          child: _renderBlock(
            context,
            blocks[index],
            blockMatches,
            localActive,
          ),
        );
      },
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
        child: _renderInline(context, b.text, style, blockMatches, localActiveMatch),
      );
    } else if (b is ParagraphBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _renderInline(context, b.text, Theme.of(context).textTheme.bodyMedium, blockMatches, localActiveMatch),
      );
    } else if (b is UlBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: b.items.asMap().entries.map((entry) {
            // For list items, find matches that fall within this item's text range.
            final offset = b.items.take(entry.key).fold(0, (s, t) => s + t.length + 1);
            final itemMatches = blockMatches
                .where((m) => m.start >= offset && m.end <= offset + entry.value.length)
                .map((m) => _SearchMatch(m.blockIndex, m.start - offset, m.end - offset))
                .toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Expanded(child: _renderInline(context, entry.value, Theme.of(context).textTheme.bodyMedium, itemMatches, localActiveMatch)),
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
            final offset = b.items.take(entry.key).fold(0, (s, t) => s + t.length + 1);
            final itemMatches = blockMatches
                .where((m) => m.start >= offset && m.end <= offset + entry.value.length)
                .map((m) => _SearchMatch(m.blockIndex, m.start - offset, m.end - offset))
                .toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.key + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: _renderInline(context, entry.value, Theme.of(context).textTheme.bodyMedium, itemMatches, localActiveMatch)),
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
          border: Border(left: BorderSide(color: Colors.grey.shade400, width: 4)),
        ),
        child: _renderInline(context, b.text, Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.grey.shade700,
        ), blockMatches, localActiveMatch),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              columns: b.headers.map((h) => DataColumn(label: Expanded(child: _renderInline(context, h, const TextStyle(fontWeight: FontWeight.bold), [], -1)))).toList(),
              rows: b.rows.map((row) => DataRow(
                cells: List.generate(b.headers.length, (i) {
                  final cellContent = i < row.length ? row[i] : '';
                  return DataCell(_renderInline(context, cellContent, Theme.of(context).textTheme.bodyMedium, [], -1));
                }),
              )).toList(),
            ),
          ),
        ),
      );
    } else if (b is MediaBlock) {
      final path = mediaMap[b.key]?.url;
      if (path == null) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text('Missing media: ${b.key}', style: const TextStyle(color: Colors.red)),
        );
      }
      final isNetwork = path.startsWith('http://') || path.startsWith('https://');
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
    text.splitMapJoin(splitRegex,
      onMatch: (m) {
        cursor += m.group(0)!.length;
        final matchText = m.group(0)!;
        final mediaMatch = RegExp(r'^\[(?:IMG|GIF):\s*([^\]]+)\]$', caseSensitive: false).firstMatch(matchText);
        if (mediaMatch != null) {
          final key = mediaMatch.group(1)!.trim();
          final path = mediaMap[key]?.url;
          if (path == null) {
            inlineParts.add(TextSpan(text: '[missing: $key]', style: const TextStyle(color: Colors.red)));
          } else {
            final isNetwork = path.startsWith('http://') || path.startsWith('https://');
            inlineParts.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: isNetwork 
                    ? Image.network(path, height: 24)
                    : Image.file(File(path), height: 24),
              ),
            ));
          }
        } else {
          final mathMatch = RegExp(r'^\$([^$\n]+?)\$$').firstMatch(matchText);
          if (mathMatch != null) {
            inlineParts.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                mathMatch.group(1)!,
                textStyle: defaultStyle,
              ),
            ));
          }
        }
        return '';
      },
      onNonMatch: (n) {
        // Apply search highlight layering on this plain-text segment.
        // We need to know where in `text` this segment starts.
        final segStart = text.length - n.length - (text.length - cursor - n.length);
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
      }
    );

    return RichText(
      text: TextSpan(children: inlineParts),
    );
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
      final oEnd   = (m.end   - segStart).clamp(0, segment.length);
      if (oEnd > oStart) {
        highlights.add((oStart, oEnd, mi == localActiveMatch));
      }
    }

    if (highlights.isEmpty) {
      // No search highlights — just do markdown inline.
      _appendMarkdownInline(out, segment, defaultStyle);
      return;
    }

    // Sort highlights by start.
    highlights.sort((a, b) => a.$1.compareTo(b.$1));

    int pos = 0;
    for (final (hStart, hEnd, isActive) in highlights) {
      if (pos < hStart) {
        _appendMarkdownInline(out, segment.substring(pos, hStart), defaultStyle);
      }
      final hiStyle = defaultStyle?.copyWith(
        backgroundColor: isActive ? Colors.orange.shade300 : Colors.yellow.shade300,
        color: Colors.black,
      ) ?? TextStyle(
        backgroundColor: isActive ? Colors.orange.shade300 : Colors.yellow.shade300,
        color: Colors.black,
      );
      out.add(TextSpan(text: segment.substring(hStart, hEnd), style: hiStyle));
      pos = hEnd;
    }
    if (pos < segment.length) {
      _appendMarkdownInline(out, segment.substring(pos), defaultStyle);
    }
  }

  void _appendMarkdownInline(List<InlineSpan> out, String text, TextStyle? defaultStyle) {
    var remaining = text;
    while (remaining.isNotEmpty) {
      final mdMatch = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)').firstMatch(remaining);
      if (mdMatch == null) {
        out.add(TextSpan(text: remaining, style: defaultStyle));
        break;
      }
      if (mdMatch.start > 0) {
        out.add(TextSpan(text: remaining.substring(0, mdMatch.start), style: defaultStyle));
      }
      final tok = mdMatch.group(0)!;
      if (tok.startsWith('**')) {
        out.add(TextSpan(text: tok.substring(2, tok.length - 2), style: defaultStyle?.copyWith(fontWeight: FontWeight.bold)));
      } else if (tok.startsWith('`')) {
        out.add(TextSpan(text: tok.substring(1, tok.length - 1), style: defaultStyle?.copyWith(fontFamily: 'monospace', backgroundColor: Colors.grey.shade200)));
      } else {
        out.add(TextSpan(text: tok.substring(1, tok.length - 1), style: defaultStyle?.copyWith(fontStyle: FontStyle.italic)));
      }
      remaining = remaining.substring(mdMatch.end);
    }
  }
}
