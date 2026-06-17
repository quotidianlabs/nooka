// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Streams every category with its tasks and exposes mutation commands.
/// Depends only on [TodoRepository].

@ProviderFor(HomeViewModel)
final homeViewModelProvider = HomeViewModelProvider._();

/// Streams every category with its tasks and exposes mutation commands.
/// Depends only on [TodoRepository].
final class HomeViewModelProvider
    extends $StreamNotifierProvider<HomeViewModel, List<CategoryWithTasks>> {
  /// Streams every category with its tasks and exposes mutation commands.
  /// Depends only on [TodoRepository].
  HomeViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeViewModelHash();

  @$internal
  @override
  HomeViewModel create() => HomeViewModel();
}

String _$homeViewModelHash() => r'ee780e4d32461b1ad62255c06561e601afeef8db';

/// Streams every category with its tasks and exposes mutation commands.
/// Depends only on [TodoRepository].

abstract class _$HomeViewModel
    extends $StreamNotifier<List<CategoryWithTasks>> {
  Stream<List<CategoryWithTasks>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<CategoryWithTasks>>,
              List<CategoryWithTasks>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<CategoryWithTasks>>,
                List<CategoryWithTasks>
              >,
              AsyncValue<List<CategoryWithTasks>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
