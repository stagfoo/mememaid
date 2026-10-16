import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which folders have been sorted, so reopening the app lands back
/// where you left off instead of in a file browser.
class RecentRoots {
  static const _key = 'recent_roots';
  static const _max = 8;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Puts [path] at the front, deduplicated, capped at [_max].
  Future<List<String>> remember(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const [];
    final updated = [path, ...existing.where((p) => p != path)].take(_max).toList();
    await prefs.setStringList(_key, updated);
    return updated;
  }

  Future<List<String>> forget(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final updated =
        (prefs.getStringList(_key) ?? const []).where((p) => p != path).toList();
    await prefs.setStringList(_key, updated);
    return updated;
  }
}
