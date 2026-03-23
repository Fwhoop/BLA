/// Philippine phone number normalization utilities.
library;

/// Normalizes a Philippine phone number to E.164 format (+63XXXXXXXXX).
///
/// Accepts:
///   09559952920   → +639559952920
///   9559952920    → +639559952920
///   639559952920  → +639559952920
///   +639559952920 → +639559952920  (unchanged)
String normalizePhPhone(String phone) {
  // Strip spaces, dashes, parentheses
  phone = phone.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');

  if (phone.startsWith('+63')) return phone;           // already E.164
  if (phone.startsWith('63') && phone.length >= 11) return '+$phone';
  if (phone.startsWith('0') && phone.length == 11) return '+63${phone.substring(1)}';
  if (!phone.startsWith('0') && phone.length == 10) return '+63$phone';

  return phone; // unrecognised format — return as-is
}

/// Returns true if [phone] looks like a valid PH mobile number
/// (after normalization it should be +639XXXXXXXXX, 13 chars).
bool isValidPhPhone(String phone) {
  final normalized = normalizePhPhone(phone);
  return RegExp(r'^\+639\d{9}$').hasMatch(normalized);
}
