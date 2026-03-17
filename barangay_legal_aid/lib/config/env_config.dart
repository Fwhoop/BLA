import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime API base URL.
/// Priority: --dart-define=API_URL → .env file → localhost fallback
String get apiBaseUrl {
  // dart-define is baked in at compile time — most reliable on web
  const defined = String.fromEnvironment('API_URL');
  if (defined.isNotEmpty && defined.startsWith('http')) {
    return defined.endsWith('/') ? defined.substring(0, defined.length - 1) : defined;
  }
  // fallback: .env file (used in local dev)
  final url = dotenv.env['API_URL']?.trim();
  if (url != null && url.isNotEmpty && url.startsWith('http')) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
  return 'http://127.0.0.1:8000';
}
