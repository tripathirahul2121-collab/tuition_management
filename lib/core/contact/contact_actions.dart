class ContactActions {
  const ContactActions._();

  static const _contactPriority = [
    'guardianMobile',
    'parentMobile',
    'parentPhone',
    'guardianPhone',
    'fatherMobile',
    'motherMobile',
    'phone',
    'mobile',
  ];

  static String preferredContactNumber(
    Map<String, dynamic> data, {
    String fallback = '',
  }) {
    for (final key in _contactPriority) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback.trim();
  }

  static Uri? callUri(String rawNumber) {
    final normalized = _normalizeForCall(rawNumber);
    if (normalized == null) return null;
    return Uri(scheme: 'tel', path: normalized);
  }

  static Uri? whatsAppUri({
    required String rawNumber,
    required String message,
  }) {
    final normalized = _normalizeForWhatsApp(rawNumber);
    if (normalized == null) return null;
    return Uri.https('wa.me', '/$normalized', {'text': message});
  }

  static String? _normalizeForCall(String rawNumber) {
    final trimmed = rawNumber.trim();
    if (trimmed.isEmpty) return null;
    final keepsPlus = trimmed.startsWith('+');
    final digits = _digitsOnly(trimmed);
    if (digits.length < 10) return null;
    return keepsPlus ? '+$digits' : digits;
  }

  static String? _normalizeForWhatsApp(String rawNumber) {
    final digits = _digitsOnly(rawNumber);
    if (digits.length == 10) return '91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    if (digits.length > 10) return digits;
    return null;
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }
}
