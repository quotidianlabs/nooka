/// A backup entry in Drive's appDataFolder.
class CloudBackupRef {
  const CloudBackupRef({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  final String id; // Drive file id
  final String name; // nooka-backup-<stamp>.json
  final DateTime createdAt; // Drive createdTime; for sort/prune/display
}

/// Minimal projection of the connected account for the UI.
class CloudAccount {
  const CloudAccount(this.email);
  final String email;
}

/// The platform cloud-storage seam for backups. The default
/// [GoogleDriveBackupIo] talks to Google Drive's appDataFolder; tests
/// substitute a fake so [CloudBackupRepository] is exercised without a device.
abstract interface class CloudBackupIo {
  /// The currently connected account, or null if not connected.
  Future<CloudAccount?> currentAccount();

  /// Interactive sign-in + appdata authorization; null if the user cancels.
  Future<CloudAccount?> connect();

  /// Forgets the connected account / revokes local tokens.
  Future<void> disconnect();

  /// Lists backup files in appDataFolder (any order).
  Future<List<CloudBackupRef>> list();

  /// Uploads [contents] as a new file named [name] in appDataFolder.
  Future<void> upload(String name, String contents);

  /// Downloads the contents of the file with [id].
  Future<String> download(String id);

  /// Deletes the file with [id].
  Future<void> delete(String id);
}
