import 'package:flutter/material.dart';

import 'app_state.dart';
import 'database_helper.dart';
import 'random_picker.dart';
import 'strings.dart';
import 'widgets.dart';

/// List of classes (7ème B1, 8ème B2, Bac Math...). Tap a class to manage its students.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  final _db = DatabaseHelper.instance;
  List<SchoolClass> _classes = [];
  Map<int, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final classes = await _db.getClasses();
    final counts = await _db.getStudentCounts();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _addClass() async {
    final name = await promptText(
      context,
      title: context.t('addClass'),
      label: context.t('className'),
      hint: context.t('classHint'),
    );
    if (name == null || name.isEmpty) return;
    final id = await _db.insertClass(name);
    // The first class created becomes the active one automatically.
    if (AppState.activeClassId.value == null) await AppState.setActiveClass(id);
    _load();
  }

  Future<void> _rename(SchoolClass c) async {
    final name = await promptText(
      context,
      title: context.t('rename'),
      label: context.t('className'),
      initial: c.name,
    );
    if (name == null || name.isEmpty) return;
    await _db.renameClass(c.id!, name);
    _load();
  }

  Future<void> _delete(SchoolClass c) async {
    if (!await confirmDelete(context, what: c.name)) return;
    await _db.deleteClass(c.id!);
    if (AppState.activeClassId.value == c.id) await AppState.setActiveClass(null);
    _load();
  }

  Future<void> _open(SchoolClass c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClassDetailScreen(schoolClass: c)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClass,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('addClass')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? EmptyState(icon: Icons.groups_outlined, message: context.t('noClassesYet'))
              : ValueListenableBuilder<int?>(
                  valueListenable: AppState.activeClassId,
                  builder: (context, activeId, _) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _classes.length,
                      itemBuilder: (_, i) {
                        final c = _classes[i];
                        final color = kClassColors[c.id! % kClassColors.length];
                        final isActive = c.id == activeId;
                        return SoftCard(
                          onTap: () => _open(c),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(Icons.groups_rounded, color: color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      '${_counts[c.id] ?? 0} ${context.t('studentsCount')}',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: context.t('setActive'),
                                onPressed: () => AppState.setActiveClass(c.id),
                                icon: Icon(
                                  isActive ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: AppColors.amber,
                                  size: 30,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) => v == 'rename' ? _rename(c) : _delete(c),
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'rename', child: Text(context.t('rename'))),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(context.t('delete'),
                                        style: const TextStyle(color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

/// Students of one class: add (one or many at once), edit, delete, random draw.
class ClassDetailScreen extends StatefulWidget {
  final SchoolClass schoolClass;
  const ClassDetailScreen({super.key, required this.schoolClass});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Student> _students = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final students = await _db.getStudents(widget.schoolClass.id!);
    if (!mounted) return;
    setState(() {
      _students = students;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showDialog<_StudentForm>(
      context: context,
      builder: (_) => _StudentFormDialog(title: context.t('addStudents'), multiline: true),
    );
    if (result == null) return;
    final names = result.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.isEmpty) return;
    await _db.insertStudents(widget.schoolClass.id!, names, gender: result.gender);
    _load();
  }

  Future<void> _edit(Student s) async {
    final result = await showDialog<_StudentForm>(
      context: context,
      builder: (_) => _StudentFormDialog(
        title: context.t('editStudent'),
        initialName: s.name,
        initialGender: s.gender,
      ),
    );
    if (result == null || result.text.isEmpty) return;
    await _db.updateStudent(s.id!, result.text, result.gender);
    await AppState.refreshSelected(); // the selected student may be this one
    _load();
  }

  Future<void> _delete(Student s) async {
    if (!await confirmDelete(context, what: s.name)) return;
    await _db.deleteStudent(s.id!);
    if (AppState.selectedStudent.value?.id == s.id) await AppState.selectStudent(null);
    _load();
  }

  Future<void> _draw() async {
    await drawRandomStudent(context, _students);
    if (mounted) _load();
  }

  Future<void> _resetPoints() async {
    final ok = await confirmDialog(
      context,
      title: context.t('resetPoints'),
      body: context.t('resetPointsConfirm'),
      confirmLabel: context.t('reset'),
    );
    if (!ok) return;
    await _db.resetPoints(widget.schoolClass.id!);
    await AppState.refreshSelected();
    _load();
  }

  Future<void> _select(Student s) async {
    await AppState.chooseStudent(s);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schoolClass.name),
        actions: [
          IconButton(
            tooltip: context.t('randomStudent'),
            onPressed: _draw,
            icon: const Icon(Icons.casino_rounded, color: AppColors.amber),
          ),
          IconButton(
            tooltip: context.t('resetPoints'),
            onPressed: _resetPoints,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(context.t('addStudents')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? EmptyState(icon: Icons.person_outline_rounded, message: context.t('noStudentsYet'))
              : ValueListenableBuilder<Student?>(
                  valueListenable: AppState.selectedStudent,
                  builder: (context, selected, _) => ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _students.length,
                    itemBuilder: (_, i) {
                      final s = _students[i];
                      final isSelected = selected?.id == s.id;
                      return SoftCard(
                        onTap: () => _select(s),
                        color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isSelected
                                  ? AppColors.indigo
                                  : AppColors.indigo.withValues(alpha: 0.12),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.indigo,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.name,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              s.isFemale ? Icons.female_rounded : Icons.male_rounded,
                              color: s.isFemale ? const Color(0xFFDB2777) : AppColors.indigo,
                              size: 24,
                            ),
                            const SizedBox(width: 6),
                            PointsBadge(points: s.points),
                            IconButton(
                              tooltip: context.t('edit'),
                              onPressed: () => _edit(s),
                              icon: const Icon(Icons.edit_rounded, color: AppColors.indigo),
                            ),
                            IconButton(
                              tooltip: context.t('delete'),
                              onPressed: () => _delete(s),
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _StudentForm {
  final String text;
  final String gender;
  const _StudentForm(this.text, this.gender);
}

/// Name field + gender selector (ذكر / أنثى). With [multiline] it adds several students
/// at once (one name per line), all with the selected gender.
class _StudentFormDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialGender;
  final bool multiline;

  const _StudentFormDialog({
    required this.title,
    this.initialName = '',
    this.initialGender = kMale,
    this.multiline = false,
  });

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialName);
  late String _gender = widget.initialGender;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _StudentForm(_ctrl.text.trim(), _gender));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              inputFormatters: const [WesternDigitsFormatter()],
              minLines: widget.multiline ? 4 : 1,
              maxLines: widget.multiline ? 10 : 1,
              textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
              onSubmitted: widget.multiline ? null : (_) => _submit(),
              decoration: fieldDecoration(
                context.t('studentName'),
                hint: widget.multiline ? context.t('oneNamePerLine') : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(context.t('gender'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<String>(
                    value: kMale,
                    icon: const Icon(Icons.male_rounded),
                    label: Text(context.t('male')),
                  ),
                  ButtonSegment<String>(
                    value: kFemale,
                    icon: const Icon(Icons.female_rounded),
                    label: Text(context.t('female')),
                  ),
                ],
                selected: {_gender},
                onSelectionChanged: (v) => setState(() => _gender = v.first),
              ),
            ),
            if (widget.multiline)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  context.t('genderAddHint'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.t('save'))),
      ],
    );
  }
}
