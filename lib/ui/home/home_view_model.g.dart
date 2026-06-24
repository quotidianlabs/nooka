// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Streams every category with its tasks and owns the home screen's command
/// coordination: it issues mutations, gates remembered-category persistence on
/// success, resolves drag-board drops against its own live state, and reports
/// every command's [CommandOutcome]. The widget collects input and renders
/// outcomes; all coordination lives here.

@ProviderFor(HomeViewModel)
final homeViewModelProvider = HomeViewModelProvider._();

/// Streams every category with its tasks and owns the home screen's command
/// coordination: it issues mutations, gates remembered-category persistence on
/// success, resolves drag-board drops against its own live state, and reports
/// every command's [CommandOutcome]. The widget collects input and renders
/// outcomes; all coordination lives here.
final class HomeViewModelProvider
    extends $StreamNotifierProvider<HomeViewModel, List<CategoryWithTasks>> {
  /// Streams every category with its tasks and owns the home screen's command
  /// coordination: it issues mutations, gates remembered-category persistence on
  /// success, resolves drag-board drops against its own live state, and reports
  /// every command's [CommandOutcome]. The widget collects input and renders
  /// outcomes; all coordination lives here.
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

String _$homeViewModelHash() => r'069bf36ec7df654f7a3d017ba08c8189462424d1';

/// Streams every category with its tasks and owns the home screen's command
/// coordination: it issues mutations, gates remembered-category persistence on
/// success, resolves drag-board drops against its own live state, and reports
/// every command's [CommandOutcome]. The widget collects input and renders
/// outcomes; all coordination lives here.

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
