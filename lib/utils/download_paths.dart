final RegExp _invalidWindowsFileNameCharacters = RegExp(
  r'[<>:"/\\|?*\x00-\x1F]',
);

const Set<String> _reservedWindowsFileNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

String sanitizeDownloadFileName(String value, {String fallback = 'download'}) {
  var sanitized = value
      .replaceAll(_invalidWindowsFileNameCharacters, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');

  if (sanitized.isEmpty) {
    sanitized = fallback
        .replaceAll(_invalidWindowsFileNameCharacters, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
  }

  if (sanitized.isEmpty) {
    sanitized = 'download';
  }

  if (_reservedWindowsFileNames.contains(sanitized.toUpperCase())) {
    sanitized = '_$sanitized';
  }

  const maxStemLength = 180;
  if (sanitized.length > maxStemLength) {
    sanitized = sanitized.substring(0, maxStemLength).trimRight();
  }

  return sanitized;
}

String buildMp3DownloadFileName({
  required String? songName,
  required Iterable<String?> artistNames,
}) {
  final title =
      songName == null || songName.trim().isEmpty ? 'Unknown Song' : songName;
  final artists = artistNames
      .where((name) => name != null && name.trim().isNotEmpty)
      .map((name) => name!.trim())
      .join(', ');
  final artistPart = artists.isEmpty ? 'Unknown Artist' : artists;
  return '${sanitizeDownloadFileName('$artistPart - $title')}.mp3';
}

String resolveDefaultDownloadDirectory({
  required Map<String, String> environment,
  required String? downloadsDirectory,
  required String supportDirectory,
  required bool isWindows,
}) {
  if (isWindows) {
    final userProfile = environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      return joinDownloadPath(userProfile, 'Desktop');
    }
  }

  if (downloadsDirectory != null && downloadsDirectory.trim().isNotEmpty) {
    return downloadsDirectory.trim();
  }

  return supportDirectory.trim();
}

String joinDownloadPath(String directory, String child) {
  final trimmedDirectory = directory.trim();
  if (trimmedDirectory.isEmpty) return child;

  final separator = _separatorFor(trimmedDirectory);
  if (trimmedDirectory == '/' || trimmedDirectory == r'\') {
    return '$trimmedDirectory$child';
  }

  final withoutTrailingSeparators = trimmedDirectory.replaceAll(
    RegExp(r'[\\/]+$'),
    '',
  );

  if (withoutTrailingSeparators.isEmpty) return child;
  return '$withoutTrailingSeparators$separator$child';
}

String _separatorFor(String path) {
  if (path.contains(r'\') && !path.contains('/')) return r'\';
  return '/';
}
