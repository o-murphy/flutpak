import 'package:flutter_test/flutter_test.dart';

import 'package:demo_app/main.dart';

void main() {
  testWidgets('renders sqlite version and rhttp status',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(sqliteVersion: '3.49.0'));
    expect(find.text('SQLite: 3.49.0'), findsOneWidget);
    expect(find.text('rhttp: ready'), findsOneWidget);
  });
}
