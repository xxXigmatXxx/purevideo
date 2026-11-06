import 'dart:convert';

Map<String, dynamic>? extractBootstrapData(dynamic rawResponseData) {
  if (rawResponseData == null) return null;
  final responseData = rawResponseData.toString();
  final markerIdx = responseData.indexOf('window.bootstrapData');
  if (markerIdx == -1) return null;
  final braceStart = responseData.indexOf('{', markerIdx);
  if (braceStart == -1) return null;
  final scriptEnd = responseData.indexOf('</script>', braceStart);
  if (scriptEnd == -1) return null;
  var braceEnd = responseData.lastIndexOf('};', scriptEnd);
  if (braceEnd == -1 || braceEnd <= braceStart) {
    braceEnd = responseData.lastIndexOf('}', scriptEnd);
    if (braceEnd == -1 || braceEnd <= braceStart) return null;
  } else {
    braceEnd += 1; // include closing '}'
  }
  try {
    final jsonString = responseData.substring(braceStart, braceEnd);
    final data = jsonDecode(jsonString);
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    return null;
  }
}

String generateSlug(String title) {
  const Map<String, String> polishChars = {
    'ą': 'a',
    'Ą': 'a',
    'ć': 'c',
    'Ć': 'c',
    'ę': 'e',
    'Ę': 'e',
    'ł': 'l',
    'Ł': 'l',
    'ń': 'n',
    'Ń': 'n',
    'ó': 'o',
    'Ó': 'o',
    'ś': 's',
    'Ś': 's',
    'ź': 'z',
    'Ź': 'z',
    'ż': 'z',
    'Ż': 'z',
  };

  String slug = title;

  polishChars.forEach((polish, replacement) {
    slug = slug.replaceAll(polish, replacement);
  });

  slug = slug.toLowerCase();
  slug = slug.replaceAll(RegExp(r'[:\.\*\(\)\[\]{}]'), ' ');
  slug = slug.replaceAll(RegExp(r'[^\w\s-]'), ' ');
  slug = slug.replaceAll(RegExp(r'\s+'), ' ');
  slug = slug.trim();
  slug = slug.replaceAll(' ', '-');
  slug = slug.replaceAll(RegExp(r'-+'), '-');
  slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');

  return slug;
}
