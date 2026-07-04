import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/models/backup_data.dart';
import 'package:nooka/domain/recurrence.dart';

void main() {
  BackupData sample() => BackupData(
    version: 1,
    exportedAt: DateTime.utc(2026, 6, 25, 9, 30),
    categories: [
      BackupCategory(
        name: 'Work',
        color: 4278228616,
        emoji: '💼',
        collapsed: false,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1, 8),
        tasks: [
          BackupTask(
            name: 'Ship it',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 6, 2, 8),
            archivedAt: null,
          ),
          BackupTask(
            name: 'Old thing',
            sortOrder: 1,
            createdAt: DateTime.utc(2026, 6, 1, 8),
            archivedAt: DateTime.utc(2026, 6, 10, 12),
          ),
        ],
      ),
    ],
  );

  test('round-trips through encode/decode', () {
    final decoded = decodeBackup(encodeBackup(sample()));
    expect(decoded.version, 1);
    expect(decoded.categories.single.name, 'Work');
    expect(decoded.categories.single.emoji, '💼');
    final tasks = decoded.categories.single.tasks;
    expect(tasks[0].archivedAt, isNull);
    expect(tasks[1].archivedAt, DateTime.utc(2026, 6, 10, 12));
  });

  test('encodes an empty database', () {
    final json = encodeBackup(
      BackupData(version: 1, exportedAt: DateTime.utc(2026), categories: []),
    );
    expect(decodeBackup(json).categories, isEmpty);
  });

  test('BackupFormatException.toString includes the message', () {
    expect(
      const BackupFormatException('bad file').toString(),
      contains('bad file'),
    );
  });

  group('decode rejects', () {
    void rejects(String source) => expect(
      () => decodeBackup(source),
      throwsA(isA<BackupFormatException>()),
    );

    test('non-JSON', () => rejects('not json'));
    test('non-object root', () => rejects('[1,2,3]'));
    test(
      'wrong app',
      () => rejects(
        '{"app":"habbits","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[]}',
      ),
    );
    test(
      'wrong version',
      () => rejects(
        '{"app":"nooka","version":3,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[]}',
      ),
    );
    test(
      'missing categories',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000"}',
      ),
    );
    test(
      'category missing name',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"color":1,'
        '"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}',
      ),
    );
    test(
      'task with bad archivedAt',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[{"name":"T",'
        '"sortOrder":0,"createdAt":"2026-06-25T00:00:00.000",'
        '"archivedAt":"not-a-date"}]}]}',
      ),
    );
    test(
      'missing exportedAt',
      () => rejects('{"app":"nooka","version":1,"categories":[]}'),
    );
    test(
      'invalid exportedAt type',
      () => rejects(
        '{"app":"nooka","version":1,"exportedAt":123,"categories":[]}',
      ),
    );
    test(
      'category entry not a map',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[42]}',
      ),
    );
    test(
      'category color not an int',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":"red","emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}',
      ),
    );
    test(
      'category emoji wrong type',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":5,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}',
      ),
    );
    test(
      'category collapsed not a bool',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":"yes","sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}',
      ),
    );
    test(
      'category sortOrder not an int',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":"0",'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}',
      ),
    );
    test(
      'category createdAt unparseable',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"not-a-date","tasks":[]}]}',
      ),
    );
    test(
      'category tasks not a list',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":{}}]}',
      ),
    );
    test(
      'task entry not a map',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[42]}]}',
      ),
    );
    test(
      'task missing name',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[{"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","archivedAt":null}]}]}',
      ),
    );
    test(
      'task sortOrder not an int',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[{"name":"T",'
        '"sortOrder":"0","createdAt":"2026-06-25T00:00:00.000",'
        '"archivedAt":null}]}]}',
      ),
    );
    test(
      'task createdAt unparseable',
      () => rejects(
        '{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[{"name":"T",'
        '"sortOrder":0,"createdAt":"not-a-date",'
        '"archivedAt":null}]}]}',
      ),
    );
  });

  group('v2 recurrence', () {
    test('encodes version 2 and round-trips recurrence + dormancy', () {
      final data = BackupData(
        version: 2,
        exportedAt: DateTime.utc(2026, 7, 4),
        categories: [
          BackupCategory(
            name: 'Home',
            color: 1,
            emoji: null,
            collapsed: false,
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 1, 1),
            tasks: [
              BackupTask(
                name: 'Water',
                sortOrder: 0,
                createdAt: DateTime.utc(2026, 1, 1),
                archivedAt: null,
                recurrenceCount: 3,
                recurrenceUnit: RecurrenceUnit.weeks,
                nextDueAt: DateTime.utc(2026, 8, 1),
              ),
            ],
          ),
        ],
      );
      final decoded = decodeBackup(encodeBackup(data));
      final t = decoded.categories.single.tasks.single;
      expect(decoded.version, 2);
      expect(t.recurrenceCount, 3);
      expect(t.recurrenceUnit, RecurrenceUnit.weeks);
      expect(t.nextDueAt, DateTime.utc(2026, 8, 1));
    });

    test('a v1 file (no recurrence keys) still decodes with nulls', () {
      const v1 = '''
      {"app":"nooka","version":1,"exportedAt":"2026-07-04T00:00:00.000Z",
       "categories":[{"name":"Home","color":1,"emoji":null,"collapsed":false,
       "sortOrder":0,"createdAt":"2026-01-01T00:00:00.000Z",
       "tasks":[{"name":"Water","sortOrder":0,
       "createdAt":"2026-01-01T00:00:00.000Z","archivedAt":null}]}]}''';
      final decoded = decodeBackup(v1);
      final t = decoded.categories.single.tasks.single;
      expect(decoded.version, 1);
      expect(t.recurrenceCount, isNull);
      expect(t.recurrenceUnit, isNull);
      expect(t.nextDueAt, isNull);
    });
  });
}
