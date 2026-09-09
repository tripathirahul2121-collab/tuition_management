class FirestoreQueryCache {
  FirestoreQueryCache._();

  static final Map<String, _CacheEntry<Object?>> _entries = {};

  static Future<T> remember<T>(
    String key,
    Future<T> Function() loader, {
    Duration ttl = const Duration(seconds: 45),
    bool forceRefresh = false,
  }) {
    final now = DateTime.now();
    final entry = _entries[key];

    if (!forceRefresh &&
        entry != null &&
        now.difference(entry.createdAt) < ttl) {
      return entry.future.then((value) => value as T);
    }

    final future = loader();
    _entries[key] = _CacheEntry<T>(future, now);
    future.then(
      (_) {},
      onError: (_) {
        if (identical(_entries[key]?.future, future)) {
          _entries.remove(key);
        }
      },
    );
    return future;
  }

  static void invalidate(String keyPrefix) {
    _entries.removeWhere((key, _) => key.startsWith(keyPrefix));
  }
}

class _CacheEntry<T> {
  const _CacheEntry(this.future, this.createdAt);

  final Future<T> future;
  final DateTime createdAt;
}
