const Map<String, String> _neteaseImageHeaders = {
  'Referer': 'https://music.163.com/',
  'Origin': 'https://music.163.com',
  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

String? normalizeImageUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  final url = rawUrl.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) {
    return 'https://${url.substring('http://'.length)}';
  }
  return url;
}

Map<String, String>? imageHeadersFor(String? rawUrl) {
  final url = normalizeImageUrl(rawUrl);
  if (url == null) return null;

  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  final isNeteaseImage =
      host == 'music.126.net' || host.endsWith('.music.126.net');
  if (!isNeteaseImage) return null;

  return _neteaseImageHeaders;
}
