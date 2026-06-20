// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Nooka';

  @override
  String get activeTab => 'Active';

  @override
  String get archiveTab => 'Archive';

  @override
  String get addCategory => 'Add category';

  @override
  String get editCategory => 'Edit category';

  @override
  String get categoryNameLabel => 'Category name';

  @override
  String get iconLabel => 'Icon (optional)';

  @override
  String get iconHelper =>
      'A single emoji or character shown next to the name.';

  @override
  String get addTask => 'New item';

  @override
  String get editTask => 'Edit item';

  @override
  String get taskNameLabel => 'Item name';

  @override
  String get categoryLabel => 'Category';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get markDoneLabel => 'Mark done';

  @override
  String get clearArchiveTitle => 'Clear archive?';

  @override
  String clearArchiveBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archived items',
      one: '$count archived item',
      zero: 'no archived items',
    );
    return 'Permanently delete $_temp0?';
  }

  @override
  String completedOn(String date) {
    return 'Completed $date';
  }

  @override
  String get deleteCategoryTitle => 'Delete category?';

  @override
  String deleteCategoryBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
      zero: 'no items',
    );
    return 'Permanently delete \"$name\" and $_temp0?';
  }

  @override
  String autoRemovesIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
      zero: 'under a day',
    );
    return 'Auto-removes in $_temp0';
  }

  @override
  String openItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
      zero: 'no items',
    );
    return '$_temp0';
  }

  @override
  String get emptyNoCategories => 'No categories yet — add one';

  @override
  String get emptyCategory => 'No items';

  @override
  String get emptyArchive => 'Nothing archived';

  @override
  String get undoCompleteMessage => 'Item completed';

  @override
  String get undoRestoreMessage => 'Item restored';

  @override
  String get undoAction => 'Undo';

  @override
  String get errorLoading => 'Something went wrong';

  @override
  String get actionFailed => 'Couldn\'t complete that. Try again.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get themeLabel => 'Theme';

  @override
  String get languageLabel => 'Language';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get langSystem => 'System';

  @override
  String get langEnglish => 'English';

  @override
  String get langRussian => 'Russian';
}
