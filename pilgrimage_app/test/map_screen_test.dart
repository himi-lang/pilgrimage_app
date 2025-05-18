import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrimage_app/main.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('MapScreen loads with GoogleMap and AppBar title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('聖地巡礼マップ'), findsOneWidget);
    expect(find.byType(GoogleMap), findsOneWidget);
  });
}
