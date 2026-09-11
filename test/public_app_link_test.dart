import 'package:flutter_test/flutter_test.dart';
import 'package:tuition/core/config/app_branding.dart';
import 'package:tuition/core/linking/public_app_link.dart';

void main() {
  group('PublicAppLink.validate', () {
    test('accepts https public URLs', () {
      final link = PublicAppLink.validate(' https://abcacademy.example.com ');

      expect(link.isValid, isTrue);
      expect(link.uri.toString(), 'https://abcacademy.example.com');
      expect(link.errorMessage, isNull);
    });

    test('rejects missing and malformed URLs', () {
      expect(PublicAppLink.validate('').isValid, isFalse);
      expect(PublicAppLink.validate('not-a-url').isValid, isFalse);
      expect(
        PublicAppLink.validate('mailto:hello@example.com').isValid,
        isFalse,
      );
    });

    test('rejects developer machine URLs', () {
      expect(PublicAppLink.validate('http://localhost:5821').isValid, isFalse);
      expect(PublicAppLink.validate('http://127.0.0.1:5821').isValid, isFalse);
      expect(PublicAppLink.validate('http://127.2.3.4').isValid, isFalse);
      expect(PublicAppLink.validate('http://app.localhost').isValid, isFalse);
    });
  });

  group('WhiteLabelConfig.current', () {
    test('provides a public QR URL by default', () {
      final link = PublicAppLink.validate(
        WhiteLabelConfig.current.publicAppUrl,
      );

      expect(link.isValid, isTrue);
      expect(link.uri.toString(), 'https://tuition-backend.web.app');
    });
  });
}
