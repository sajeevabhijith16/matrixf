import 'package:flutter_test/flutter_test.dart';
import 'package:matrixf/src/components/text_blocks.dart';
import 'package:matrixf/src/models/pending_image_token.dart';

void main() {
  group('Module I1 - Core Parsing (Inline Image Descriptions)', () {
    test('extractMediaTokensWithDescriptions correctly parses tokens and inline descriptions', () {
      final content = 'Text [IMG: fig1] more text\n'
          '[IMG: fig2(Diagram showing current flow)]\n'
          'Inline [GIF: anim3(A short looping animation)] here\n'
          '[IMG:  fig1(duplicate, should be ignored)  ]';

      final result = extractMediaTokensWithDescriptions(content);

      expect(result, {
        'fig1': null,
        'fig2': 'Diagram showing current flow',
        'anim3': 'A short looping animation',
      });
    });

    test('parseBlocks creates MediaBlock with key and description for standalone tokens', () {
      final blocks = parseBlocks(
        '[IMG: fig2(A diagram)]\n'
        '[IMG: fig1]\n',
      );

      expect(blocks.length, 2);
      expect(blocks[0], isA<MediaBlock>());
      final b0 = blocks[0] as MediaBlock;
      expect(b0.key, 'fig2');
      expect(b0.description, 'A diagram');

      expect(blocks[1], isA<MediaBlock>());
      final b1 = blocks[1] as MediaBlock;
      expect(b1.key, 'fig1');
      expect(b1.description, null);
    });

    test('extractMediaKeys remains backward compatible', () {
      final content = '[IMG: fig1] text [IMG: fig2(description)]';
      final keys = extractMediaKeys(content);
      expect(keys, {'fig1', 'fig2'});
    });
  });

  group('Module I3 - PendingImageToken with inline description', () {
    test('PendingImageToken stores inlineDescription correctly', () {
      const token = PendingImageToken(
        token: 'fig2',
        moduleId: 'm1',
        moduleTitle: 'Mod 1',
        courseId: 'c1',
        courseTitle: 'Course 1',
        inlineDescription: 'Diagram showing flow',
      );

      expect(token.token, 'fig2');
      expect(token.inlineDescription, 'Diagram showing flow');
    });
  });
}
