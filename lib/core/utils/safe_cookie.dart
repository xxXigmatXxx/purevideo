import 'dart:io';

/// Lenient cookie that never throws on characters dart:io's [Cookie] rejects
/// (quotes, commas, non-ASCII ...). Sites such as Ekino/Cloudflare set such
/// values, which caused "Invalid cookie" FormatExceptions on login.
class RawCookie implements Cookie {
  @override
  String name;
  @override
  String value;
  @override
  DateTime? expires;
  @override
  int? maxAge;
  @override
  String? domain;
  @override
  String? path;
  @override
  bool secure = false;
  @override
  bool httpOnly = false;

  RawCookie(this.name, this.value);

  /// Parses "name=value" or "name=value; Path=/; HttpOnly" (only the first
  /// pair is used). Returns null when there is no usable name.
  static RawCookie? parse(String raw) {
    final first = raw.split(';').first.trim();
    final i = first.indexOf('=');
    if (i <= 0) return null;
    final n = first.substring(0, i).trim();
    if (n.isEmpty) return null;
    return RawCookie(n, first.substring(i + 1).trim());
  }

  @override
  String toString() => '$name=$value';
}