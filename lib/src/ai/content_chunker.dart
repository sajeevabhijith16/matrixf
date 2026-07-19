/// Splits raw course content into chunks suitable for embedding, without
/// breaking apart fenced code blocks or $$ math blocks, and without
/// reformatting the original text — each chunk keeps its original
/// markdown/LaTeX syntax intact.
List<String> chunkCourseContent(String content, {int maxChunkChars = 1000}) {
  final segments = _splitIntoSegments(content);
  final chunks = <String>[];
  final current = StringBuffer();

  for (final seg in segments) {
    final trimmedSeg = seg.trim();
    if (trimmedSeg.isEmpty) continue;

    if (current.isNotEmpty &&
        current.length + trimmedSeg.length + 2 > maxChunkChars) {
      chunks.add(current.toString().trim());
      current.clear();
    }
    if (current.isNotEmpty) current.write('\n\n');
    current.write(trimmedSeg);
  }
  if (current.isNotEmpty) chunks.add(current.toString().trim());
  return chunks;
}

/// Splits [content] into paragraph-like segments on blank lines, EXCEPT
/// while inside a ``` fenced block or a $$ math block, where blank lines
/// (if any) do not count as a split point.
List<String> _splitIntoSegments(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final segments = <String>[];
  final buf = StringBuffer();
  bool inFence = false;
  bool inMath = false;

  void flush() {
    if (buf.isNotEmpty) {
      segments.add(buf.toString());
      buf.clear();
    }
  }

  for (final line in lines) {
    final isFenceLine = RegExp(r'^```').hasMatch(line.trim());
    final isMathLine = RegExp(r'^\$\$').hasMatch(line.trim());

    if (isFenceLine) {
      buf.writeln(line);
      inFence = !inFence;
      continue;
    }
    if (isMathLine && !inFence) {
      buf.writeln(line);
      inMath = !inMath;
      continue;
    }

    if (line.trim().isEmpty && !inFence && !inMath) {
      flush();
      continue;
    }

    buf.writeln(line);
  }
  flush();
  return segments;
}
