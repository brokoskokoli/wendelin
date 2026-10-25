// Quote „beim ersten Review sauber“ aus den Urteilsdateien des Reviewers.
//
//   dart run tool/review_stats.dart [ordner]
//
// Standard: `reviews` neben dem Hauptcheckout (`<Hauptcheckout>/../james-wt/reviews`),
// unabhängig vom Arbeitsverzeichnis, auch aus einem Worktree.
import 'dart:io';

import 'src/review_stats.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? defaultReviewsDir(_git) : args.first;
  if (!Directory(dir).existsSync()) {
    stderr.writeln('Ordner fehlt: $dir');
    exitCode = 1;
    return;
  }
  stdout.writeln(summarizeReviews(readReviews(dir)));
}

String? _git(List<String> a) {
  final r = Process.runSync('git', a);
  return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
}
