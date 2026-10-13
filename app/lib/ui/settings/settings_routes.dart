import '../routes.dart';

/// The settings page where the missing setup of integration [id] happens,
/// or `null` if „Einrichten“ asks for a permission instead.
String? setupPageFor(String id) => switch (id) {
  'lists' => AppRoutes.lists,
  'web' => AppRoutes.webSearch,
  _ => null,
};
