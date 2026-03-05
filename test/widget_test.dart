// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:barangay_legal_aid/main.dart';
import 'package:barangay_legal_aid/services/api_service.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';
import 'package:barangay_legal_aid/services/secure_storage_service.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    final secure = SecureStorageService();
    final apiService = ApiService(secure);
    final authService = AuthService(secureStorage: secure, apiService: apiService);

    await tester.pumpWidget(MyApp(
      isLoggedIn: false,
      authService: authService,
      apiService: apiService,
    ));

    expect(find.text('Barangay Legal Aid'), findsOneWidget);
    expect(find.text('Login to Legal Aid'), findsOneWidget);
  });
}
