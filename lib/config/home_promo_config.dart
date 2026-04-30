/// 홈 하단 프로모 영역 — 유료 API 없이 동작하도록 ID만 넣어 사용합니다.
///
/// **유튜브**
/// - **채널 ID**(`UC…`): 채널 업로드 목록(playlist `UU…`)을 임베드합니다.
/// - **영상 ID**(11자): 해당 영상만 재생합니다.
/// 비우면 안내 플레이스홀더만 표시됩니다.
const String kHomeYoutubeVideoId = 'UCdv6tbCA0-vhRKBW_3SjBRw';

/// 채널 ID 여부 판단 (기본 규칙).
bool isHomeYoutubeChannelId(String raw) {
  final id = raw.trim();
  return id.startsWith('UC') && id.length >= 22;
}

/// [kHomeYoutubeVideoId] 로 임베드할 YouTube URL을 만듭니다.
Uri buildHomeYoutubeEmbedUri(String raw) {
  final id = raw.trim();
  if (id.isEmpty) {
    return Uri.parse('about:blank');
  }
  if (id.startsWith('UC') && id.length >= 22) {
    final uploadsListId = 'UU${id.substring(2)}';
    return Uri.parse(
      'https://www.youtube.com/embed/videoseries?list=$uploadsListId&playsinline=1&rel=0&modestbranding=1',
    );
  }
  return Uri.parse(
    'https://www.youtube.com/embed/$id?playsinline=1&rel=0&modestbranding=1',
  );
}
