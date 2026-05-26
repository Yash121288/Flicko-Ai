import 'package:flutter/material.dart';

import '../logs/health_log_entry.dart';
import '../management/flicko_care_task.dart';
import '../reminders/flicko_reminder_schedule.dart';
import '../reminders/flicko_saved_reminder.dart';
import 'management_care_tasks_section.dart';

class DashboardManagementView extends StatelessWidget {
  const DashboardManagementView({
    super.key,
    required this.problemName,
    required this.subtitle,
    required this.healthLogs,
    required this.savedReminders,
    required this.careTasks,
    required this.onAddLog,
    required this.onSendReminderNotification,
    required this.onSaveReminder,
    required this.onDeleteReminder,
    required this.onSaveCareTask,
    required this.onDeleteCareTask,
    required this.intakeSummary,
    required this.reminders,
    required this.dashboardNotes,
    required this.defaultMetricTitle,
    required this.defaultMetricIcon,
    required this.defaultMetricStatus,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  final String problemName;
  final String subtitle;
  final List<HealthLogEntry> healthLogs;
  final List<FlickoSavedReminder> savedReminders;
  final List<FlickoCareTask> careTasks;
  final ValueChanged<HealthLogEntry> onAddLog;
  final ValueChanged<String> onSendReminderNotification;
  final FlickoSavedReminderWriter onSaveReminder;
  final FlickoSavedReminderDeleter onDeleteReminder;
  final FlickoCareTaskWriter onSaveCareTask;
  final FlickoCareTaskDeleter onDeleteCareTask;
  final String intakeSummary;
  final List<String> reminders;
  final List<String> dashboardNotes;
  final String defaultMetricTitle;
  final IconData defaultMetricIcon;
  final String defaultMetricStatus;
  final DateTime Function() nowProvider;

  @override
  Widget build(BuildContext context) {
    final recentLogs = healthLogs.take(8).toList(growable: false);
    final scheduleItems = _buildScheduleItems(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _ManagementImageBubble(
                  asset: 'assets/images/dashboard/live_coach.png',
                  accent: Color(0xFF149447),
                  size: 52,
                  padding: 3,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Management',
                        style: TextStyle(
                          color: Color(0xFF0B372D),
                          fontSize: 22,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF65736F),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF149447),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _openLogSheet(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Log',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: 18),
                children: [
                  if (scheduleItems.isEmpty)
                    _EmptySchedulePanel(
                      onAddReminder: () => _pickReminderTime(
                        context,
                        'Time for your Flicko health check-in.',
                      ),
                      onAddTask: () => showCareTaskSheet(
                        context,
                        problemName: problemName,
                        onSaveTask: onSaveCareTask,
                        nowProvider: nowProvider,
                      ),
                    )
                  else
                    _ScheduleAgendaPanel(
                      items: scheduleItems,
                      onAddReminder: () => _pickReminderTime(
                        context,
                        'Time for your Flicko health check-in.',
                      ),
                      onAddTask: () => showCareTaskSheet(
                        context,
                        problemName: problemName,
                        onSaveTask: onSaveCareTask,
                        nowProvider: nowProvider,
                      ),
                    ),
                  const Text(
                    'Recent local logs',
                    style: TextStyle(
                      color: Color(0xFF0B372D),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (recentLogs.isEmpty)
                    _EmptyLogsCard(onAddLog: () => _openLogSheet(context))
                  else
                    for (final log in recentLogs) _HealthLogCard(log: log),
                  ManagementCareTasksSection(
                    problemName: problemName,
                    tasks: careTasks,
                    onSaveTask: onSaveCareTask,
                    onDeleteTask: onDeleteCareTask,
                    nowProvider: nowProvider,
                    showTaskList: careTasks.isEmpty || scheduleItems.isEmpty,
                  ),
                  if (scheduleItems.isEmpty)
                    _ReminderTemplatePanel(
                      problemName: problemName,
                      onCreate: (title, body) =>
                          _pickReminderTime(context, body, title: title),
                    ),
                ].separatedBy(const SizedBox(height: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ScheduleAgendaItem> _buildScheduleItems(BuildContext context) {
    final items = <_ScheduleAgendaItem>[];
    final savedReminderBodies = <String>{};
    final now = nowProvider();
    final nowMinutes = now.hour * 60 + now.minute;

    for (final reminder in FlickoSavedReminder.dedupe(
      savedReminders.where((entry) => entry.enabled),
    )) {
      final body = reminder.body.trim();
      final scheduleMinutes = reminder.hour * 60 + reminder.minute;
      savedReminderBodies.add(body.toLowerCase());
      items.add(
        _ScheduleAgendaItem(
          timeLabel: reminder.timeLabel,
          sortMinutes: scheduleMinutes,
          icon: Icons.alarm_on_rounded,
          title: reminder.title.trim().isEmpty
              ? 'Daily reminder'
              : reminder.title.trim(),
          body: body.isEmpty ? 'Flicko health check-in' : body,
          accent: const Color(0xFF149447),
          status: _scheduleStatusFor(scheduleMinutes, nowMinutes),
          actions: [
            _CardAction(
              label: 'Edit time',
              onTap: () => _pickReminderTime(
                context,
                reminder.body,
                title: reminder.title,
                existing: reminder,
              ),
            ),
            _CardAction(
              label: 'Delete',
              onTap: () => _deleteReminder(context, reminder),
            ),
          ],
        ),
      );
    }

    for (final task in careTasks.where((entry) => entry.enabled)) {
      final parsedTime = _parseScheduleTime(task.timeLabel);
      final title = task.title.trim();
      final taskDoneToday = task.isDoneOn(now);
      items.add(
        _ScheduleAgendaItem(
          timeLabel: parsedTime?.label ?? 'Any time',
          sortMinutes: parsedTime?.minutes ?? 1500,
          icon: _careTaskIcon(task.type),
          title: title.isEmpty ? task.type.defaultTitle : title,
          body: [
            task.type.label,
            if (task.detail.trim().isNotEmpty) task.detail.trim(),
            taskDoneToday ? 'Done today' : 'Pending today',
          ].join(' - '),
          accent: taskDoneToday
              ? const Color(0xFF149447)
              : const Color(0xFF168878),
          status: _scheduleStatusFor(
            parsedTime?.minutes,
            nowMinutes,
            completed: taskDoneToday,
            anyTime: parsedTime == null,
          ),
          completed: taskDoneToday,
          actions: [
            _CardAction(
              label: taskDoneToday ? 'Undo' : 'Done',
              onTap: () => _toggleCareTaskDone(context, task),
            ),
            _CardAction(
              label: 'Time',
              onTap: () => _pickCareTaskTime(context, task),
            ),
            _CardAction(
              label: 'Edit',
              onTap: () => showCareTaskSheet(
                context,
                problemName: problemName,
                onSaveTask: onSaveCareTask,
                existing: task,
                nowProvider: nowProvider,
              ),
            ),
            _CardAction(
              label: 'Delete',
              onTap: () => _deleteCareTask(context, task),
            ),
          ],
        ),
      );
    }

    for (final reminder in reminders) {
      final cleanReminder = reminder.trim();
      if (cleanReminder.isEmpty ||
          savedReminderBodies.contains(cleanReminder.toLowerCase())) {
        continue;
      }
      final parsedTime = _parseScheduleTime(cleanReminder);
      items.add(
        _ScheduleAgendaItem(
          timeLabel: parsedTime?.label ?? 'Needs time',
          sortMinutes: parsedTime?.minutes ?? 1600 + items.length,
          icon: Icons.notifications_active_outlined,
          title: 'AI reminder',
          body: cleanReminder,
          accent: const Color(0xFF2F9A66),
          status: _scheduleStatusFor(
            parsedTime?.minutes,
            nowMinutes,
            needsTime: parsedTime == null,
          ),
          actions: [
            _CardAction(
              label: 'Notify now',
              onTap: () {
                onSendReminderNotification(cleanReminder);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Flicko notification sent.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            _CardAction(
              label: parsedTime == null ? 'Set time' : 'Save daily',
              onTap: () => _pickReminderTime(context, cleanReminder),
            ),
          ],
        ),
      );
    }

    items.sort((left, right) {
      final timeSort = left.sortMinutes.compareTo(right.sortMinutes);
      if (timeSort != 0) {
        return timeSort;
      }
      return left.title.compareTo(right.title);
    });
    return items;
  }

  void _openLogSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          HealthLogSheet(problemName: problemName, onAddLog: onAddLog),
    );
  }

  Future<void> _pickReminderTime(
    BuildContext context,
    String reminder, {
    String title = 'Flicko daily reminder',
    FlickoSavedReminder? existing,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          existing?.timeOfDay ??
          FlickoReminderScheduleRequest.suggestedTimeFor(reminder),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF149447),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0B372D),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !context.mounted) {
      return;
    }

    final body = reminder.trim().isEmpty
        ? 'Time for your Flicko health check-in.'
        : reminder.trim();
    final savedReminder =
        existing?.copyWith(
          title: title,
          body: body,
          hour: picked.hour,
          minute: picked.minute,
          updatedAt: nowProvider(),
          enabled: true,
        ) ??
        FlickoSavedReminder.create(
          title: title,
          body: body,
          time: picked,
          problemName: problemName,
        );
    final scheduled = await onSaveReminder(savedReminder);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          scheduled
              ? 'Daily Flicko reminder set for ${savedReminder.timeLabel}.'
              : 'Reminder could not be scheduled on this device.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteReminder(
    BuildContext context,
    FlickoSavedReminder reminder,
  ) async {
    final deleted = await onDeleteReminder(reminder);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Reminder deleted.'
              : 'Reminder could not be deleted on this device.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleCareTaskDone(
    BuildContext context,
    FlickoCareTask task,
  ) async {
    final now = nowProvider();
    final next = task.isDoneOn(now)
        ? task.copyWith(clearCompleted: true, updatedAt: now)
        : task.copyWith(lastCompletedAt: now, updatedAt: now);
    final saved = await onSaveCareTask(next);
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

  Future<void> _pickCareTaskTime(
    BuildContext context,
    FlickoCareTask task,
  ) async {
    final parsedTime = _parseScheduleTime(task.timeLabel);
    final now = nowProvider();
    final picked = await showTimePicker(
      context: context,
      initialTime: parsedTime == null
          ? TimeOfDay(hour: now.hour, minute: now.minute)
          : TimeOfDay(
              hour: parsedTime.minutes ~/ 60,
              minute: parsedTime.minutes % 60,
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF149447),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0B372D),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final next = task.copyWith(
      timeLabel: _formatTimeLabel(picked.hour, picked.minute),
      updatedAt: nowProvider(),
    );
    final saved = await onSaveCareTask(next);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Care task moved to ${next.timeLabel}.'
              : 'Could not update care task time.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteCareTask(
    BuildContext context,
    FlickoCareTask task,
  ) async {
    final deleted = await onDeleteCareTask(task);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? 'Care task deleted.' : 'Could not delete care task.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ScheduleAgendaPanel extends StatefulWidget {
  const _ScheduleAgendaPanel({
    required this.items,
    required this.onAddReminder,
    required this.onAddTask,
  });

  final List<_ScheduleAgendaItem> items;
  final VoidCallback onAddReminder;
  final VoidCallback onAddTask;

  @override
  State<_ScheduleAgendaPanel> createState() => _ScheduleAgendaPanelState();
}

class _ScheduleAgendaPanelState extends State<_ScheduleAgendaPanel> {
  _ScheduleAgendaFilter _filter = _ScheduleAgendaFilter.all;

  @override
  Widget build(BuildContext context) {
    final doneItems = widget.items
        .where((item) => item.status.kind == _ScheduleStatusKind.done)
        .toList(growable: false);
    final activeItems = widget.items
        .where((item) => item.status.kind != _ScheduleStatusKind.done)
        .toList(growable: false);
    final dueNowItems = activeItems
        .where((item) => item.status.kind == _ScheduleStatusKind.dueNow)
        .toList(growable: false);
    final missedItems = activeItems
        .where((item) => item.status.kind == _ScheduleStatusKind.missed)
        .toList(growable: false);
    final doneCount = doneItems.length;
    final laterCount = activeItems
        .where(
          (item) =>
              item.status.kind == _ScheduleStatusKind.next ||
              item.status.kind == _ScheduleStatusKind.upcoming ||
              item.status.kind == _ScheduleStatusKind.open ||
              item.status.kind == _ScheduleStatusKind.needsTime,
        )
        .length;
    final filteredItems = switch (_filter) {
      _ScheduleAgendaFilter.all => activeItems,
      _ScheduleAgendaFilter.now => dueNowItems,
      _ScheduleAgendaFilter.missed => missedItems,
      _ScheduleAgendaFilter.later =>
        activeItems
            .where(
              (item) =>
                  item.status.kind == _ScheduleStatusKind.next ||
                  item.status.kind == _ScheduleStatusKind.upcoming ||
                  item.status.kind == _ScheduleStatusKind.open ||
                  item.status.kind == _ScheduleStatusKind.needsTime,
            )
            .toList(growable: false),
      _ScheduleAgendaFilter.completed => doneItems,
    };
    final groups = <_ScheduleAgendaGroup>[];
    for (final item in filteredItems) {
      if (groups.isEmpty || groups.last.timeLabel != item.timeLabel) {
        groups.add(_ScheduleAgendaGroup(item.timeLabel, [item]));
      } else {
        groups.last.items.add(item);
      }
    }
    final badgeLabel = switch (_filter) {
      _ScheduleAgendaFilter.all =>
        activeItems.isEmpty ? 'All done' : '${activeItems.length} active',
      _ScheduleAgendaFilter.now => '${dueNowItems.length} now',
      _ScheduleAgendaFilter.missed => '${missedItems.length} missed',
      _ScheduleAgendaFilter.later => '$laterCount later',
      _ScheduleAgendaFilter.completed => '${doneItems.length} done',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FFF9), Color(0xFFEAF7EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDEDE3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF149447).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF149447),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today schedule',
                      style: TextStyle(
                        color: Color(0xFF0B372D),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Reminders and care tasks grouped by time.',
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFDDEDE3)),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Color(0xFF0B5B2D),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ScheduleProgressStrip(
            doneCount: doneCount,
            focusCount: dueNowItems.length,
            missedCount: missedItems.length,
            laterCount: laterCount,
          ),
          const SizedBox(height: 12),
          _ScheduleFilterBar(
            selectedFilter: _filter,
            activeCount: activeItems.length,
            dueNowCount: dueNowItems.length,
            missedCount: missedItems.length,
            laterCount: laterCount,
            completedCount: doneCount,
            onSelected: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScheduleHeaderAction(
                label: 'Reminder',
                icon: Icons.add_alert_rounded,
                onTap: widget.onAddReminder,
              ),
              _ScheduleHeaderAction(
                label: 'Task',
                icon: Icons.add_task_rounded,
                onTap: widget.onAddTask,
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (_filter == _ScheduleAgendaFilter.all &&
              dueNowItems.isNotEmpty) ...[
            _FocusNowStrip(items: dueNowItems),
            const SizedBox(height: 15),
          ],
          if (_filter == _ScheduleAgendaFilter.all &&
              missedItems.isNotEmpty) ...[
            _MissedRecoveryStrip(items: missedItems),
            const SizedBox(height: 15),
          ],
          if (groups.isEmpty && _filter == _ScheduleAgendaFilter.all)
            _AllCaughtUpCard(doneCount: doneItems.length)
          else if (groups.isEmpty)
            _FilteredScheduleEmptyState(filter: _filter)
          else
            for (final group in groups) _ScheduleTimeBlock(group: group),
          if (_filter == _ScheduleAgendaFilter.all && doneItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            _CompletedTodayStrip(items: doneItems),
          ],
        ],
      ),
    );
  }
}

class _EmptySchedulePanel extends StatelessWidget {
  const _EmptySchedulePanel({
    required this.onAddReminder,
    required this.onAddTask,
  });

  final VoidCallback onAddReminder;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FFF9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDEDE3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF149447).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Color(0xFF149447),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No schedule yet',
                  style: TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Add the first time-based reminder for today.',
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onAddReminder,
                child: const Text('Reminder'),
              ),
              TextButton(onPressed: onAddTask, child: const Text('Task')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleTimeBlock extends StatelessWidget {
  const _ScheduleTimeBlock({required this.group});

  final _ScheduleAgendaGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              group.timeLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0B5B2D),
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (final item in group.items) _ScheduleItemCard(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({required this.item});

  final _ScheduleAgendaItem item;

  @override
  Widget build(BuildContext context) {
    final isDueNow = item.status.kind == _ScheduleStatusKind.dueNow;
    final isMissed = item.status.kind == _ScheduleStatusKind.missed;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.completed
            ? const Color(0xFFF0FBF3)
            : isDueNow
            ? const Color(0xFFF7FDF9)
            : isMissed
            ? const Color(0xFFFFFBF8)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.completed
              ? const Color(0xFFCFEFDB)
              : isDueNow
              ? const Color(0xFFD7F0DF)
              : isMissed
              ? const Color(0xFFF2D4C9)
              : const Color(0xFFE0EBE5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF10231D),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ScheduleStatusChip(status: item.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF65736F),
                        fontSize: 12,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.actions.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in item.actions)
                  _CompactActionButton(action: action),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleProgressStrip extends StatelessWidget {
  const _ScheduleProgressStrip({
    required this.doneCount,
    required this.focusCount,
    required this.missedCount,
    required this.laterCount,
  });

  final int doneCount;
  final int focusCount;
  final int missedCount;
  final int laterCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ScheduleSummaryChip(
          label: 'Done',
          count: doneCount,
          color: const Color(0xFF149447),
          background: const Color(0xFFEAF8EE),
        ),
        _ScheduleSummaryChip(
          label: 'Now',
          count: focusCount,
          color: const Color(0xFF0B5B2D),
          background: const Color(0xFFE9F7ED),
        ),
        _ScheduleSummaryChip(
          label: 'Missed',
          count: missedCount,
          color: const Color(0xFFB6452C),
          background: const Color(0xFFFFEEE7),
        ),
        _ScheduleSummaryChip(
          label: 'Later',
          count: laterCount,
          color: const Color(0xFF50635B),
          background: const Color(0xFFF1F6F3),
        ),
      ],
    );
  }
}

class _ScheduleSummaryChip extends StatelessWidget {
  const _ScheduleSummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.background,
  });

  final String label;
  final int count;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF30463F),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleFilterBar extends StatelessWidget {
  const _ScheduleFilterBar({
    required this.selectedFilter,
    required this.activeCount,
    required this.dueNowCount,
    required this.missedCount,
    required this.laterCount,
    required this.completedCount,
    required this.onSelected,
  });

  final _ScheduleAgendaFilter selectedFilter;
  final int activeCount;
  final int dueNowCount;
  final int missedCount;
  final int laterCount;
  final int completedCount;
  final ValueChanged<_ScheduleAgendaFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ScheduleFilterChip(
            label: 'All',
            count: activeCount,
            selected: selectedFilter == _ScheduleAgendaFilter.all,
            onTap: () => onSelected(_ScheduleAgendaFilter.all),
          ),
          const SizedBox(width: 8),
          _ScheduleFilterChip(
            label: 'Now',
            count: dueNowCount,
            selected: selectedFilter == _ScheduleAgendaFilter.now,
            onTap: () => onSelected(_ScheduleAgendaFilter.now),
          ),
          const SizedBox(width: 8),
          _ScheduleFilterChip(
            label: 'Missed',
            count: missedCount,
            selected: selectedFilter == _ScheduleAgendaFilter.missed,
            onTap: () => onSelected(_ScheduleAgendaFilter.missed),
          ),
          const SizedBox(width: 8),
          _ScheduleFilterChip(
            label: 'Later',
            count: laterCount,
            selected: selectedFilter == _ScheduleAgendaFilter.later,
            onTap: () => onSelected(_ScheduleAgendaFilter.later),
          ),
          const SizedBox(width: 8),
          _ScheduleFilterChip(
            label: 'Done',
            count: completedCount,
            selected: selectedFilter == _ScheduleAgendaFilter.completed,
            onTap: () => onSelected(_ScheduleAgendaFilter.completed),
          ),
        ],
      ),
    );
  }
}

