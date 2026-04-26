import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_logger_mobile/screens/main_navigation.dart';

void main() {
  testWidgets('Main navigation loads successfully', (WidgetTester tester) async {
    /// Test that the main navigation screen loads without crashing.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
        ),
        home: const MainNavigation(),
      ),
    );

    /// Verify that the MainNavigation widget is built successfully.
    expect(find.byType(MainNavigation), findsOneWidget);
  });

  testWidgets('Material app theme is configured correctly', (WidgetTester tester) async {
    /// Test that the MaterialApp is configured with the correct theme.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
        ),
        home: const MainNavigation(),
      ),
    );

    /// Verify that Material3 design system is enabled.
    final ThemeData theme = Theme.of(tester.element(find.byType(MainNavigation)));
    expect(theme.useMaterial3, true);
  });
}
