import 'dart:io';

void main() {
  final file = File('lib/src/app.dart');
  final lines = file.readAsLinesSync();

  String getSlice(int startPatternIndex, int endPatternIndex) {
    return lines.sublist(startPatternIndex, endPatternIndex).join('\n');
  }

  // Find boundaries
  int indexOf(String pattern) => lines.indexWhere((l) => l.contains(pattern));
  
  final homeIdx = indexOf('// ─── Home Screen');
  final catalogIdx = indexOf('// ─── Catalog Screen');
  final courseDetailIdx = indexOf('// ─── Course Detail Screen');
  final readerIdx = indexOf('// ─── Reader Screen');
  final libraryIdx = indexOf('// ─── Library Screen');
  final supportIdx = indexOf('// ─── Support Screen');
  final profileIdx = indexOf('// ─── Profile Screen');
  final adminIdx = indexOf('// ─── Admin Screen');
  final richTextIdx = indexOf('// ─── Rich Text Renderer');

  final commonImports = '''
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';
''';

  // 1. Screens
  Directory('lib/src/screens').createSync(recursive: true);
  
  File('lib/src/screens/home_screen.dart').writeAsStringSync('$commonImports\nimport "course_detail_screen.dart";\n${getSlice(homeIdx, catalogIdx)}');
  File('lib/src/screens/catalog_screen.dart').writeAsStringSync('$commonImports\nimport "course_detail_screen.dart";\n${getSlice(catalogIdx, courseDetailIdx)}');
  File('lib/src/screens/course_detail_screen.dart').writeAsStringSync('$commonImports\nimport "reader_screen.dart";\n${getSlice(courseDetailIdx, readerIdx)}');
  File('lib/src/screens/reader_screen.dart').writeAsStringSync('$commonImports\nimport "../components/module_text_renderer.dart";\n${getSlice(readerIdx, libraryIdx)}');
  File('lib/src/screens/library_screen.dart').writeAsStringSync('$commonImports\nimport "course_detail_screen.dart";\nimport "reader_screen.dart";\n${getSlice(libraryIdx, supportIdx)}');
  File('lib/src/screens/support_screen.dart').writeAsStringSync(commonImports + getSlice(supportIdx, profileIdx));
  File('lib/src/screens/profile_screen.dart').writeAsStringSync('$commonImports\nimport "admin_screen.dart";\n${getSlice(profileIdx, adminIdx)}');
  File('lib/src/screens/admin_screen.dart').writeAsStringSync(commonImports + getSlice(adminIdx, richTextIdx));

  // 2. Widgets
  Directory('lib/src/widgets').createSync(recursive: true);
  File('lib/src/widgets/shared_widgets.dart').writeAsStringSync(commonImports + getSlice(richTextIdx, lines.length));

  // 3. App Shell
  final shellImports = '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'models/models.dart';
import 'screens/home_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/library_screen.dart';
import 'screens/support_screen.dart';
import 'screens/profile_screen.dart';
''';
  File('lib/src/app.dart').writeAsStringSync('$shellImports\n${getSlice(lines.indexWhere((l) => l.contains('// ─── App Shell')), homeIdx)}');

  print('Splitting completed.');
}
