import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:matrixf/src/app.dart';
import 'package:matrixf/src/screens/admin_screen.dart';
import 'package:matrixf/src/api.dart';
import 'package:matrixf/src/models/models.dart';

void main() {
  testWidgets('Test Admin Screen Push', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      print('FLUTTER_ERROR: ${details.exceptionAsString()}');
      print('STACK: ${details.stack}');
    };

    try {
      final api = matrixApi;
      // We mock a profile that is admin
      final profile = Profile(id: '1', isAdmin: true);
      
      await tester.pumpWidget(MatrixScope(
        api: api,
        profile: profile,
        refreshProfile: () async {},
        setTab: (t) {},
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: AdminScreen(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Open admin console'),
                ),
              );
            },
          ),
        ),
      ));
      
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open admin console'));
      await tester.pumpAndSettle();
    } catch (e) {
      print('PUMP_ERROR: $e');
    }
  });
}
