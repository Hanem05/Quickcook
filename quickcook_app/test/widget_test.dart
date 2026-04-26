// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quickcook_app/theme/theme_notifier.dart';

void main() {
  testWidgets('ThemeNotifier is available to widget tree', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final mode = context.watch<ThemeNotifier>().mode;
              return Scaffold(body: Text(mode.name));
            },
          ),
        ),
      ),
    );

    expect(find.text('light'), findsOneWidget);
  });
}
