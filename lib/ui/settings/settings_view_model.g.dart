// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the settings screen's backup commands: export, pick-and-decode, and
/// apply (replace-all). Raw errors never cross the seam — they are logged and
/// mapped to a coarse result the widget turns into a localized SnackBar.

@ProviderFor(SettingsViewModel)
final settingsViewModelProvider = SettingsViewModelProvider._();

/// Owns the settings screen's backup commands: export, pick-and-decode, and
/// apply (replace-all). Raw errors never cross the seam — they are logged and
/// mapped to a coarse result the widget turns into a localized SnackBar.
final class SettingsViewModelProvider
    extends $NotifierProvider<SettingsViewModel, void> {
  /// Owns the settings screen's backup commands: export, pick-and-decode, and
  /// apply (replace-all). Raw errors never cross the seam — they are logged and
  /// mapped to a coarse result the widget turns into a localized SnackBar.
  SettingsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsViewModelHash();

  @$internal
  @override
  SettingsViewModel create() => SettingsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$settingsViewModelHash() => r'b27b0842cdd1a5849d7aaf25a8f3045bd298735d';

/// Owns the settings screen's backup commands: export, pick-and-decode, and
/// apply (replace-all). Raw errors never cross the seam — they are logged and
/// mapped to a coarse result the widget turns into a localized SnackBar.

abstract class _$SettingsViewModel extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
