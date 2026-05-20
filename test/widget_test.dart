import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/base58.dart';
import 'package:unite_wallet/main.dart';

void main() {
  testWidgets('renders Solana wallet onboarding', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const UniteApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Unite'), findsOneWidget);
    expect(find.text('Create Solana wallet'), findsOneWidget);
    expect(find.text('Import recovery phrase'), findsOneWidget);
    expect(find.text('Import private key'), findsOneWidget);
  });

  test('parses Solana private key formats', () {
    final seed = List<int>.generate(32, (index) => index + 1);
    final phantom = [...seed, ...List<int>.generate(32, (index) => index + 33)];

    expect(parsePrivateKey(base58encode(seed)), seed);
    expect(parsePrivateKey(base58encode(phantom)), seed);
    expect(parsePrivateKey(phantom.toString()), seed);
    expect(parsePrivateKey('not a key'), isNull);
  });

  test('decodes address book and Solana Pay URI', () {
    const address = 'mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN';
    expect(solanaPayUri(address), 'solana:$address');
    expect(decodeAddressBook(jsonEncode({address: 'System'})), {
      address: 'System',
    });
    expect(decodeAddressBook('broken'), isEmpty);
  });
}
