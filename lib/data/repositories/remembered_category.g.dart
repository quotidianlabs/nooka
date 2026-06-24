// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remembered_category.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(rememberedCategory)
final rememberedCategoryProvider = RememberedCategoryProvider._();

final class RememberedCategoryProvider
    extends
        $FunctionalProvider<
          RememberedCategory,
          RememberedCategory,
          RememberedCategory
        >
    with $Provider<RememberedCategory> {
  RememberedCategoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rememberedCategoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rememberedCategoryHash();

  @$internal
  @override
  $ProviderElement<RememberedCategory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RememberedCategory create(Ref ref) {
    return rememberedCategory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RememberedCategory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RememberedCategory>(value),
    );
  }
}

String _$rememberedCategoryHash() =>
    r'a1469c97bfc5568f780fef196c66c901c2f3d576';
