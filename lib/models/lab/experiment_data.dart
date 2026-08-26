import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'experiment.dart';

/// Current on-disk schema version for the experiment log.
///
/// Versioned separately from the habit schema, like the trackers are: an
/// experiment is a small, self-contained record and its shape should be able to
/// change without touching the envelope a decade of habit history is stamped
/// with.
///
/// - v1: the original shape.
const int kExperimentSchemaVersion = 1;

String encodeExperiments(List<Experiment> experiments) =>
    jsonEncode(<String, dynamic>{
      'version': kExperimentSchemaVersion,
      'experiments': experiments.map((e) => e.toJson()).toList(),
    });

/// Decodes the envelope written by [encodeExperiments].
///
/// Null for anything unreadable, never a throw — same contract as the habit and
/// tracker decoders, and for the same reason.
List<Experiment>? decodeExperiments(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > kExperimentSchemaVersion) {
      debugPrint(
        'experiment data is schema v$version, this build reads '
        'v$kExperimentSchemaVersion',
      );
      return null;
    }

    final list = decoded['experiments'];
    if (list is! List) return null;

    return <Experiment>[
      for (final item in list)
        if (item is Map) Experiment.fromJson(Map<String, dynamic>.from(item)),
    ];
  } on FormatException catch (error) {
    debugPrint('could not decode experiment data: $error');
    return null;
  }
}
