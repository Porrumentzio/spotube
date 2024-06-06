part of '../spotify.dart';

class SyncedLyricsNotifier extends FamilyAsyncNotifier<SubtitleSimple, Track?>
    with Persistence<SubtitleSimple> {
  SyncedLyricsNotifier() {
    load();
  }

  Track get _track => arg!;

  Future<SubtitleSimple> getSpotifyLyrics(String? token) async {
    final res = await http.get(
        Uri.parse(
          "https://spclient.wg.spotify.com/color-lyrics/v2/track/${_track.id}?format=json&market=from_token",
        ),
        headers: {
          "User-Agent":
              "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36",
          "App-platform": "WebPlayer",
          "authorization": "Bearer $token"
        });

    if (res.statusCode != 200) {
      return SubtitleSimple(
        lyrics: [],
        name: _track.name!,
        uri: res.request!.url,
        rating: 0,
        provider: "Spotify",
      );
    }
    final linesRaw = Map.castFrom<dynamic, dynamic, String, dynamic>(
      jsonDecode(res.body),
    )["lyrics"]?["lines"] as List?;

    final lines = linesRaw?.map((line) {
          return LyricSlice(
            time: Duration(milliseconds: int.parse(line["startTimeMs"])),
            text: line["words"] as String,
          );
        }).toList() ??
        [];

    return SubtitleSimple(
      lyrics: lines,
      name: _track.name!,
      uri: res.request!.url,
      rating: 100,
      provider: "Spotify",
    );
  }

  /// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors
  /// Thanks for their generous public API
  Future<SubtitleSimple> getLRCLibLyrics() async {
    final packageInfo = await PackageInfo.fromPlatform();

    final res = await http.get(
      Uri(
        scheme: "https",
        host: "lrclib.net",
        path: "/api/get",
        queryParameters: {
          "artist_name": _track.artists?.first.name,
          "track_name": _track.name,
          "album_name": _track.album?.name,
          "duration": _track.duration?.inSeconds.toString(),
        },
      ),
      headers: {
        "User-Agent":
            "Spotube v${packageInfo.version} (https://github.com/KRTirtho/spotube)"
      },
    );

    if (res.statusCode != 200) {
      return SubtitleSimple(
        lyrics: [],
        name: _track.name!,
        uri: res.request!.url,
        rating: 0,
        provider: "LRCLib",
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;

    final syncedLyricsRaw = json["syncedLyrics"] as String?;
    final syncedLyrics = syncedLyricsRaw?.isNotEmpty == true
        ? Lrc.parse(syncedLyricsRaw!)
            .lyrics
            .map(LyricSlice.fromLrcLine)
            .toList()
        : null;

    if (syncedLyrics?.isNotEmpty == true) {
      return SubtitleSimple(
        lyrics: syncedLyrics!,
        name: _track.name!,
        uri: res.request!.url,
        rating: 100,
        provider: "LRCLib",
      );
    }

    final plainLyrics = (json["plainLyrics"] as String)
        .split("\n")
        .map((line) => LyricSlice(text: line, time: Duration.zero))
        .toList();

    return SubtitleSimple(
      lyrics: plainLyrics,
      name: _track.name!,
      uri: res.request!.url,
      rating: 0,
      provider: "LRCLib",
    );
  }

  @override
  FutureOr<SubtitleSimple> build(track) async {
    try {
      final spotify = ref.watch(spotifyProvider);
      if (track == null) {
        throw "No track currently";
      }
      final token = await spotify.getCredentials();
      SubtitleSimple lyrics = await getSpotifyLyrics(token.accessToken);

      if (lyrics.lyrics.isEmpty) {
        lyrics = await getLRCLibLyrics();
      }

      if (lyrics.lyrics.isEmpty) {
        throw Exception("Unable to find lyrics");
      }

      return lyrics;
    } catch (e, stackTrace) {
      Catcher2.reportCheckedError(e, stackTrace);
      rethrow;
    }
  }

  @override
  FutureOr<SubtitleSimple> fromJson(Map<String, dynamic> json) =>
      SubtitleSimple.fromJson(json.castKeyDeep<String>());

  @override
  Map<String, dynamic> toJson(SubtitleSimple data) => data.toJson();
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

final syncedLyricsProvider =
    AsyncNotifierProviderFamily<SyncedLyricsNotifier, SubtitleSimple, Track?>(
  () => SyncedLyricsNotifier(),
);

final syncedLyricsMapProvider =
    FutureProvider.family((ref, Track? track) async {
  final syncedLyrics = await ref.watch(syncedLyricsProvider(track).future);

  final isStaticLyrics =
      syncedLyrics.lyrics.every((l) => l.time == Duration.zero);

  final lyricsMap = syncedLyrics.lyrics
      .map((lyric) => {lyric.time.inSeconds: lyric.text})
      .reduce((accumulator, lyricSlice) => {...accumulator, ...lyricSlice});

  return (static: isStaticLyrics, lyricsMap: lyricsMap);
});
