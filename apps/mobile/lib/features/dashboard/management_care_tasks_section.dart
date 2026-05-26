import 'package:flutter/material.dart';

import '../management/flicko_care_task.dart';

void showCareTaskSheet(
  BuildContext context, {
  required String problemName,
  required FlickoCareTaskWriter onSaveTask,
  FlickoCareTask? existing,
  DateTime Function()? nowProvider,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CareTaskSheet(
      problemName: problemName,
      existing: existing,
      onSaveTask: onSaveTask,
      nowProvider: nowProvider ?? DateTime.now,
    ),
  );
}

class ManagementCareTasksSection extends StatelessWidget {
  const ManagementCareTasksSection({
    super.key,
    required this.problemName,
    required this.tasks,
    required this.onSaveTask,
    required this.onDeleteTask,
    DateTime Function()? nowProvider,
    this.showTaskList = true,
  }) : nowProvider = nowProvider ?? DateTime.now;

  final String problemName;
  final List<FlickoCareTask> tasks;
  final FlickoCareTaskWriter onSaveTask;
  final FlickoCareTaskDeleter onDeleteTask;
  final DateTime Function() nowProvider;
  final bool showTaskList;

  @override
  Widget build(BuildContext context) {
    final now = nowProvider();
    final visibleTasks = tasks.take(8).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3EAE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TaskIconBubble(icon: Icons.fact_check_rounded),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Care tasks',
                      style: TextStyle(
                        color: Color(0xFF0B372D),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Medicines, readings, meals, activity, and follow-ups.',
                      style: TextStyle(
                        color: Color(0xFF65736F),
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _SmallButton(
                label: 'Add',
                icon: Icons.add_rounded,
                onTap: () => showCareTaskSheet(
                  context,
                  problemName: problemName,
                  onSaveTask: onSaveTask,
                  nowProvider: nowProvider,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!showTaskList && visibleTasks.isNotEmpty)
            _CompactTaskSummary(count: visibleTasks.length)
          else if (visibleTasks.isEmpty)
            const _EmptyTasks()
          else
            Column(
              children: [
                for (final task in visibleTasks)
                  _CareTaskTile(
                    task: task,
                    doneToday: task.isDoneOn(now),
                    onDoneToggle: () => _toggleDone(context, task),
                    onEdit: () => showCareTaskSheet(
                      context,
                      problemName: problemName,
                      onSaveTask: onSaveTask,
                      existing: task,
                      nowProvider: nowProvider,
                    ),
                    onDelete: () => _deleteTask(context, task),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _toggleDone(BuildContext context, FlickoCareTask task) async {
    final now = nowProvider();
    final next = task.isDoneOn(now)
        ? task.copyWith(clearCompleted: true, updatedAt: now)
        : task.copyWith(lastCompletedAt: now, updatedAt: now);
    final saved = await onSaveTask(next);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Care task updated.' : 'Could not update task.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteTask(BuildContext context, FlickoCareTask task) async {
    final deleted = await onDeleteTask(task);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? 'Care task deleted.' : 'Could not delete task.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _CareTaskSheet extends StatefulWidget {
  const _CareTaskSheet({
    required this.problemName,
    required this.onSaveTask,
    required this.nowProvider,
    this.existing,
  });

  final String problemName;
  final FlickoCareTaskWriter onSaveTask;
  final DateTime Function() nowProvider;
  final FlickoCareTask? existing;

  @override
  State<_CareTaskSheet> createState() => _CareTaskSheetState();
}

class _CareTaskSheetState extends State<_CareTaskSheet> {
  late FlickoCareTaskType _type;
  late final TextEditingController _title;
  late final TextEditingController _detail;
  late final TextEditingController _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? FlickoCareTaskType.medicine;
    _title = TextEditingController(text: existing?.title ?? _type.defaultTitle);
    _detail = TextEditingController(text: existing?.detail);
    _time = TextEditingController(text: existing?.timeLabel);
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE7E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.existing == null ? 'Add care task' : 'Edit care task',
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.problemName} dashboard uses these tasks for reminders, reports, and AI follow-up.',
                  style: const TextStyle(
                    color: Color(0xFF65736F),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in FlickoCareTaskType.values)
                      ChoiceChip(
                        selected: _type == type,
                        label: Text(type.label),
                        selectedColor: const Color(0xFFDDF4E6),
                        labelStyle: TextStyle(
                          color: _type == type
                              ? const Color(0xFF0B5B2D)
                              : const Color(0xFF65736F),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: _type == type
                              ? const Color(0xFF149447)
                              : const Color(0xFFE1E9E4),
                        ),
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _TaskField(
                  controller: _title,
                  label: 'Task name',
                  hint: _type.defaultTitle,
                ),
                const SizedBox(height: 10),
                _TaskField(
                  controller: _detail,
                  label: 'Details',
                  hint: 'Dose, target, food rule, note...',
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                _TaskField(controller: _time, label: 'Time', hint: '8:00 PM'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF149447),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      _saving ? 'Saving...' : 'Save task',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final existing = widget.existing;
    final now = widget.nowProvider();
    final task =
        existing?.copyWith(
          type: _type,
          title: _title.text.trim(),
          detail: _detail.text.trim(),
          timeLabel: _time.text.trim(),
          problemName: widget.problemName,
          updatedAt: now,
        ) ??
        FlickoCareTask.create(
          type: _type,
          title: _title.text,
          detail: _detail.text,
          timeLabel: _time.text,
          problemName: widget.problemName,
          now: now,
        );
    final saved = await widget.onSaveTask(task);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (saved) {
      Navigator.of(context).pop();
    }
  }
}

class _CareTaskTile extends StatelessWidget {
  const _CareTaskTile({
    required this.task,
    required this.doneToday,
    required this.onDoneToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final FlickoCareTask task;
  final bool doneToday;
  final VoidCallback onDoneToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = doneToday
        ? const Color(0xFF149447)
        : const Color(0xFF50635B);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: doneToday ? const Color(0xFFF0FBF3) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: doneToday ? const Color(0xFFCFEFDB) : const Color(0xFFE2EAE5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onDoneToggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                doneToday ? Icons.check_rounded : _iconForType(task.type),
                color: accent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    task.type.label,
                    if (task.timeLabel.trim().isNotEmpty) task.timeLabel,
                    if (task.detail.trim().isNotEmpty) task.detail,
                  ].join(' - '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF65736F),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Color(0xFF63756F),
            ),
            onSelected: (value) {
              if (value == 'done') {
                onDoneToggle();
              } else if (value == 'edit') {
                onEdit();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'done',
                child: Text(doneToday ? 'Undo done' : 'Mark done'),
              ),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FCF8),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2EAE5)),
      ),
      child: const Text(
        'No care tasks yet. Add medicine, meal, reading, water, sleep, or activity tasks.',
        style: TextStyle(
          color: Color(0xFF65736F),
          fontSize: 12.5,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompactTaskSummary extends StatelessWidget {
  const _CompactTaskSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FCF8),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2EAE5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: Color(0xFF149447),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count care ${count == 1 ? 'task is' : 'tasks are'} shown in today schedule.',
              style: const TextStyle(
                color: Color(0xFF65736F),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF0B5B2D)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B5B2D),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskField extends StatelessWidget {
  const _TaskField({
    required this.controller,
    required this.label,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7FBF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE0EBE5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE0EBE5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF149447), width: 1.4),
        ),
      ),
    );
  }
}

class _TaskIconBubble extends StatelessWidget {
  const _TaskIconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: const Color(0xFF149447).withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: const Color(0xFF149447), size: 21),
    );
  }
}

IconData _iconForType(FlickoCareTaskType type) {
  return switch (type) {
    FlickoCareTaskType.medicine => Icons.medication_outlined,
    FlickoCareTaskType.meal => Icons.restaurant_menu_rounded,
    FlickoCareTaskType.measurement => Icons.monitor_heart_outlined,
    FlickoCareTaskType.activity => Icons.directions_walk_rounded,
    FlickoCareTaskType.water => Icons.local_drink_outlined,
    FlickoCareTaskType.sleep => Icons.nightlight_round,
    FlickoCareTaskType.symptom => Icons.edit_note_rounded,
    FlickoCareTaskType.appointment => Icons.calendar_month_outlined,
    FlickoCareTaskType.custom => Icons.task_alt_rounded,
  };
}
