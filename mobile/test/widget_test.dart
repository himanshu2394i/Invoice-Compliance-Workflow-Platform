import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/app.dart';

void main() {
  testWidgets('app boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: InvoiceCaptureApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice Capture'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
