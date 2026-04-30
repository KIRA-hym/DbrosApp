import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// RSS 첫 영상 메타 (채널 피드용)
typedef YoutubeLatestVideoMeta = ({
  String id,
  String title,
  String channelName,
  String publishedDot,
});

/// YouTube 채널 RSS(`feeds/videos.xml`)에서 최신 영상 ID 추출 — API 키 불필요.
class YoutubeRssService {
  YoutubeRssService._();

  /// 기본 Dart UA는 YouTube RSS/oEmbed에서 거절되는 경우가 있어 브라우저형으로 통일.
  static const Map<String, String> _rssHeaders = {
    'Accept': 'application/atom+xml, application/xml, text/xml, */*',
    'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  };

  static final Map<String, String> _oembedHeaders = {
    ..._rssHeaders,
    'Accept': 'application/json, */*',
  };

  static final _ytVideoIdTag = RegExp(
    r'<yt:videoId>\s*([a-zA-Z0-9_-]{11})\s*</yt:videoId>',
    caseSensitive: false,
  );
  static final _watchLink = RegExp(
    r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );
  /// Atom entry 없이 본문에만 링크가 있을 때 (형식 변동 대비)
  static final _watchInHref = RegExp(
    r'href="https?://(?:www\.)?youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );
  static final _embedOrShort = RegExp(
    r'(?:youtube\.com/embed/|youtu\.be/)([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );

  static const _cacheKeyPrefix = 'home_yt_rss_vid_';
  static const _cacheTsSuffix = '_at';
  static const _cacheTitleSuffix = '_title';
  static const _cacheAuthorSuffix = '_author';
  static const _cachePublishedSuffix = '_publishedDot';
  static const _cacheTtl = Duration(hours: 4);

  static final _entryTag = RegExp(
    r'<entry\b[\s\S]*?</entry>',
    caseSensitive: false,
  );
  static final _entryTitleTag = RegExp(
    r'<title>\s*(?:<!\[CDATA\[(.*?)\]\]>|([^<]+))\s*</title>',
    caseSensitive: false,
  );
  static final _entryPublishedTag = RegExp(
    r'<published>\s*([^<]+?)\s*</published>',
    caseSensitive: false,
  );
  /// entry 내 채널명 (첫 entry의 author/name)
  static final _entryAuthorNameTag = RegExp(
    r'<author>\s*<name>\s*(?:<!\[CDATA\[(.*?)\]\]>|([^<]+?))\s*</name>',
    caseSensitive: false,
  );
  static final _feedAuthorNameTag = RegExp(
    r'<feed\b[\s\S]*?<author>\s*<name>\s*(?:<!\[CDATA\[(.*?)\]\]>|([^<]+?))\s*</name>',
    caseSensitive: false,
  );
  static final _feedTitleTag = RegExp(
    r'<feed\b[\s\S]*?<title>\s*(?:<!\[CDATA\[(.*?)\]\]>|([^<]+?))\s*</title>',
    caseSensitive: false,
  );
  static final _entryUpdatedTag = RegExp(
    r'<updated>\s*([^<]+?)\s*</updated>',
    caseSensitive: false,
  );

  static String _decodeXmlText(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  static bool _looksLikeAtomFeed(String body) {
    final t = body.trimLeft();
    if (t.length < 80) return false;
    return t.startsWith('<?xml') || t.contains('<feed') || t.contains('<entry');
  }

  static String? _parseFirstVideoId(String xml) {
    final m = _ytVideoIdTag.firstMatch(xml);
    if (m != null && (m.group(1)?.length == 11)) return m.group(1);
    for (final r in [_watchInHref, _embedOrShort, _watchLink]) {
      final hit = r.firstMatch(xml);
      if (hit != null && (hit.group(1)?.length == 11)) return hit.group(1);
    }
    return null;
  }

  static String _parseFirstPublishedAnywhere(String xml) {
    final pm = RegExp(
      r'<published>\s*([^<]+?)\s*</published>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (pm != null) {
      final d = _dotDateFromIsoPublished(pm.group(1) ?? '');
      if (d.isNotEmpty) return d;
    }
    return '';
  }

  static String _dotDateFromIsoPublished(String iso) {
    try {
      final dt = DateTime.parse(iso.trim()).toLocal();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '${dt.year}.$m.$d';
    } catch (_) {
      return '';
    }
  }

  static YoutubeLatestVideoMeta? _parseLatestVideoMeta(String xml) {
    final em = _entryTag.firstMatch(xml);
    if (em == null) return null;
    final entry = em.group(0) ?? '';
    final id = _parseFirstVideoId(entry);
    if (id == null || id.isEmpty) return null;
    final tm = _entryTitleTag.firstMatch(entry);
    final rawTitle = (tm?.group(1) ?? tm?.group(2) ?? '').trim();
    final title = rawTitle.isEmpty ? '유튜브 최신 영상' : _decodeXmlText(rawTitle);

    String channelName = '';
    final am = _entryAuthorNameTag.firstMatch(entry);
    if (am != null) {
      channelName = (am.group(1) ?? am.group(2) ?? '').trim();
      channelName = _decodeXmlText(channelName);
    }
    if (channelName.isEmpty) {
      final fam = _feedAuthorNameTag.firstMatch(xml);
      if (fam != null) {
        channelName = (fam.group(1) ?? fam.group(2) ?? '').trim();
        channelName = _decodeXmlText(channelName);
      }
    }
    if (channelName.isEmpty) {
      final ftm = _feedTitleTag.firstMatch(xml);
      if (ftm != null) {
        channelName = (ftm.group(1) ?? ftm.group(2) ?? '').trim();
        channelName = _decodeXmlText(channelName);
      }
    }

    String publishedDot = '';
    final pm = _entryPublishedTag.firstMatch(entry);
    if (pm != null) {
      publishedDot = _dotDateFromIsoPublished(pm.group(1) ?? '');
    }
    if (publishedDot.isEmpty) {
      final um = _entryUpdatedTag.firstMatch(entry);
      if (um != null) {
        publishedDot = _dotDateFromIsoPublished(um.group(1) ?? '');
      }
    }

    return (
      id: id,
      title: title,
      channelName: channelName,
      publishedDot: publishedDot,
    );
  }

  static Future<({String title, String channelName})?> _fetchOEmbedMeta(
    String videoId,
  ) async {
    try {
      final uri = Uri.https('www.youtube.com', '/oembed', <String, String>{
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'json',
      });
      final res = await http
          .get(uri, headers: _oembedHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final title = (map['title'] ?? '').toString().trim();
      final channel = (map['author_name'] ?? '').toString().trim();
      return (title: title, channelName: channel);
    } catch (_) {
      return null;
    }
  }

  /// 공개 RSS에서 첫 번째(최신) 영상 ID만 반환. 네트워크/파싱 실패 시 null.
  static Future<String?> fetchLatestVideoId(String channelId) async {
    final id = channelId.trim();
    if (id.isEmpty) return null;
    final uri = Uri.https(
      'www.youtube.com',
      '/feeds/videos.xml',
      <String, String>{'channel_id': id},
    );
    try {
      final res = await http
          .get(uri, headers: _rssHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      if (!_looksLikeAtomFeed(res.body)) return null;
      return _parseFirstVideoId(res.body);
    } catch (_) {
      return null;
    }
  }

  /// 동일 채널에 대해 짧은 시간 내 재요청을 줄이기 위해 캐시.
  static Future<String?> fetchLatestVideoIdCached(String channelId) async {
    final id = channelId.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final keyVid = '$_cacheKeyPrefix$id';
    final keyTs = '$keyVid$_cacheTsSuffix';
    final cached = prefs.getString(keyVid);
    final tsMs = prefs.getInt(keyTs);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null &&
        cached.length == 11 &&
        tsMs != null &&
        now - tsMs < _cacheTtl.inMilliseconds) {
      return cached;
    }

    final fresh = await fetchLatestVideoId(id);
    if (fresh != null && fresh.isNotEmpty) {
      await prefs.setString(keyVid, fresh);
      await prefs.setInt(keyTs, now);
      return fresh;
    }
    return cached;
  }

  /// 최신 영상 id / 제목 / 채널명 / 게시일(yyyy.MM.dd, 로컬). 실패 시 null.
  static Future<YoutubeLatestVideoMeta?> fetchLatestVideoMetaCached(String channelId) async {
    final id = channelId.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final keyVid = '$_cacheKeyPrefix$id';
    final keyTs = '$keyVid$_cacheTsSuffix';
    final keyTitle = '$keyVid$_cacheTitleSuffix';
    final keyAuthor = '$keyVid$_cacheAuthorSuffix';
    final keyPublished = '$keyVid$_cachePublishedSuffix';
    final cachedId = prefs.getString(keyVid);
    final cachedTitle = prefs.getString(keyTitle);
    final cachedAuthor = prefs.getString(keyAuthor);
    final cachedPublished = prefs.getString(keyPublished);
    final tsMs = prefs.getInt(keyTs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final cacheFresh = tsMs != null && now - tsMs < _cacheTtl.inMilliseconds;
    final cacheComplete =
        cachedId != null &&
        cachedId.length == 11 &&
        cachedTitle != null &&
        cachedTitle.isNotEmpty &&
        cachedAuthor != null &&
        cachedPublished != null;

    if (cacheComplete && cacheFresh) {
      return (
        id: cachedId,
        title: cachedTitle,
        channelName: cachedAuthor,
        publishedDot: cachedPublished,
      );
    }

    final uri = Uri.https(
      'www.youtube.com',
      '/feeds/videos.xml',
      <String, String>{'channel_id': id},
    );
    try {
      final res = await http
          .get(uri, headers: _rssHeaders)
          .timeout(const Duration(seconds: 18));
      if (res.statusCode == 200 && _looksLikeAtomFeed(res.body)) {
        var meta = _parseLatestVideoMeta(res.body);
        if (meta == null) {
          final id = _parseFirstVideoId(res.body);
          if (id != null) {
            final oembed = await _fetchOEmbedMeta(id);
            meta = (
              id: id,
              title: (oembed?.title.isNotEmpty ?? false)
                  ? oembed!.title
                  : '유튜브 최신 영상',
              channelName: oembed?.channelName ?? '',
              publishedDot: _parseFirstPublishedAnywhere(res.body),
            );
          }
        }
        if (meta != null && (meta.channelName.isEmpty || meta.title.isEmpty)) {
          final oembed = await _fetchOEmbedMeta(meta.id);
          if (oembed != null) {
            meta = (
              id: meta.id,
              title: meta.title.isNotEmpty ? meta.title : oembed.title,
              channelName: meta.channelName.isNotEmpty
                  ? meta.channelName
                  : oembed.channelName,
              publishedDot: meta.publishedDot,
            );
          }
        }
        if (meta != null) {
          await prefs.setString(keyVid, meta.id);
          await prefs.setString(keyTitle, meta.title);
          await prefs.setString(keyAuthor, meta.channelName);
          await prefs.setString(keyPublished, meta.publishedDot);
          await prefs.setInt(keyTs, now);
          return meta;
        }
      }
    } catch (_) {}

    if (cachedId != null && cachedId.length == 11) {
      return (
        id: cachedId,
        title: (cachedTitle ?? '유튜브 최신 영상'),
        channelName: (cachedAuthor ?? ''),
        publishedDot: (cachedPublished ?? ''),
      );
    }
    return null;
  }

  /// 영상 ID만 있을 때도 제목/채널명을 조회해 홈 카드 표시를 보강.
  static Future<({String title, String channelName})?> fetchVideoMetaById(
    String videoId,
  ) async {
    final id = videoId.trim();
    if (id.length != 11) return null;
    return _fetchOEmbedMeta(id);
  }
}
