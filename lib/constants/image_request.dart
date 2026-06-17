const Map<String, String> _neteaseImageHeaders = {
  'Referer': 'https://music.163.com/',
  'Origin': 'https://music.163.com',
  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

const int _defaultNeteaseImageSize = 512;

String? normalizeImageUrl(
  String? rawUrl, {
  int neteaseImageSize = _defaultNeteaseImageSize,
}) {
  if (rawUrl == null) return null;
  var url = rawUrl.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) url = 'https:$url';
  if (url.startsWith('http://')) {
    url = 'https://${url.substring('http://'.length)}';
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !_isNeteaseImageHost(uri.host)) return url;
  if (uri.queryParameters.containsKey('param')) return url;
  if (neteaseImageSize < 1) return url;

  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'param': '${neteaseImageSize}y$neteaseImageSize',
        },
      )
      .toString();
}

bool _isNeteaseImageHost(String host) {
  final lowerHost = host.toLowerCase();
  return lowerHost == 'music.126.net' || lowerHost.endsWith('.music.126.net');
}

Map<String, String>? imageHeadersFor(String? rawUrl) {
  final url = normalizeImageUrl(rawUrl);
  if (url == null) return null;

  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (!_isNeteaseImageHost(uri.host)) return null;

  return _neteaseImageHeaders;
}
