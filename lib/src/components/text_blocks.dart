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

bool isTableSeparator(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('-')) return false;
  return trimmed.replaceAll(RegExp(r'[\s|:\-]'), '').isEmpty;
}

List<String> splitPipeCells(String line) {
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
    final mediaMatch = RegExp(
      r'^\s*\[(?:IMG|GIF):\s*([^\]]+)\]\s*$',
      caseSensitive: false,
    ).firstMatch(line);
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
        if (RegExp(r'^\s*\+[-+]+\+\s*$').hasMatch(l)) {
          i++;
          continue;
        }
        if (RegExp(r'^\s*\|.*\|\s*$').hasMatch(l)) {
          rows.add(splitPipeCells(l));
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
    if (line.contains('|') &&
        i + 1 < lines.length &&
        isTableSeparator(lines[i + 1])) {
      final headers = splitPipeCells(line);
      final sepCells = splitPipeCells(lines[i + 1]);
      final align = sepCells.map((c) {
        final t = c.trim();
        final l = t.startsWith(':');
        final r = t.endsWith(':');
        return l && r
            ? 'center'
            : r
            ? 'right'
            : 'left';
      }).toList();
      i += 2;
      final body = <List<String>>[];
      while (i < lines.length &&
          lines[i].contains('|') &&
          !isTableSeparator(lines[i]) &&
          lines[i].trim().isNotEmpty) {
        body.add(splitPipeCells(lines[i]));
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
        !RegExp(
          r'^(#{1,3}\s|>\s?|```|\s*[-*]\s+|\s*\d+\.\s+)',
        ).hasMatch(lines[i]) &&
        !RegExp(
          r'^\s*\[(?:IMG|GIF):',
          caseSensitive: false,
        ).hasMatch(lines[i]) &&
        !RegExp(r'^\s*\$\$').hasMatch(lines[i]) &&
        !(lines[i].contains('|') &&
            i + 1 < lines.length &&
            isTableSeparator(lines[i + 1])) &&
        !RegExp(r'^\s*\+[-+]+\+\s*$').hasMatch(lines[i])) {
      buf.add(lines[i]);
      i++;
    }
    out.add(ParagraphBlock(buf.join(' ')));
  }
  return out;
}

/// Scans [content] for [IMG: key] / [GIF: key] tokens (both standalone-line
/// and inline forms) and returns the unique set of keys referenced.
/// Used to find which course images are relevant to offer the AI as
/// available media for a given course's chat context.
Set<String> extractMediaKeys(String content) {
  final regex = RegExp(r'\[(?:IMG|GIF):\s*([^\]]+)\]', caseSensitive: false);
  final keys = <String>{};
  for (final match in regex.allMatches(content)) {
    final key = match.group(1)?.trim();
    if (key != null && key.isNotEmpty) keys.add(key);
  }
  return keys;
}
