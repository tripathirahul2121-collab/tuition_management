import 'package:flutter_test/flutter_test.dart';
import 'package:tuition/core/contact/contact_actions.dart';

void main() {
  group('ContactActions', () {
    test('prefers guardian and parent contact fields before fallback', () {
      expect(
        ContactActions.preferredContactNumber({
          'mobile': '9999999999',
          'parentMobile': '8888888888',
          'guardianMobile': '7777777777',
        }, fallback: '6666666666'),
        '7777777777',
      );
    });

    test('builds call uri from phone number', () {
      expect(
        ContactActions.callUri('+91 98765 43210').toString(),
        'tel:+919876543210',
      );
    });

    test('builds WhatsApp uri with India code for local mobile', () {
      final uri = ContactActions.whatsAppUri(
        rawNumber: '98765 43210',
        message: 'Absent today',
      );

      expect(uri.toString(), contains('https://wa.me/919876543210'));
      expect(uri!.queryParameters['text'], 'Absent today');
    });
  });
}
