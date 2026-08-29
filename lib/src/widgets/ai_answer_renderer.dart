import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'package:matrixf/src/models/models.dart';

import '../components/text_blocks.dart';

/// Renders AI-generated answer text (headings, lists, tables, math, code)
/// using the same block-parsing logic as MatrixTextRenderer, but without
/// search highlighting or its own internal scroll view — designed to sit
/// as a single item inside the chat's own ListView.
class AiAnswerRenderer extends StatelessWidget {
  const AiAnswerRenderer({
    super.key,
    required this.content,
    this.mediaMap = const {},
  });

  final String content;
  final Map<String, ModuleMedia> mediaMap;

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks.map((b) => _renderBlock(context, b)).toList(),
    );
  }

  Widget _renderBlock(BuildContext context, Block b) {
    if (b is HeadingBlock) {
      final style = b.level == 1
          ? Theme.of(context).textTheme.headlineSmall
          : b.level == 2
          ? Theme.of(context).textTheme.titleLarge
          : Theme.of(context).textTheme.titleMedium;
      return Padding(
        padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
        child: _renderInline(context, b.text, style),
      );
    } else if (b is ParagraphBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: _renderInline(
          context,
          b.text,
          Theme.of(context).textTheme.bodyMedium,
        ),
      );
    } else if (b is UlBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: b.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Expanded(
                    child: _renderInline(
                      context,
                      item,
                      Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    } else if (b is OlBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: b.items.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
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
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    } else if (b is QuoteBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.only(left: 12.0),
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
        ),
      );
    } else if (b is CodeBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.all(10.0),
        width: double.infinity,
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
        padding: const EdgeInsets.symmetric(vertical: 10.0),
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
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              columns: b.headers
                  .map(
                    (h) => DataColumn(
                      label: Expanded(
                        child: _renderInline(
                          context,
                          h,
                          const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              rows: b.rows
                  .map(
                    (row) => DataRow(
                      cells: List.generate(b.headers.length, (i) {
                        final cellContent = i < row.length ? row[i] : '';
                        return DataCell(
                          _renderInline(
                            context,
                            cellContent,
                            Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );
    } else if (b is MediaBlock) {
      final path = mediaMap[b.key]?.url;
      if (path == null) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
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
        padding: const EdgeInsets.symmetric(vertical: 10.0),
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

  /// Inline rendering: markdown bold/italic/code + inline math + inline media.
  /// No search-highlight layering (not needed in chat).
  Widget _renderInline(
    BuildContext context,
    String text,
    TextStyle? defaultStyle,
  ) {
    final inlineParts = <InlineSpan>[];
    final splitRegex = RegExp(
      r'(\[(?:IMG|GIF):\s*[^\]]+\]|\$[^$\n]+?\$)',
      caseSensitive: false,
    );

    text.splitMapJoin(
      splitRegex,
      onMatch: (m) {
        final matchText = m.group(0)!;
        final mediaMatch = RegExp(
          r'^\[(?:IMG|GIF):\s*([^\(\)\]]+?)\s*(?:\(([^)]*)\))?\s*\]$',
          caseSensitive: false,
        ).firstMatch(matchText);
        if (mediaMatch != null) {
          final key = mediaMatch.group(1)!.trim();
          final path = mediaMap[key]?.url;
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
        _appendMarkdownInline(inlineParts, n, defaultStyle);
        return '';
      },
    );

    return RichText(text: TextSpan(children: inlineParts));
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
