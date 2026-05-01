import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickcook_app/widgets/app_message.dart';

void main() {
  testWidgets('shows snack bar with retry action', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                AppMessage.show(
                  context,
                  text: 'Load failed',
                  type: AppMessageType.error,
                  actionLabel: 'Retry',
                  onAction: () => tapped = true,
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Load failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