class _ScheduleFilterChip extends StatelessWidget {
  const _ScheduleFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF149447) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFF149447)
                  : const Color(0xFFDDEDE3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0B5B2D),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFEAF7EE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF149447),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusNowStrip extends StatelessWidget {
  const _FocusNowStrip({required this.items});

  final List<_ScheduleAgendaItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD3EEDB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFDDF3E5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFF0B5B2D),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${items.length} ${items.length == 1 ? 'item needs' : 'items need'} attention now',
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in visibleItems) _FocusNowRow(item: item),
          if (items.length > visibleItems.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${items.length - visibleItems.length} more due now in schedule.',
                style: const TextStyle(
                  color: Color(0xFF3A5C49),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FocusNowRow extends StatelessWidget {
  const _FocusNowRow({required this.item});

  final _ScheduleAgendaItem item;

  @override
  Widget build(BuildContext context) {
    final primaryAction = _preferredAgendaAction(item.actions);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.timeLabel} - ${item.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0B372D),
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (primaryAction != null) ...[
            const SizedBox(width: 8),
            _CompactActionButton(action: primaryAction),
          ],
        ],
      ),
    );
  }
}

class _ScheduleStatusChip extends StatelessWidget {
  const _ScheduleStatusChip({required this.status});

  final _ScheduleStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.16)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MissedRecoveryStrip extends StatelessWidget {
  const _MissedRecoveryStrip({required this.items});

  final List<_ScheduleAgendaItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D1C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE8DF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: Color(0xFFB6452C),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${items.length} missed ${items.length == 1 ? 'item' : 'items'} today',
                  style: const TextStyle(
                    color: Color(0xFF5A2C20),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in visibleItems) _MissedRecoveryRow(item: item),
          if (items.length > visibleItems.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${items.length - visibleItems.length} more missed items in schedule.',
                style: const TextStyle(
                  color: Color(0xFF8A4B38),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllCaughtUpCard extends StatelessWidget {
  const _AllCaughtUpCard({required this.doneCount});

  final int doneCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7EDDE)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFDFF4E6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF149447),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              doneCount > 0
                  ? 'No active schedule items right now. Completed items are archived below.'
                  : 'No active schedule items right now.',
              style: const TextStyle(
                color: Color(0xFF335146),
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredScheduleEmptyState extends StatelessWidget {
  const _FilteredScheduleEmptyState({required this.filter});

  final _ScheduleAgendaFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (filter) {
      _ScheduleAgendaFilter.all => (
        Icons.check_circle_rounded,
        'All caught up',
        'No active schedule items right now.',
      ),
      _ScheduleAgendaFilter.now => (
        Icons.bolt_rounded,
        'Nothing due now',
        'Current items will appear here when their time window starts.',
      ),
      _ScheduleAgendaFilter.missed => (
        Icons.priority_high_rounded,
        'No missed items',
        'Anything overdue today will appear here.',
      ),
      _ScheduleAgendaFilter.later => (
        Icons.upcoming_rounded,
        'No later items',
        'Future reminders and open tasks will appear here.',
      ),
      _ScheduleAgendaFilter.completed => (
        Icons.done_all_rounded,
        'Nothing completed yet',
        'Finished items for today will appear here.',
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDEAE3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF7EE),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF149447), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF65736F),
                    fontSize: 11.8,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedTodayStrip extends StatelessWidget {
  const _CompletedTodayStrip({required this.items});

  final List<_ScheduleAgendaItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDEAE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F7EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.done_all_rounded,
                  color: Color(0xFF149447),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${items.length} completed ${items.length == 1 ? 'item' : 'items'} today',
                  style: const TextStyle(
                    color: Color(0xFF0B372D),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${item.timeLabel} - ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF61736B),
                  fontSize: 12.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (items.length > visibleItems.length)
            Text(
              '+${items.length - visibleItems.length} more completed items.',
              style: const TextStyle(
                color: Color(0xFF7A8A83),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _MissedRecoveryRow extends StatelessWidget {
  const _MissedRecoveryRow({required this.item});

  final _ScheduleAgendaItem item;

  @override
  Widget build(BuildContext context) {
    final primaryAction = _preferredAgendaAction(item.actions);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.timeLabel} - ${item.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF5A2C20),
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (primaryAction != null) ...[
            const SizedBox(width: 8),
            _CompactActionButton(action: primaryAction),
          ],
        ],
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({required this.action});

  final _CardAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F8F3),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            action.label,
            style: const TextStyle(
              color: Color(0xFF0B5B2D),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

_CardAction? _preferredAgendaAction(List<_CardAction> actions) {
  if (actions.isEmpty) {
    return null;
  }
  const priorityLabels = <String>[
    'Done',
    'Undo',
    'Notify now',
    'Set time',
    'Edit time',
  ];
  for (final label in priorityLabels) {
    for (final action in actions) {
      if (action.label == label) {
        return action;
      }
    }
  }
  return actions.first;
}

class _ScheduleHeaderAction extends StatelessWidget {
  const _ScheduleHeaderAction({
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDDEDE3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF149447), size: 16),
              const SizedBox(width: 6),
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

class _ScheduleAgendaItem {
  const _ScheduleAgendaItem({
    required this.timeLabel,
    required this.sortMinutes,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    required this.status,
    this.completed = false,
    this.actions = const <_CardAction>[],
  });

  final String timeLabel;
  final int sortMinutes;
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final _ScheduleStatus status;
  final bool completed;
  final List<_CardAction> actions;
}

class _ScheduleAgendaGroup {
  _ScheduleAgendaGroup(this.timeLabel, this.items);

  final String timeLabel;
  final List<_ScheduleAgendaItem> items;
}

class _ScheduleStatus {
  const _ScheduleStatus({
    required this.kind,
    required this.label,
    required this.color,
    required this.background,
  });

  final _ScheduleStatusKind kind;
  final String label;
  final Color color;
  final Color background;
}

enum _ScheduleStatusKind {
  done,
  missed,
  dueNow,
  next,
  upcoming,
  open,
  needsTime,
}

enum _ScheduleAgendaFilter { all, now, missed, later, completed }

_ScheduleStatus _scheduleStatusFor(
  int? scheduleMinutes,
  int nowMinutes, {
  bool completed = false,
  bool anyTime = false,
  bool needsTime = false,
}) {
  if (completed) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.done,
      label: 'Done',
      color: Color(0xFF149447),
      background: Color(0xFFE9F8EE),
    );
  }
  if (needsTime) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.needsTime,
      label: 'Needs time',
      color: Color(0xFFB85F00),
      background: Color(0xFFFFF3E2),
    );
  }
  if (anyTime || scheduleMinutes == null) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.open,
      label: 'Open',
      color: Color(0xFF168878),
      background: Color(0xFFE8F7F4),
    );
  }

  final delta = scheduleMinutes - nowMinutes;
  if (delta < -15) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.missed,
      label: 'Missed',
      color: Color(0xFFB6452C),
      background: Color(0xFFFFECE7),
    );
  }
  if (delta <= 15) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.dueNow,
      label: 'Due now',
      color: Color(0xFF0B5B2D),
      background: Color(0xFFE5F7EA),
    );
  }
  if (delta <= 60) {
    return const _ScheduleStatus(
      kind: _ScheduleStatusKind.next,
      label: 'Next',
      color: Color(0xFF0B5B2D),
      background: Color(0xFFEAF7EE),
    );
  }
  return const _ScheduleStatus(
    kind: _ScheduleStatusKind.upcoming,
    label: 'Upcoming',
    color: Color(0xFF50635B),
    background: Color(0xFFF1F6F3),
  );
}

