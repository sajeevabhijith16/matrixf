import 'dart:io';

void main() {
  final dir = Directory('lib/src');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  final renames = {
    '_BrandHeader': 'BrandHeader',
    '_EmptyBox': 'EmptyBox',
    '_ErrorBox': 'ErrorBox',
    '_CenteredError': 'CenteredError',
    '_LoadingList': 'LoadingList',
    '_SignInPrompt': 'SignInPrompt',
    '_TrustTile': 'TrustTile',
    '_SectionTitle': 'SectionTitle',
    '_InfoRow': 'InfoRow',
    '_showSnack': 'showSnack',
    '_openCourse': 'openCourse',
    '_showQaSheet': 'showQaSheet',
    '_showCourseEditor': 'showCourseEditor',
    '_showModuleEditor': 'showModuleEditor',
  };

  for (final file in files) {
    if (file.path.contains('split_app.dart') || file.path.contains('rename_widgets.dart')) continue;
    
    var content = file.readAsStringSync();
    var originalContent = content;
    
    for (final entry in renames.entries) {
      content = content.replaceAll(entry.key, entry.value);
    }
    
    if (content != originalContent) {
      file.writeAsStringSync(content);
      print('Updated \${file.path}');
    }
  }

  // Also fix test.dart
  final testFile = File('test.dart');
  if (testFile.existsSync()) {
    var content = testFile.readAsStringSync();
    if (!content.contains("import 'package:matrixf/src/screens/admin_screen.dart';")) {
      content = content.replaceFirst("import 'package:matrixf/src/app.dart';", "import 'package:matrixf/src/app.dart';\nimport 'package:matrixf/src/screens/admin_screen.dart';");
      testFile.writeAsStringSync(content);
    }
  }

  print('Renaming completed.');
}
