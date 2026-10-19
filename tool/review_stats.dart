// Quote „beim ersten Review sauber“ aus den Urteilsdateien des Reviewers.
//
//   dart run tool/review_stats.dart [ordner]   (Standard ../james-wt/handoff)
import 'dart:io';

import 'src/review_stats.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? '../james-wt/handoff' : args.first;
  if (!Directory(dir).existsSync()) {
    stderr.writeln('Ordner fehlt: $dir');
    exitCode = 1;
    return;
  }
  stdout.writeln(summarizeReviews(readReviews(dir)));
}
