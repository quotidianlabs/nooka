import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/backup_codec.dart';
import '../../domain/clock.dart';
import '../../domain/models/backup_data.dart';
import '../services/backup/backup_io.dart';
import '../services/backup/platform_backup_io.dart';
import 'todo_repository.dart';

part 'backup_repository.g.dart';

/// Orchestrates backup file I/O: builds + encodes a snapshot, writes a temp
/// file and shares it; picks a file, reads and decodes it. All platform calls
/// go through the injectable [BackupIo] seam so this logic is unit-testable.
class BackupRepository {
  BackupRepository(this._todos, this._io, {this._clock = const SystemClock()});
  final TodoRepository _todos;
  final BackupIo _io;
  final Clock _clock;

  Future<void> exportAndShare({required String subject}) async {
    final now = _clock.now();
    final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
    final path = await _io.writeTemp(
      'nooka-backup-${_isoDate(now)}.json',
      json,
    );
    await _io.shareFile(path, subject);
  }

  Future<BackupData?> pickAndDecode() async {
    final path = await _io.pickFile();
    if (path == null) return null;
    return decodeBackup(await _io.readFile(path));
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

@Riverpod(keepAlive: true)
BackupRepository backupRepository(Ref ref) => BackupRepository(
  ref.watch(todoRepositoryProvider),
  const PlatformBackupIo(),
  clock: ref.watch(clockProvider),
);
