import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Matches an `import`/`export` directive and captures its target, under either
/// quote style. `flutter_lints` does not enable `prefer_single_quotes`, so both
/// are legal here, and an `export` re-publishes a dependency to every importer
/// exactly as an `import` would.
final _directive = RegExp('''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''');

/// Every hand-written Dart file under [dir], paired with its dependency targets.
/// Relative targets are resolved against the importing file, so a check can ask
/// which directory a target actually lands in.
Map<String, List<String>> _dependenciesUnder(String dir) {
  final result = <String, List<String>>{};
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final from = Uri.file(entity.absolute.path);
    result[entity.path] = entity
        .readAsLinesSync()
        .map((line) => _directive.firstMatch(line)?.group(1))
        .nonNulls
        .map(
          (target) =>
              target.startsWith('package:') || target.startsWith('dart:')
              ? target
              : from.resolve(target).toFilePath(),
        )
        .toList();
  }
  return result;
}

/// Files under any of [dirs] whose targets [offends], as `path -> target`.
/// Throws if a directory contributes no files: an empty scan would otherwise
/// make every check below pass without inspecting anything.
List<String> _violations(
  List<String> dirs,
  bool Function(String target) offends,
) {
  final violations = <String>[];
  for (final dir in dirs) {
    final scanned = _dependenciesUnder(dir);
    if (scanned.isEmpty) throw StateError('no Dart files found under $dir');
    scanned.forEach((path, targets) {
      for (final target in targets) {
        if (offends(target)) violations.add('$path -> $target');
      }
    });
  }
  return violations;
}

bool _isUnder(String target, String dir) =>
    target.contains('/$dir/') || target.endsWith('/$dir');

void main() {
  test('domain depends on no Flutter or Drift package', () {
    // INVARIANT: pure logic stays free of the UI toolkit and the database
    // library, so it can be read and tested without either.
    //
    // Broken by reaching for a Flutter type in a domain file because it is
    // convenient: Color for a habit swatch, TimeOfDay for a reminder, or Drift's
    // expression builders to push a computation into SQL. Each one is
    // individually reasonable and collectively turns the date and streak logic
    // into something that only runs inside a widget test with a database
    // attached. The whole ecosystem is excluded, not just the two root packages,
    // because flutter_riverpod in a pure function is the same mistake wearing a
    // different name. Drift still arrives transitively through the generated
    // database library, which docs/adr/0001 permits; a direct dependency is the
    // thing that does not come back.
    expect(
      _violations(
        ['lib/domain'],
        (target) =>
            target.startsWith('package:flutter') ||
            target.startsWith('package:drift'),
      ),
      isEmpty,
    );
  });

  test('the generated database library is the only data dependency in domain', () {
    // INVARIANT: domain depends on the database for row types and nothing else.
    //
    // Broken by importing a repository or a DAO from a domain file to reach a
    // query that is already written, at which point pure functions start doing
    // I/O and the projection can no longer be exercised with a literal set of
    // dates. Drift rows are the domain model by docs/adr/0001, so this single
    // dependency is the price of having no mapper layer; a second one means the
    // mapper is now owed.
    expect(
      _violations(
        ['lib/domain'],
        (target) =>
            _isUnder(target, 'data') && !target.endsWith('/database.dart'),
      ),
      isEmpty,
    );
  });

  test('nothing beneath domain or data depends on the ui layer', () {
    // INVARIANT: the dependency arrow into the UI points one way, so a screen
    // can be rebuilt or deleted without a repository noticing.
    //
    // Broken by a repository or a domain helper reaching for a provider, a theme
    // token, or a localization lookup that happens to live under ui/: the
    // fastest fix at the call site, and the one that makes the data layer
    // unusable from a plain Dart test. lib/main.dart is deliberately outside
    // this rule, being the composition root that wires the screens together.
    expect(
      _violations([
        'lib/domain',
        'lib/data',
      ], (target) => _isUnder(target, 'ui')),
      isEmpty,
    );
  });

  test('the ui layer reaches the database through no DAO', () {
    // INVARIANT: a screen may name a row type, but never the object that queries
    // for one.
    //
    // Broken by a screen calling the DAO for the one value its view model does
    // not expose yet, which is faster than threading it through and leaves the
    // widget untestable without a live database. Widgets holding rows is
    // deliberate here and docs/adr/0001 says why, so this is the line that
    // remains: rows yes, queries no. The sibling repo draws it further out and
    // keeps rows out of the UI entirely.
    expect(
      _violations(['lib/ui'], (target) => target.contains('_dao.dart')),
      isEmpty,
    );
  });

  test('shared widgets read no providers', () {
    // INVARIANT: everything under lib/ui/widgets/ takes values and returns user
    // input. The screen owns the wiring.
    //
    // Broken by a shared widget watching a provider for a value it could have
    // been passed, which quietly binds it to one screen's state and makes it
    // untestable without a container. Feature-local widgets under
    // lib/ui/<feature>/widgets/ are a different thing and may read providers;
    // only the shared directory is held to this.
    expect(
      _violations(['lib/ui/widgets'], (target) => target.contains('riverpod')),
      isEmpty,
    );
  });
}
