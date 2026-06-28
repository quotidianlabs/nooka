// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_backup_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(cloudBackupRepository)
final cloudBackupRepositoryProvider = CloudBackupRepositoryProvider._();

final class CloudBackupRepositoryProvider
    extends
        $FunctionalProvider<
          CloudBackupRepository,
          CloudBackupRepository,
          CloudBackupRepository
        >
    with $Provider<CloudBackupRepository> {
  CloudBackupRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudBackupRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudBackupRepositoryHash();

  @$internal
  @override
  $ProviderElement<CloudBackupRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CloudBackupRepository create(Ref ref) {
    return cloudBackupRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CloudBackupRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CloudBackupRepository>(value),
    );
  }
}

String _$cloudBackupRepositoryHash() =>
    r'8d9787e7155f6ad1436f7bca60968a5647e49f0e';
