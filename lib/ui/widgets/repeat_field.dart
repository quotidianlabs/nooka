import 'package:flutter/material.dart';

import '../../domain/recurrence.dart';
import '../../l10n/app_localizations.dart';

/// The Repeat section shared by the quick-add and edit task dialogs: an
/// on/off switch and, when on, a count stepper and a unit selector, all
/// full-width rows with 48px touch targets. Controlled: the parent owns
/// the state and receives every change through [onChanged].
class RepeatField extends StatelessWidget {
  const RepeatField({
    super.key,
    required this.repeat,
    required this.count,
    required this.unit,
    required this.onChanged,
  });

  final bool repeat;
  final int count;
  final RecurrenceUnit unit;
  final void Function(bool repeat, int count, RecurrenceUnit unit) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const Key('task-repeat-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.repeatLabel),
          value: repeat,
          onChanged: (v) => onChanged(v, count, unit),
        ),
        if (repeat) ...[
          Row(
            key: const Key('task-repeat-stepper'),
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: count > 1
                      ? () => onChanged(repeat, count - 1, unit)
                      : null,
                  child: const Icon(Icons.remove),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => onChanged(repeat, count + 1, unit),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<RecurrenceUnit>(
              key: const Key('task-repeat-unit'),
              style: SegmentedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              segments: [
                ButtonSegment(
                  value: RecurrenceUnit.days,
                  label: Text(l10n.recurrenceUnitDays),
                ),
                ButtonSegment(
                  value: RecurrenceUnit.weeks,
                  label: Text(l10n.recurrenceUnitWeeks),
                ),
                ButtonSegment(
                  value: RecurrenceUnit.months,
                  label: Text(l10n.recurrenceUnitMonths),
                ),
              ],
              selected: {unit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(repeat, count, s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.recurrenceSummary(count, unit.name),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}
