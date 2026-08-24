import 'package:flutter/foundation.dart';

import '../habit.dart';

/// One sitting with a book.
///
/// Pages *and* minutes, because either alone is close to useless: pages say
/// nothing about a dense book, minutes say nothing about a book you fell asleep
/// over, and the two together give a reading speed that turns "I'm on page 140"
/// into "you'll finish on the 14th".
@immutable
class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.day,
    required this.book,
    required this.pages,
    required this.minutes,
  });

  final String id;
  final DateTime day;

  /// Free text. Deliberately not an entity with an id: making the user create a
  /// "book" before they can log ten minutes is how a reading log goes unused.
  /// The title is matched case-insensitively when sessions are grouped.
  final String book;

  final int pages;
  final int minutes;

  /// Pages an hour for this sitting, or null when it was untimed.
  double? get pagesPerHour {
    if (minutes <= 0 || pages <= 0) return null;
    return pages / (minutes / 60);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'day': encodeDay(day),
    'book': book,
    'pages': pages,
    'minutes': minutes,
  };

  static ReadingSession? fromJson(Map<String, dynamic> json) {
    final day = decodeDay(json['day'] as String?);
    if (day == null) return null;

    return ReadingSession(
      id: json['id'] as String? ?? 'reading-${day.millisecondsSinceEpoch}',
      day: day,
      book: json['book'] as String? ?? '',
      pages: ((json['pages'] as num?)?.toInt() ?? 0).clamp(0, 100000),
      minutes: ((json['minutes'] as num?)?.toInt() ?? 0).clamp(0, 1440),
    );
  }
}

/// A book the user has told us the length of, so progress can be projected.
typedef BookLength = ({String book, int totalPages});

/// What the reading log adds up to.
@immutable
class ReadingInsights {
  const ReadingInsights._({
    required this.minutesToday,
    required this.pagesToday,
    required this.minutesThisWeek,
    required this.pagesThisWeek,
    required this.pagesPerHour,
    required this.currentBook,
    required this.pagesInCurrentBook,
    required this.sessions,
    required this.daysRead,
  });

  final int minutesToday;
  final int pagesToday;
  final int minutesThisWeek;
  final int pagesThisWeek;

  /// Reading speed across every timed session in the window, or null when
  /// nothing has been timed yet.
  ///
  /// Pooled over sessions rather than averaged over their individual speeds: a
  /// five-minute sitting should not weigh as heavily as an hour, and averaging
  /// the rates lets it.
  final double? pagesPerHour;

  /// The book of the most recent session, or null when nothing is on the go.
  final String? currentBook;

  /// Pages logged against [currentBook] across the whole log, not just the
  /// window — progress through a book is not a thirty-day question.
  final int pagesInCurrentBook;

  final int sessions;

  /// Distinct days with a session, for the "read on 5 of 7 days" line.
  final int daysRead;

  static const int windowDays = 30;

  /// Days to finish [totalPages] of the current book at the current pace.
  ///
  /// Null when the pace or the length is unknown, or when the book is already
  /// finished. Uses pages per *day* rather than per hour: how fast somebody
  /// reads matters far less to a finish date than whether they open the book.
  int? daysToFinish(int totalPages) {
    final remaining = totalPages - pagesInCurrentBook;
    if (remaining <= 0) return null;

    final perDay = pagesThisWeek / 7;
    if (perDay <= 0) return null;
    return (remaining / perDay).ceil();
  }

  factory ReadingInsights.from(
    List<ReadingSession> sessions, {
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final windowStart = addDays(today, -(window - 1));
    final weekStart = addDays(today, -6);

    var minutesToday = 0;
    var pagesToday = 0;
    var minutesThisWeek = 0;
    var pagesThisWeek = 0;
    // Speed is pooled over timed sittings only. Counting the pages of an
    // untimed session against the minutes of the timed ones would inflate the
    // rate without limit.
    var timedPages = 0;
    var timedMinutes = 0;
    var inWindow = 0;
    final days = <DateTime>{};

    ReadingSession? latest;

    for (final session in sessions) {
      if (latest == null || !session.day.isBefore(latest.day)) latest = session;

      if (session.day.isBefore(windowStart) || session.day.isAfter(today)) {
        continue;
      }
      inWindow++;
      days.add(session.day);
      if (session.minutes > 0 && session.pages > 0) {
        timedPages += session.pages;
        timedMinutes += session.minutes;
      }

      if (!session.day.isBefore(weekStart)) {
        minutesThisWeek += session.minutes;
        pagesThisWeek += session.pages;
      }
      if (session.day == today) {
        minutesToday += session.minutes;
        pagesToday += session.pages;
      }
    }

    final book = latest?.book.trim();
    final currentBook = book == null || book.isEmpty ? null : book;

    var pagesInBook = 0;
    if (currentBook != null) {
      final key = currentBook.toLowerCase();
      for (final session in sessions) {
        if (session.book.trim().toLowerCase() == key) {
          pagesInBook += session.pages;
        }
      }
    }

    return ReadingInsights._(
      minutesToday: minutesToday,
      pagesToday: pagesToday,
      minutesThisWeek: minutesThisWeek,
      pagesThisWeek: pagesThisWeek,
      pagesPerHour: timedMinutes == 0
          ? null
          : timedPages / (timedMinutes / 60),
      currentBook: currentBook,
      pagesInCurrentBook: pagesInBook,
      sessions: inWindow,
      daysRead: days.length,
    );
  }
}