class _ParsedScheduleTime {
  const _ParsedScheduleTime({required this.label, required this.minutes});

  final String label;
  final int minutes;
}

_ParsedScheduleTime? _parseScheduleTime(String value) {
  final source = value.trim();
  if (source.isEmpty) {
    return null;
  }
  final upper = source.toUpperCase().replaceAll('.', '');
  final meridianMatch = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\b',
  ).firstMatch(upper);
  if (meridianMatch != null) {
    final hourRaw = int.tryParse(meridianMatch.group(1) ?? '');
    final minute = int.tryParse(meridianMatch.group(2) ?? '0') ?? 0;
    final meridian = meridianMatch.group(3);
    if (hourRaw == null || hourRaw < 1 || hourRaw > 12 || minute > 59) {
      return null;
    }
    var hour = hourRaw % 12;
    if (meridian == 'PM') {
      hour += 12;
    }
    return _ParsedScheduleTime(
      label: _formatTimeLabel(hour, minute),
      minutes: hour * 60 + minute,
    );
  }

  final twentyFourHourMatch = RegExp(
    r'\b([01]?\d|2[0-3]):([0-5]\d)\b',
  ).firstMatch(upper);
  if (twentyFourHourMatch == null) {
    return null;
  }
  final hour = int.parse(twentyFourHourMatch.group(1)!);
  final minute = int.parse(twentyFourHourMatch.group(2)!);
  return _ParsedScheduleTime(
    label: _formatTimeLabel(hour, minute),
    minutes: hour * 60 + minute,
  );
}

