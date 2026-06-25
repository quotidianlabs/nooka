/// The platform file-I/O seam for backups. The default [PlatformBackupIo] does
/// real share-sheet / file-picker / temp-file work; tests substitute a fake so
/// [BackupRepository] orchestration is exercised without a device.
abstract interface class BackupIo {
  /// Writes [contents] to a temp file named [filename]; returns its path.
  Future<String> writeTemp(String filename, String contents);

  /// Hands the file at [path] to the OS share sheet under [subject].
  Future<void> shareFile(String path, String subject);

  /// Opens the OS file picker; returns the chosen path, or null if cancelled.
  Future<String?> pickFile();

  /// Reads the file at [path] as a string.
  Future<String> readFile(String path);
}
