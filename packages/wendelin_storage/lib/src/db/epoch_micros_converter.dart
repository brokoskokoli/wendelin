import 'package:drift/drift.dart';

/// Stores instants as microseconds since the epoch (UTC instant, exact and
/// comparable as integers); reads them back as local [DateTime]s.
final class EpochMicrosConverter extends TypeConverter<DateTime, int> {
  /// Creates the converter.
  const EpochMicrosConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMicrosecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.microsecondsSinceEpoch;
}

/// Shared converter instance (referenced by generated code).
const epochMicros = EpochMicrosConverter();
