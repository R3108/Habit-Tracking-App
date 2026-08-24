import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../models/trackers/reading_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Reading: pages, pace, and when the current book will actually be finished.
class ReadingScreen extends StatelessWidget {
  const ReadingScreen({super.key});

  static const _kind = TrackerKind.reading;

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());
    final insights = ReadingInsights.from(store.data.reading);

    final week = <({DateTime day, num value})>[
      for (var age = 6; age >= 0; age--)
        (
          day: addDays(today, -age),
          value: store.data.reading
              .where((s) => s.day == addDays(today, -age))
              .fold<int>(0, (sum, s) => sum + s.minutes),
        ),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSession(context, store, today, insights),
        backgroundColor: _kind.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Log reading'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(_kind.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
            sliver: SliverList.list(
              children: [
                Center(
                  child: GoalRing(
                    progress: insights.minutesToday / goals.readingMinutes,
                    value: formatMinutes(insights.minutesToday),
                    caption: 'of ${formatMinutes(goals.readingMinutes)} today',
                    footnote: insights.pagesToday > 0
                        ? '${insights.pagesToday} pages'
                        : null,
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 24),
                if (insights.currentBook case final book?) ...[
                  _CurrentBookCard(
                    book: book,
                    pagesRead: insights.pagesInCurrentBook,
                    totalPages: store.bookLength(book),
                    daysToFinish: store.bookLength(book) == null
                        ? null
                        : insights.daysToFinish(store.bookLength(book)!),
                    onSetLength: () => _setBookLength(context, store, book),
                  ),
                  const SizedBox(height: 16),
                ],
                TrackerCard(
                  title: 'Last 7 days',
                  child: MiniBars(
                    values: week,
                    goal: goals.readingMinutes,
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 16),
                if (insights.sessions == 0)
                  const TrackerCard(
                    child: TrackerEmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Nothing logged yet',
                      message:
                          'Log a sitting with the pages and the minutes. Both '
                          'together give a reading speed, which turns "I am on '
                          'page 140" into a finish date.',
                    ),
                  )
                else
                  TrackerCard(
                    title: 'Last 30 days',
                    child: Column(
                      children: [
                        TrackerStatRow(
                          icon: Icons.speed,
                          label: 'Reading speed',
                          value: insights.pagesPerHour == null
                              ? 'Not timed yet'
                              : '${insights.pagesPerHour!.round()} pages/hour',
                        ),
                        TrackerStatRow(
                          icon: Icons.auto_stories_outlined,
                          label: 'Pages this week',
                          value: '${insights.pagesThisWeek}',
                        ),
                        TrackerStatRow(
                          icon: Icons.event_available_outlined,
                          label: 'Days read',
                          value: '${insights.daysRead}',
                        ),
                        TrackerStatRow(
                          icon: Icons.timer_outlined,
                          label: 'Time this week',
                          value: formatMinutes(insights.minutesThisWeek),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                _SessionList(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSession(
    BuildContext context,
    TrackerStore store,
    DateTime today,
    ReadingInsights insights,
  ) async {
    final draft = await showModalBottomSheet<
      ({String book, int pages, int minutes})
    >(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => _SessionEditor(suggestedBook: insights.currentBook),
    );
    if (draft == null) return;

    store.addReading(
      day: today,
      book: draft.book,
      pages: draft.pages,
      minutes: draft.minutes,
    );
  }

  Future<void> _setBookLength(
    BuildContext context,
    TrackerStore store,
    String book,
  ) async {
    final controller = TextEditingController(
      text: (store.bookLength(book) ?? '').toString(),
    );

    final pages = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('How long is it?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total pages in "$book". Used to estimate when you will '
                'finish at your current pace.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pages'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()) ?? 0,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (pages != null) store.setBookLength(book, pages);
  }
}

/// Progress through whatever is on the go, and when it will be done.
class _CurrentBookCard extends StatelessWidget {
  const _CurrentBookCard({
    required this.book,
    required this.pagesRead,
    required this.totalPages,
    required this.daysToFinish,
    required this.onSetLength,
  });

  final String book;
  final int pagesRead;
  final int? totalPages;
  final int? daysToFinish;
  final VoidCallback onSetLength;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = totalPages;

    return TrackerCard(
      title: 'Currently reading',
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Set total pages',
        onPressed: onSetLength,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: TrackerKind.reading.color,
            ),
          ),
          const SizedBox(height: 10),
          if (total == null) ...[
            Text(
              '$pagesRead pages logged. Add the book\'s length to get a '
              'finish date.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pagesRead / total).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(TrackerKind.reading.color),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$pagesRead of $total pages · '
              '${((pagesRead / total) * 100).clamp(0, 100).round()}%',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              switch (daysToFinish) {
                null when pagesRead >= total => 'Finished — nice.',
                null =>
                  'Read a little this week and this will project a finish date.',
                final days =>
                  'At this week\'s pace you finish in $days day'
                      '${days == 1 ? '' : 's'} — around '
                      '${DateFormat.MMMd().format(addDays(dateOnly(DateTime.now()), days))}.',
              },
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.store});

  final TrackerStore store;

  @override
  Widget build(BuildContext context) {
    final sessions = store.data.reading.reversed.take(10).toList();
    if (sessions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return TrackerCard(
      title: 'Recent sittings',
      child: Column(
        children: [
          for (final session in sessions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: TrackerKind.reading.color.withValues(
                  alpha: 0.16,
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 20,
                  color: TrackerKind.reading.color,
                ),
              ),
              title: Text(
                session.book.isEmpty ? 'Untitled' : session.book,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${DateFormat.MMMd().format(session.day)} · '
                '${session.pages} pages · ${formatMinutes(session.minutes)}',
              ),
              trailing: IconButton(
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                tooltip: 'Remove',
                onPressed: () {
                  final removed = store.removeReading(session.id);
                  if (removed == null) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Sitting removed'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => store.insertReading(
                            removed.index,
                            removed.session,
                          ),
                        ),
                      ),
                    );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({this.suggestedBook});

  final String? suggestedBook;

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late final _bookController = TextEditingController(
    text: widget.suggestedBook ?? '',
  );
  final _pagesController = TextEditingController();
  var _minutes = 30;

  @override
  void dispose() {
    _bookController.dispose();
    _pagesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log a sitting', style: textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextField(
                controller: _bookController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Book',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pagesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pages read',
                  prefixIcon: Icon(Icons.auto_stories_outlined),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Time: ${formatMinutes(_minutes)}',
                style: textTheme.labelLarge,
              ),
              Slider(
                value: _minutes.toDouble(),
                min: 5,
                max: 180,
                divisions: 35,
                label: formatMinutes(_minutes),
                activeColor: TrackerKind.reading.color,
                onChanged: (value) =>
                    setState(() => _minutes = value.round()),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TrackerKind.reading.color,
                  ),
                  onPressed: () => Navigator.pop(context, (
                    book: _bookController.text.trim(),
                    pages: int.tryParse(_pagesController.text.trim()) ?? 0,
                    minutes: _minutes,
                  )),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
