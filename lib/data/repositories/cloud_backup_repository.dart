import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/backup_codec.dart';
import '../../domain/clock.dart';
import '../../domain/models/backup_data.dart';
import '../services/backup/cloud_backup_io.dart';
import '../services/backup/google_drive_backup_io.dart';
import 'todo_repository.dart';

part 'cloud_backup_repository.g.dart';

/// Orchestrates cloud backup/restore: builds + encodes a snapshot and uploads
/// it (pruning to the newest [_keep]); lists and downloads + decodes backups.
/// All platform calls go through the injectable [CloudBackupIo] seam.
class CloudBackupRepository {
  CloudBackupRepository(
    this._todos,
    this._io, {
    this._clock = const SystemClock(),
  });
  final TodoRepository _todos;
  final CloudBackupIo _io;
  final Clock _clock;

  static const int _keep = 5;

  Future<CloudAccount?> account() => _io.currentAccount();
  Future<CloudAccount?> connect() => _io.connect();
  Future<void> disconnect() => _io.disconnect();

  Future<void> backupNow() async {
    final now = _clock.now();
    final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
    await _io.upload('nooka-backup-${_fileStamp(now)}.json', json);
    await _pruneToNewest(_keep);
  }

  Future<List<CloudBackupRef>> listBackups() async {
    final all = await _io.list();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
    return all;
  }

  Future<BackupData> fetch(String id) async =>
      decodeBackup(await _io.download(id));

  Future<void> _pruneToNewest(int keep) async {
    final all = await listBackups(); // already newest-first
    for (final r in all.skip(keep)) {
      await _io.delete(r.id);
    }
  }

  String _fileStamp(DateTime d) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(d.year, 4)}-${p(d.month)}-${p(d.day)}'
        'T${p(d.hour)}-${p(d.minute)}-${p(d.second)}';
  }
}

@Riverpod(keepAlive: true)
CloudBackupRepository cloudBackupRepository(Ref ref) => CloudBackupRepository(
  ref.watch(todoRepositoryProvider),
  GoogleDriveBackupIo(),
  clock: ref.watch(clockProvider),
);
