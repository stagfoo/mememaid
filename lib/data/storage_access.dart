import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Wraps the one permission this app lives or dies by.
///
/// Mememaid moves files between folders the user picks, which the Storage
/// Access Framework can't express without a tree grant per folder — so it asks
/// for "All files access" and then uses plain dart:io. That grant is handed out
/// from a system Settings screen, not an in-app dialog, which is why the
/// request returns via a round trip the UI has to re-check on resume.
class StorageAccess {
  Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    // Android 12 and below have no manageExternalStorage grant; the legacy
    // read permission is the whole story there.
    return Permission.storage.isGranted;
  }

  /// Sends the user to the "All files access" screen. The returned value is
  /// the status immediately afterwards, which on Android is usually still
  /// denied — the grant lands while the app is backgrounded, so the caller
  /// must re-check with [isGranted] on resume rather than trusting this.
  Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  Future<void> openSettings() => openAppSettings();
}
