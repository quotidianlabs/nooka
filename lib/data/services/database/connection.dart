import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Resolves the [QueryExecutor] for `AppDatabase`. A test-injected [executor] is
/// wrapped so streams close synchronously (fake-async sees no pending timer after
/// the last listener detaches); otherwise it opens the on-device SQLite file.
/// Production I/O glue — unrunnable under `flutter test`, so excluded from
/// coverage (see coverde.yaml). Covered by the emulator integration test.
QueryExecutor resolveExecutor(QueryExecutor? executor) => executor != null
    ? DatabaseConnection(executor, closeStreamsSynchronously: true)
    : driftDatabase(name: 'nooka');
