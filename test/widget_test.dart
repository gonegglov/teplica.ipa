import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse_pro/main.dart';

void main() {
  testWidgets('Проверка запуска экрана теплицы', (WidgetTester tester) async {
    await tester.pumpWidget(const GreenhouseApp());
    expect(find.text('ГринХаус Про'), findsOneWidget);
  });
}