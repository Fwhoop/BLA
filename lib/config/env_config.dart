import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime API base URL. Call [dotenv.load()] in main() before accessing.
/// Fallback used when .env is not loaded or API_URL is missing.
String get apiBaseUrl {
  final url = dotenv.env['API_URL']?.trim();
  if (url != null && url.isNotEmpty) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
  return 'http://127.0.0.1:8000';
}
