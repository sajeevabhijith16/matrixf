import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:matrixf/src/api.dart';
import 'package:matrixf/src/app.dart';

void main() {
  testWidgets('Matrix app renders the mobile shell', (tester) async {
    await tester.pumpWidget(
      MatrixScope(
        api: matrixApi,
        profile: null,
        refreshProfile: () async {},
        setTab: (_) {},
        child: const MaterialApp(
          home: MatrixShell(tab: 3, onTabChanged: _noop, profile: null),
        ),
      ),
    );

    expect(find.text('Matrix'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}

void _noop(int _) {}
