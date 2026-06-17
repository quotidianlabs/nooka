// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Nooka';

  @override
  String get activeTab => 'Активные';

  @override
  String get archiveTab => 'Архив';

  @override
  String get addCategory => 'Добавить категорию';

  @override
  String get editCategory => 'Изменить категорию';

  @override
  String get categoryNameLabel => 'Название категории';

  @override
  String get colorLabel => 'Цвет';

  @override
  String get emojiLabel => 'Эмодзи (необязательно)';

  @override
  String get addTask => 'Новое дело';

  @override
  String get editTask => 'Изменить дело';

  @override
  String get taskNameLabel => 'Название дела';

  @override
  String get categoryLabel => 'Категория';

  @override
  String get moveToCategory => 'Переместить в категорию';

  @override
  String get save => 'Сохранить';

  @override
  String get add => 'Добавить';

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get edit => 'Изменить';

  @override
  String get rename => 'Переименовать';

  @override
  String get restore => 'Вернуть';

  @override
  String get done => 'Готово';

  @override
  String get clearArchive => 'Очистить архив';

  @override
  String get clearArchiveTitle => 'Очистить архив?';

  @override
  String clearArchiveBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дела',
      many: '$count дел',
      few: '$count дела',
      one: '$count дело',
      zero: 'нет дел',
    );
    return 'Удалить из архива $_temp0 навсегда?';
  }

  @override
  String completedOn(String date) {
    return 'Выполнено $date';
  }

  @override
  String get deleteCategoryTitle => 'Удалить категорию?';

  @override
  String deleteCategoryBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дела',
      many: '$count дел',
      few: '$count дела',
      one: '$count дело',
      zero: 'нет дел',
    );
    return 'Удалить «$name» и $_temp0 навсегда?';
  }

  @override
  String autoRemovesIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дня',
      many: '$count дней',
      few: '$count дня',
      one: '$count день',
      zero: 'меньше суток',
    );
    return 'Удалится через $_temp0';
  }

  @override
  String openItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дела',
      many: '$count дел',
      few: '$count дела',
      one: '$count дело',
      zero: 'нет дел',
    );
    return '$_temp0';
  }

  @override
  String get emptyNoCategories => 'Пока нет категорий — добавьте одну';

  @override
  String get emptyCategory => 'Нет дел';

  @override
  String get emptyArchive => 'В архиве пусто';

  @override
  String get undoCompleteMessage => 'Дело выполнено';

  @override
  String get undoRestoreMessage => 'Дело возвращено';

  @override
  String get undoAction => 'Отменить';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get themeLabel => 'Тема';

  @override
  String get languageLabel => 'Язык';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get langSystem => 'Системный';

  @override
  String get langEnglish => 'Английский';

  @override
  String get langRussian => 'Русский';
}
