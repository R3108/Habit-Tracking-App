import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/habit_store.dart';
import 'habit_detail_screen.dart';

/// Habits that were archived rather than deleted.
///
/// Archiving exists so a habit can stop nagging without taking its history with
/// it — the insights screen counts only active habits, but everything is still
/// here to restore.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HabitScope.of(context);
    final archived = store.archivedHabits;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Archived habits')),
      body: archived.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing archived',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Long-press a habit to archive it instead of deleting '
                      'it. Its history is kept.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: archived.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final habit = archived[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: habit.color.withValues(alpha: 0.16),
                    child: Icon(habit.icon, size: 20, color: habit.color),
                  ),
                  title: Text(habit.title),
                  subtitle: Text(
                    '${habit.totalCompletions} completions · since '
                    '${DateFormat.yMMM().format(habit.createdAt)}',
                  ),
                  trailing: TextButton(
                    onPressed: () => store.setArchived(habit.id, false),
                    child: const Text('Restore'),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HabitDetailScreen(habitId: habit.id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
