import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';
import 'todo_dao.dart';

part 'database_providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@riverpod
TodoDao todoDao(Ref ref) => ref.watch(appDatabaseProvider).todoDao;
