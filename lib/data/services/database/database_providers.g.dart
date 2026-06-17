// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'59cce38d45eeaba199eddd097d8e149d66f9f3e1';

@ProviderFor(todoDao)
final todoDaoProvider = TodoDaoProvider._();

final class TodoDaoProvider
    extends $FunctionalProvider<TodoDao, TodoDao, TodoDao>
    with $Provider<TodoDao> {
  TodoDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoDaoHash();

  @$internal
  @override
  $ProviderElement<TodoDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TodoDao create(Ref ref) {
    return todoDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TodoDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TodoDao>(value),
    );
  }
}

String _$todoDaoHash() => r'fc49dc00d094795fa604050ec790e61c880d4939';