String _formatTimeLabel(int hour, int minute) {
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  final displayMinute = minute.toString().padLeft(2, '0');
  return '$displayHour:$displayMinute $suffix';
}

IconData _careTaskIcon(FlickoCareTaskType type) {
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

class HealthLogSheet extends StatefulWidget {
  const HealthLogSheet({
    super.key,
    required this.problemName,
    required this.onAddLog,
  });

  final String problemName;
  final ValueChanged<HealthLogEntry> onAddLog;

  @override
  State<HealthLogSheet> createState() => _HealthLogSheetState();
}

class _HealthLogSheetState extends State<HealthLogSheet> {
  late HealthLogType _type;
  final TextEditingController _value = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = _typesForProblem(widget.problemName).first;
    _unit.text = _type.defaultUnit;
  }

  @override
  void dispose() {
    _value.dispose();
    _unit.dispose();
    _note.dispose();
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
              const Text(
                'Add health log',
                style: TextStyle(
                  color: Color(0xFF0B372D),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.problemName} plan uses these logs for dashboard and reports.',
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
                  for (final type in HealthLogType.values)
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
                      onSelected: (_) {
                        setState(() {
                          _type = type;
                          _unit.text = type.defaultUnit;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _SheetField(
                      controller: _value,
                      label: 'Value',
                      hint: _valueHint(_type),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetField(
                      controller: _unit,
                      label: 'Unit',
                      hint: _type.defaultUnit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SheetField(
                controller: _note,
                label: 'Note',
                hint: 'What happened? food, symptoms, timing...',
                minLines: 2,
                maxLines: 3,
              ),
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
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text(
                    'Save log',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (_value.text.trim().isEmpty && _note.text.trim().isEmpty) {
      return;
    }
    widget.onAddLog(
      HealthLogEntry.create(
        type: _type,
        title: _type.defaultTitle,
        value: _value.text,
        unit: _unit.text,
        note: _note.text,
        problemName: widget.problemName,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
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

class _ReminderTemplatePanel extends StatelessWidget {
  const _ReminderTemplatePanel({
    required this.problemName,
    required this.onCreate,
  });

  final String problemName;
  final void Function(String title, String body) onCreate;

  @override
  Widget build(BuildContext context) {
    final templates = _reminderTemplatesForProblem(problemName);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FCF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDEDE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFF149447),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Reminder templates',
                style: TextStyle(
                  color: Color(0xFF0B372D),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final template in templates)
                _TemplateChip(
                  template: template,
                  onTap: () => onCreate(template.title, template.body),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.template, required this.onTap});

  final _ReminderTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCECE3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(template.icon, color: const Color(0xFF149447), size: 16),
              const SizedBox(width: 6),
              Text(
                template.title,
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

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    this.action = '',
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF10231D),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF51625C),
                    fontSize: 12.7,
                    height: 1.36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (action.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _MiniAction(label: action, onTap: onTap),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction {
  const _CardAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

class _HealthLogCard extends StatelessWidget {
  const _HealthLogCard({required this.log});

  final HealthLogEntry log;

  @override
  Widget build(BuildContext context) {
    return _ManagementCard(
      icon: _iconForType(log.type),
      title: log.title,
      body: [
        if (log.valueText.trim().isNotEmpty) log.valueText,
        if (log.note.trim().isNotEmpty) log.note,
        _timeLabel(log.createdAt),
      ].join('\n'),
      accent: const Color(0xFF149447),
    );
  }
}

class _EmptyLogsCard extends StatelessWidget {
  const _EmptyLogsCard({required this.onAddLog});

  final VoidCallback onAddLog;

  @override
  Widget build(BuildContext context) {
    return _ManagementCard(
      icon: Icons.add_chart_rounded,
      title: 'No local logs yet',
      body:
          'Add weight, meal, BP, sugar, water, sleep, mood, medicine, symptom, or activity logs. Flicko will use these to personalize the dashboard.',
      accent: const Color(0xFF149447),
      action: 'Add first log',
      onTap: onAddLog,
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0B5B2D),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagementImageBubble extends StatelessWidget {
  const _ManagementImageBubble({
    required this.asset,
    this.accent = const Color(0xFF149447),
    this.size = 48,
    this.padding = 4,
  });

  final String asset;
  final Color accent;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(size * 0.36),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stackTrace) => Container(
            color: accent.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: Icon(Icons.image_outlined, color: accent, size: size * 0.4),
          ),
        ),
      ),
    );
  }
}

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    final result = <Widget>[];
    for (var i = 0; i < length; i++) {
      if (i > 0) {
        result.add(separator);
      }
      result.add(this[i]);
    }
    return result;
  }
}

List<HealthLogType> _typesForProblem(String problemName) {
  final normalized = problemName.toLowerCase();
  if (normalized.contains('diabetes')) {
    return const [
      HealthLogType.glucose,
      HealthLogType.meal,
      HealthLogType.medicine,
      HealthLogType.steps,
      HealthLogType.symptom,
    ];
  }
  if (normalized.contains('blood pressure') || normalized.contains('heart')) {
    return const [
      HealthLogType.bloodPressure,
      HealthLogType.medicine,
      HealthLogType.activity,
      HealthLogType.symptom,
      HealthLogType.sleep,
    ];
  }
  if (normalized.contains('weight')) {
    return const [
      HealthLogType.weight,
      HealthLogType.meal,
      HealthLogType.water,
      HealthLogType.steps,
      HealthLogType.sleep,
    ];
  }
  if (normalized.contains('sleep')) {
    return const [
      HealthLogType.sleep,
      HealthLogType.mood,
      HealthLogType.activity,
      HealthLogType.symptom,
    ];
  }
  if (normalized.contains('stress') || normalized.contains('mood')) {
    return const [
      HealthLogType.mood,
      HealthLogType.sleep,
      HealthLogType.activity,
      HealthLogType.symptom,
    ];
  }
  return const [
    HealthLogType.symptom,
    HealthLogType.meal,
    HealthLogType.water,
    HealthLogType.activity,
    HealthLogType.medicine,
  ];
}

String _valueHint(HealthLogType type) {
  return switch (type) {
    HealthLogType.weight => '56',
    HealthLogType.glucose => '118',
    HealthLogType.bloodPressure => '122/78',
    HealthLogType.meal => '82',
    HealthLogType.water => '2.1',
    HealthLogType.steps => '7842',
    HealthLogType.sleep => '7.5',
    HealthLogType.mood => '7',
    HealthLogType.medicine => 'Done / missed',
    HealthLogType.symptom => '3',
    HealthLogType.activity => '20',
  };
}

IconData _iconForType(HealthLogType type) {
  return switch (type) {
    HealthLogType.weight => Icons.monitor_weight_outlined,
    HealthLogType.glucose => Icons.water_drop_outlined,
    HealthLogType.bloodPressure => Icons.speed_rounded,
    HealthLogType.meal => Icons.restaurant_menu_rounded,
    HealthLogType.water => Icons.local_drink_outlined,
    HealthLogType.steps => Icons.directions_walk_rounded,
    HealthLogType.sleep => Icons.nightlight_round,
    HealthLogType.mood => Icons.mood_outlined,
    HealthLogType.medicine => Icons.medication_outlined,
    HealthLogType.symptom => Icons.edit_note_rounded,
    HealthLogType.activity => Icons.directions_run_rounded,
  };
}

String _timeLabel(DateTime value) {
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.inMinutes < 1) {
    return 'Just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} min ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} hr ago';
  }
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
}

class _ReminderTemplate {
  const _ReminderTemplate({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}

List<_ReminderTemplate> _reminderTemplatesForProblem(String problemName) {
  final normalized = problemName.toLowerCase();
  final templates = <_ReminderTemplate>[
    const _ReminderTemplate(
      title: 'Water',
      body: 'Drink water and log your hydration.',
      icon: Icons.local_drink_outlined,
    ),
    const _ReminderTemplate(
      title: 'Meal photo',
      body: 'Upload your meal photo so Flicko can score it.',
      icon: Icons.camera_alt_outlined,
    ),
    const _ReminderTemplate(
      title: 'Medicine',
      body: 'Take your medicine and mark it done.',
      icon: Icons.medication_outlined,
    ),
    const _ReminderTemplate(
      title: 'Sleep',
      body: 'Start your sleep wind-down routine.',
      icon: Icons.nightlight_round,
    ),
  ];

  if (normalized.contains('diabetes')) {
    return [
      const _ReminderTemplate(
        title: 'Sugar check',
        body: 'Check blood sugar and log the reading.',
        icon: Icons.water_drop_outlined,
      ),
      ...templates,
    ];
  }
  if (normalized.contains('blood pressure') || normalized.contains('heart')) {
    return [
      const _ReminderTemplate(
        title: 'BP check',
        body: 'Measure blood pressure and log the reading.',
        icon: Icons.speed_rounded,
      ),
      const _ReminderTemplate(
        title: 'Evening walk',
        body: 'Take a light walk and log activity.',
        icon: Icons.directions_walk_rounded,
      ),
      ...templates.take(3),
    ];
  }
  if (normalized.contains('weight')) {
    return [
      const _ReminderTemplate(
        title: 'Weigh-in',
        body: 'Do your morning weigh-in and log the value.',
        icon: Icons.monitor_weight_outlined,
      ),
      ...templates,
    ];
  }
  if (normalized.contains('sleep')) {
    return [
      templates.last,
      const _ReminderTemplate(
        title: 'Wake log',
        body: 'Log sleep duration and morning energy.',
        icon: Icons.bedtime_outlined,
      ),
      const _ReminderTemplate(
        title: 'No caffeine',
        body: 'Avoid late caffeine and start a calmer evening.',
        icon: Icons.coffee_outlined,
      ),
    ];
  }
  return templates;
}
