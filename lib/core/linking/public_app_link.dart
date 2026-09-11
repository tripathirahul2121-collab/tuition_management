class PublicAppLink {
  const PublicAppLink._({required this.uri, required this.errorMessage});

  final Uri? uri;
  final String? errorMessage;

  bool get isValid => uri != null;

  static PublicAppLink validate(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      return const PublicAppLink._(
        uri: null,
        errorMessage:
            'Public app link is not configured yet. Please configure the coaching app URL before generating the QR code.',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return const PublicAppLink._(
        uri: null,
        errorMessage:
            'Public app link is invalid. Please configure a valid URL.',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return const PublicAppLink._(
        uri: null,
        errorMessage: 'Public app link must start with http:// or https://.',
      );
    }

    final host = uri.host.toLowerCase();
    if (_isLocalHost(host)) {
      return const PublicAppLink._(
        uri: null,
        errorMessage:
            'Public app link cannot be localhost. Configure a deployed URL that another phone can open.',
      );
    }

    return PublicAppLink._(uri: uri, errorMessage: null);
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
      return true;
    }
    if (host == '::1' || host == '[::1]') return true;
    if (host.endsWith('.localhost')) return true;
    if (host.startsWith('127.')) return true;
    return false;
  }
}
