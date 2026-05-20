import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unite_wallet/main.dart';

void main() {
  testWidgets('renders Solana wallet onboarding', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const UniteApp());
    await tester.pumpAndSettle();

    expect(find.text('Unite'), findsOneWidget);
    expect(find.text('Create Solana wallet'), findsOneWidget);
    expect(find.text('Import wallet'), findsOneWidget);
  });
}
