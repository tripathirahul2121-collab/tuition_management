import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tuition/core/config/app_branding.dart';
import 'package:tuition/core/widgets/coaching_qr_dialog.dart';

void main() {
  testWidgets('shows a scannable QR for a configured public URL', (
    tester,
  ) async {
    const branding = AppBranding(
      instituteName: 'ABC Academy',
      instituteShortName: 'ABC',
      tagline: 'Focused learning',
      branchName: '',
      logoAsset: 'assets/icon/melogo.png',
      primaryColor: Color(0xFF3F51B5),
      secondaryColor: Color(0xFF5C6BC0),
      accentColor: Color(0xFF0EA5E9),
      backgroundColor: Color(0xFFF6F8FC),
      surfaceColor: Colors.white,
      textColor: Color(0xFF111827),
      contactPhone: '',
      whatsAppNumber: '',
      supportEmail: '',
      website: '',
      publicAppUrl: 'https://abcacademy.example.com',
      address: '',
      footerText: '',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CoachingQrSheet(branding: branding)),
      ),
    );

    expect(
      find.byKey(const ValueKey('coaching-qr:https://abcacademy.example.com')),
      findsOneWidget,
    );
    expect(find.text('https://abcacademy.example.com'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('rejects localhost QR URLs', (tester) async {
    const branding = AppBranding(
      instituteName: 'ABC Academy',
      instituteShortName: 'ABC',
      tagline: 'Focused learning',
      branchName: '',
      logoAsset: 'assets/icon/melogo.png',
      primaryColor: Color(0xFF3F51B5),
      secondaryColor: Color(0xFF5C6BC0),
      accentColor: Color(0xFF0EA5E9),
      backgroundColor: Color(0xFFF6F8FC),
      surfaceColor: Colors.white,
      textColor: Color(0xFF111827),
      contactPhone: '',
      whatsAppNumber: '',
      supportEmail: '',
      website: '',
      publicAppUrl: 'http://localhost:5823',
      address: '',
      footerText: '',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CoachingQrSheet(branding: branding)),
      ),
    );

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('cannot be localhost'), findsWidgets);
  });
}
