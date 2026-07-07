import 'dart:io';

void main() {
  void addImport(String filePath, String imp) {
    final file = File(filePath);
    if (!file.existsSync()) return;
    var content = file.readAsStringSync();
    if (!content.contains(imp)) {
      content = content.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n\$imp");
      file.writeAsStringSync(content);
    }
  }

  void addKeys(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return;
    var content = file.readAsStringSync();
    content = content.replaceAllMapped(RegExp(r'class ([A-Za-z0-9_]+) extends StatelessWidget \{\s*const \1\(\{'), (m) => 'class \${m[1]} extends StatelessWidget {\n  const \${m[1]}({super.key, ');
    file.writeAsStringSync(content);
  }

  addImport('lib/src/widgets/shared_widgets.dart', "import '../screens/course_detail_screen.dart';");
  addImport('lib/src/widgets/shared_widgets.dart', "import '../screens/reader_screen.dart';");
  addImport('lib/src/widgets/shared_widgets.dart', "import '../screens/admin_screen.dart';");
  
  addKeys('lib/src/widgets/shared_widgets.dart');

  print('Imports and keys fixed.');
}
