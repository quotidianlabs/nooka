import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_io.dart';

/// Production file-I/O glue — unrunnable under `flutter test`, so excluded from
/// coverage (see coverde.yaml). Exercised manually / by emulator runs.
class PlatformBackupIo implements BackupIo {
  const PlatformBackupIo();

  @override
  Future<String> writeTemp(String filename, String contents) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }

  @override
  Future<void> shareFile(String path, String subject) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: subject),
    );
  }

  @override
  Future<String?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    return result?.files.single.path;
  }

  @override
  Future<String> readFile(String path) => File(path).readAsString();
}
