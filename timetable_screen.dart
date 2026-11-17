import 'package:flutter/material.dart';

import 'database_helper.dart';
import 'digits.dart';
import 'strings.dart';
import 'widgets.dart';

/// One visual block of a day column: either an empty period, or one class
/// (consecutive periods of the same class are merged into a single block).
class _Block {
  final int start; // first period index (0-based)
  final List<TimetableEntry> entries; // empty list = empty cell

  const _Block(this.start, this.entries);

  bool get isEmpty => entries.isEmpty;
  int get length => entries.isEmpty ? 1 : entries.length;
  List<int> get slots => [for (var i = 0; i < length; i++) start + i];
  TimetableEntry get first => entries.first;

  /// Rooms of the merged periods, without duplicates ("A1 / B2").
  String get rooms => entries.map((e) => e.room).where((r) => r.isNotEmpty).toSet().join(' / ');
}

/// Weekly timetable: Monday–Saturday x 9 periods. Tap a cell to assign a class and a room.
/// Consecutive periods of the same class on the same day are merged into one tall block.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const List<String> kPeriodTimes = [
    '08:00', '09:00', '10:00', '11:00', '13:00', '14:00', '15:00', '16:00', '17:00',
  ];
  static const double _timeColWidth = 68;
  static const double _cellWidth = 98;
  static const double _rowHeight = 82; // height of one period, margins included
  static const double _cellMargin = 3;

  final _db = DatabaseHelper.instance;
  Map<String, TimetableEntry> _grid = {};
  List<SchoolClass> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _db.getTimetable();
    final classes = await _db.getClasses();
    if (!mounted) return;
    setState(() {
      _grid = {for (final e in entries) '${e.day}-${e.slot}': e};
      _classes = classes;
      _loading = false;
    });
  }

  /// Splits one day into blocks, merging consecutive periods that have the same class.
  List<_Block> _blocksFor(int day) {
    final blocks = <_Block>[];
    var slot = 0;
    while (slot < kPeriodTimes.length) {
      final entry = _grid['$day-$slot'];
      if (entry == null) {
        blocks.add(_Block(slot, const []));
        slot++;
        continue;
      }
      var end = slot;
      while (end + 1 < kPeriodTimes.length &&
          _grid['$day-${end + 1}']?.classId == entry.classId) {
        end++;
      }
      blocks.add(_Block(slot, [for (var s = slot; s <= end; s++) _grid['$day-$s']!]));
      slot = end + 1;
    }
    return blocks;
  }

  Future<void> _onBlockTap(int day, _Block block) async {
    if (block.length == 1) return _editSlots(day, block.slots);

    // Merged block: edit everything at once, or only one of its periods.
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_agenda_rounded, color: AppColors.indigo),
              title: Text(sheet.t('editWholeBlock'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(sheet, -1),
            ),
            const Divider(height: 1),
            for (final slot in block.slots)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('${sheet.t('period')} ${slot + 1}  (${kPeriodTimes[slot]})'),
                onTap: () => Navigator.pop(sheet, slot),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _editSlots(day, choice == -1 ? block.slots : [choice]);
  }

  /// Assign / change / clear a class for one period or for all periods of a merged block.
  Future<void> _editSlots(int day, List<int> slots) async {
    if (_classes.isEmpty) {
      showSnack(context, context.t('noClasses'));
      return;
    }
    final existing = _grid['$day-${slots.first}'];
    int? selected = existing?.classId;
    final room = TextEditingController(text: existing?.room ?? '');
    final first = slots.first;
    final last = slots.last;
    final periodLabel = first == last
        ? '${context.t('period')} ${first + 1} (${kPeriodTimes[first]})'
        : '${context.t('period')} ${first + 1}–${last + 1} (${kPeriodTimes[first]})';

    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text('${c.t('d$day')} • $periodLabel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.t('pickClassForSlot'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final cls in _classes)
                      ChoiceChip(
                        label: Text(cls.name),
                        selected: selected == cls.id,
                        onSelected: (_) => setLocal(() => selected = cls.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: room,
                  inputFormatters: const [WesternDigitsFormatter()],
                  decoration: fieldDecoration(c.t('room')),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(c, 'clear'),
                child: Text(c.t('clearSlot'), style: const TextStyle(color: AppColors.danger)),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('cancel'))),
            FilledButton(
              onPressed: selected == null ? null : () => Navigator.pop(c, 'save'),
              child: Text(c.t('save')),
            ),
          ],
        ),
      ),
    );

    if (result == 'save' && selected != null) {
      for (final slot in slots) {
        await _db.setTimetableSlot(day, slot, selected!, room.text.trim());
      }
    } else if (result == 'clear') {
      for (final slot in slots) {
        await _db.clearTimetableSlot(day, slot);
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final today = DateTime.now().weekday; // 1 = Monday

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Day headers
              Row(
                children: [
                  const SizedBox(width: _timeColWidth),
                  for (var d = 1; d <= 6; d++)
                    Container(
                      width: _cellWidth,
                      height: 46,
                      margin: const EdgeInsets.all(_cellMargin),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d == today ? AppColors.amber : AppColors.indigo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        context.t('d$d'),
                        style: TextStyle(
                          color: d == today ? AppColors.ink : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time column
                  Column(
                    children: [
                      for (var slot = 0; slot < kPeriodTimes.length; slot++)
                        SizedBox(
                          width: _timeColWidth,
                          height: _rowHeight,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${context.t('period')} ${slot + 1}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  kPeriodTimes[slot],
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  // One column per day, made of (merged) blocks
                  for (var d = 1; d <= 6; d++)
                    Column(
                      children: [
                        for (final block in _blocksFor(d)) _blockWidget(d, block),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockWidget(int day, _Block block) {
    final height = block.length * _rowHeight - 2 * _cellMargin;

    if (block.isEmpty) {
      return GestureDetector(
        onTap: () => _editSlots(day, block.slots),
        child: Container(
          width: _cellWidth,
          height: height,
          margin: const EdgeInsets.all(_cellMargin),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Icon(Icons.add_rounded, color: Colors.grey.shade400),
        ),
      );
    }

    final entry = block.first;
    final color = kClassColors[entry.classId % kClassColors.length];
    final merged = block.length > 1;

    return GestureDetector(
      onTap: () => _onBlockTap(day, block),
      child: Container(
        width: _cellWidth,
        height: height,
        margin: const EdgeInsets.all(_cellMargin),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: merged ? 0.22 : 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              entry.className,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: merged ? 17 : 14,
                color: color,
              ),
            ),
            if (block.rooms.isNotEmpty)
              Text(
                block.rooms,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
          ],
        ),
      ),
    );
  }
}
