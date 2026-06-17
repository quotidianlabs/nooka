default: install lint test

install:
    flutter pub get

lint:
    dart format .
    flutter analyze

lint-ci:
    dart format --output=none --set-exit-if-changed .
    flutter analyze

test *args:
    flutter test {{ args }}
