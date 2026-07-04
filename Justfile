default: install lint test

install:
    flutter pub get

lint:
    dart format .
    flutter analyze

lint-ci:
    dart format --output=none --set-exit-if-changed .
    flutter analyze
    python3 planning/index.py --check

test *args:
    flutter test {{ args }}

# tests with coverage; excludes generated + DB glue, gates the % (matches CI).
# One-time setup: `dart pub global activate coverde` — `pub global run` then
# finds it without needing ~/.pub-cache/bin on PATH.
coverage:
    flutter test --coverage
    dart pub global run coverde transform --input coverage/lcov.info --output coverage/lcov.info --mode w --transformations preset=exclude-untestable
    dart pub global run coverde check --input coverage/lcov.info 100

# Print the planning change index (flat, newest-first) to stdout.
index:
    python3 planning/index.py

# Validate planning bundles + decisions; CI runs this via lint-ci.
check-planning:
    python3 planning/index.py --check

# Dump the current schema snapshot into drift_schemas/ (run after bumping
# schemaVersion, before generating steps).
schema-dump:
    dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/

# Regenerate migration step helpers + SchemaVerifier test helpers from the
# snapshots in drift_schemas/.
schema-gen:
    dart run drift_dev schema steps drift_schemas/ lib/data/services/database/database.steps.dart
    dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/
