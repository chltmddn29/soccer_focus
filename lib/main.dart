import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '축구선수 포커스',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B46)),
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        useMaterial3: true,
      ),
      home: const MatchPage(),
    );
  }
}

// 2026-09-28 튀르키예-이탈리아 경기에서 확인된 선수 기록입니다.
class Player {
  const Player({
    required this.name,
    required this.position,
    required this.distanceKm,
    required this.goals,
    required this.assists,
    required this.passes,
    required this.minutes,
    this.focusTrack,
    this.highlights = const [],
  });

  final String name;
  final String position;
  final double? distanceKm;
  final int? goals;
  final int? assists;
  final int? passes;
  final int? minutes;
  final PlayerFocusTrack? focusTrack;
  final List<HighlightClip> highlights;
}

// 미리 확인한 구간이나 사용자가 입력한 전체 영상의 재생 범위를 보관합니다.
class HighlightClip {
  const HighlightClip({
    required this.title,
    required this.rangeLabel,
    required this.startSeconds,
    this.endSeconds,
    this.videoId = '9wx0QPdlPc8',
  });

  final String title;
  final String rangeLabel;
  final double startSeconds;
  final double? endSeconds;
  final String videoId;
}

// 붙여 넣은 URL에서 YouTube 영상 ID만 추출해 추적용 쿼리는 저장하지 않습니다.
String? youtubeVideoIdFromUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  String? videoId;
  if (host == 'youtu.be' && parts.length == 1) {
    videoId = parts.first;
  } else if ({
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
  }.contains(host)) {
    if (uri.path == '/watch') {
      videoId = uri.queryParameters['v'];
    } else if (parts.length == 2 &&
        {'shorts', 'embed', 'live'}.contains(parts.first)) {
      videoId = parts.last;
    }
  }
  if (videoId == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
    return null;
  }
  return videoId;
}

// 영상 파일 대신 재생 위치, 설명, 선수 이름과 입력한 경기 기록을 저장합니다.
class SavedHighlight {
  const SavedHighlight({
    required this.videoId,
    required this.startSeconds,
    this.endSeconds,
    required this.description,
    this.playerName,
    this.distanceKm,
    this.goals,
    this.assists,
    this.passes,
    this.minutes,
  });

  final String videoId;
  final double startSeconds;
  final double? endSeconds;
  final String description;
  final String? playerName;
  final double? distanceKm;
  final int? goals;
  final int? assists;
  final int? passes;
  final int? minutes;

  Map<String, Object> toJson() {
    final data = <String, Object>{
      'videoId': videoId,
      'startSeconds': startSeconds,
      'description': description,
    };
    if (endSeconds case final end?) data['endSeconds'] = end;
    if (playerName case final name?) data['playerName'] = name;
    if (distanceKm case final distance?) data['distanceKm'] = distance;
    if (goals case final count?) data['goals'] = count;
    if (assists case final count?) data['assists'] = count;
    if (passes case final count?) data['passes'] = count;
    if (minutes case final count?) data['minutes'] = count;
    return data;
  }

  static SavedHighlight? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final videoId = value['videoId'];
    final start = value['startSeconds'];
    final end = value['endSeconds'];
    final description = value['description'];
    final playerName = value['playerName'];
    final distance = value['distanceKm'];
    final goals = value['goals'];
    final assists = value['assists'];
    final passes = value['passes'];
    final minutes = value['minutes'];
    if (videoId is! String ||
        start is! num ||
        (end != null && end is! num) ||
        description is! String ||
        description.trim().isEmpty ||
        (playerName != null &&
            (playerName is! String || playerName.trim().isEmpty)) ||
        (distance != null &&
            (distance is! num || !distance.isFinite || distance < 0)) ||
        (goals != null && (goals is! int || goals < 0)) ||
        (assists != null && (assists is! int || assists < 0)) ||
        (passes != null && (passes is! int || passes < 0)) ||
        (minutes != null && (minutes is! int || minutes < 0)) ||
        start < 0 ||
        (end is num && end <= start)) {
      return null;
    }
    return SavedHighlight(
      videoId: videoId,
      startSeconds: start.toDouble(),
      endSeconds: (end as num?)?.toDouble(),
      description: description,
      playerName: playerName as String?,
      distanceKm: (distance as num?)?.toDouble(),
      goals: goals as int?,
      assists: assists as int?,
      passes: passes as int?,
      minutes: minutes as int?,
    );
  }
}

abstract class HighlightStorage {
  Future<List<SavedHighlight>> load();
  Future<void> save(List<SavedHighlight> highlights);
}

// 사용자가 직접 기록한 포커스 위치를 영상·선수별로 보관합니다.
abstract class FocusTrackStorage {
  Future<List<FocusSample>> loadTrack(String key);
  Future<void> saveTrack(String key, List<FocusSample> samples);
}

class SoccerItem {
  const SoccerItem({required this.title, this.completed = false});

  final String title;
  final bool completed;

  Map<String, Object> toJson() => {'title': title, 'completed': completed};

  static SoccerItem? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final title = value['title'];
    final completed = value['completed'];
    if (title is! String || title.trim().isEmpty || completed is! bool) {
      return null;
    }
    return SoccerItem(title: title, completed: completed);
  }
}

class BrowserHighlightStorage implements HighlightStorage, FocusTrackStorage {
  static const key = 'soccer-items';

  // 경기 목록과 영상 정보를 하나의 키에 함께 보관합니다.
  Future<Map<String, dynamic>> _readData() async {
    if (!kIsWeb) return {};
    try {
      final preferences = SharedPreferencesAsync();
      final raw = await preferences.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeData(Map<String, dynamic> data) async {
    if (!kIsWeb) return;
    final preferences = SharedPreferencesAsync();
    await preferences.setString(key, jsonEncode(data));
  }

  Future<List<SoccerItem>> loadItems() async {
    final data = await _readData();
    final items = data['items'];
    if (items is! List) return [];
    return items.map(SoccerItem.fromJson).whereType<SoccerItem>().toList();
  }

  Future<void> saveItems(List<SoccerItem> items) async {
    final data = await _readData();
    data['items'] = items.map((item) => item.toJson()).toList();
    await _writeData(data);
  }

  @override
  Future<List<FocusSample>> loadTrack(String key) async {
    final data = await _readData();
    final tracks = data['focusTracks'];
    final samples = tracks is Map ? tracks[key] : null;
    if (samples is! List) return [];
    return samples.map(FocusSample.fromJson).whereType<FocusSample>().toList();
  }

  @override
  Future<void> saveTrack(String key, List<FocusSample> samples) async {
    final data = await _readData();
    final tracks = data['focusTracks'];
    final updated = tracks is Map<String, dynamic>
        ? tracks
        : <String, dynamic>{};
    if (samples.isEmpty) {
      updated.remove(key);
    } else {
      updated[key] = samples.map((sample) => sample.toJson()).toList();
    }
    data['focusTracks'] = updated;
    await _writeData(data);
  }

  @override
  Future<List<SavedHighlight>> load() async {
    final data = await _readData();
    final highlights = data['highlights'];
    if (highlights is! List) return [];
    return highlights
        .map(SavedHighlight.fromJson)
        .whereType<SavedHighlight>()
        .toList();
  }

  @override
  Future<void> save(List<SavedHighlight> highlights) async {
    final data = await _readData();
    data['highlights'] = highlights.map((item) => item.toJson()).toList();
    await _writeData(data);
  }
}

const turkeyNumber10Highlights = [
  HighlightClip(
    title: '아르다 귈러 · 초반 장면',
    rangeLabel: '0:23.5~0:32.0',
    startSeconds: 23.5,
    endSeconds: 32,
  ),
  HighlightClip(
    title: '아르다 귈러 · 후반 공격 장면',
    rangeLabel: '3:09.0~3:17.5',
    startSeconds: 189,
    endSeconds: 197.5,
  ),
];

// 영상을 980×551 크기로 보며 직접 기록한 선수 주변 사각형입니다.
class FocusSample {
  const FocusSample(this.seconds, this.left, this.top, this.width, this.height);

  final double seconds;
  final double left;
  final double top;
  final double width;
  final double height;

  // 화면에서 그린 0~1 비율 사각형을 같은 980×551 기준 값으로 바꿉니다.
  factory FocusSample.fromRect(double seconds, Rect rect) => FocusSample(
    seconds,
    rect.left * 980,
    rect.top * 551,
    rect.width * 980,
    rect.height * 551,
  );

  List<double> toJson() => [seconds, left, top, width, height];

  static FocusSample? fromJson(Object? value) {
    if (value is! List || value.length != 5) return null;
    if (value.any((item) => item is! num || !item.isFinite)) return null;
    final v = value.cast<num>();
    if (v[0] < 0 || v[3] <= 0 || v[4] <= 0) return null;
    return FocusSample(
      v[0].toDouble(),
      v[1].toDouble(),
      v[2].toDouble(),
      v[3].toDouble(),
      v[4].toDouble(),
    );
  }

  // 화면 크기가 바뀌어도 같은 위치를 가리키도록 0~1 비율로 변환합니다.
  Rect get bounds =>
      Rect.fromLTWH(left / 980, top / 551, width / 980, height / 551);
}

class PlayerFocusTrack {
  const PlayerFocusTrack({required this.label, required this.segments});

  final String label;
  final List<List<FocusSample>> segments;

  Rect? rectangleAt(Duration position) {
    final seconds = position.inMicroseconds / Duration.microsecondsPerSecond;
    for (final samples in segments) {
      // 기록이 하나뿐이면 그 시점 앞뒤 0.5초만 보여 줍니다.
      if (samples.length == 1 &&
          (seconds - samples.first.seconds).abs() <= 0.5) {
        return samples.first.bounds;
      }
      if (samples.isEmpty ||
          seconds < samples.first.seconds ||
          seconds > samples.last.seconds) {
        continue;
      }
      for (var i = 1; i < samples.length; i++) {
        final before = samples[i - 1];
        final after = samples[i];
        if (seconds <= after.seconds) {
          final progress =
              (seconds - before.seconds) / (after.seconds - before.seconds);
          // 같은 장면 안의 두 기록 사이를 연결합니다. 장면 사이는 연결하지 않습니다.
          return Rect.lerp(before.bounds, after.bounds, progress);
        }
      }
      return samples.last.bounds;
    }
    // 위치가 미등록된 구간에서 다른 선수를 잘못 가리키지 않습니다.
    return null;
  }
}

// 기록 사이가 3초 이하이면 같은 장면으로 보고 이어 붙이고, 더 멀면 장면을 나눕니다.
List<List<FocusSample>> groupFocusSamples(List<FocusSample> samples) {
  final sorted = [...samples]..sort((a, b) => a.seconds.compareTo(b.seconds));
  final segments = <List<FocusSample>>[];
  for (final sample in sorted) {
    if (segments.isNotEmpty &&
        sample.seconds - segments.last.last.seconds <= 3) {
      segments.last.add(sample);
    } else {
      segments.add([sample]);
    }
  }
  return segments;
}

const turkeyNumber10Track = PlayerFocusTrack(
  label: '튀르키예 10번',
  segments: [
    // 0:23.5~0:32.0: 등번호 10을 확인한 초반 장면입니다.
    [
      FocusSample(23.5, 361, 269, 30, 67),
      FocusSample(24, 369, 271, 29, 68),
      FocusSample(24.5, 376, 272, 32, 70),
      FocusSample(25, 375, 274, 34, 72),
      FocusSample(25.5, 358, 281, 34, 71),
      FocusSample(26, 343, 285, 34, 74),
      FocusSample(26.5, 358, 289, 41, 75),
      FocusSample(27, 342, 286, 42, 74),
      FocusSample(27.5, 327, 285, 37, 72),
      FocusSample(28, 304, 284, 36, 72),
      FocusSample(28.5, 287, 289, 31, 72),
      FocusSample(29, 283, 291, 32, 71),
      FocusSample(29.5, 275, 292, 31, 70),
      FocusSample(30, 276, 290, 50, 69),
      FocusSample(30.5, 306, 285, 49, 69),
      FocusSample(31, 349, 278, 48, 70),
      FocusSample(32, 440, 273, 44, 68),
    ],
    // 3:09.0~3:17.5: 등번호 10을 확인한 후반 공격 장면입니다.
    [
      FocusSample(189, 546, 295, 31, 60),
      FocusSample(189.5, 549, 281, 30, 58),
      FocusSample(190, 549, 267, 47, 64),
      FocusSample(190.5, 555, 251, 39, 61),
      FocusSample(191, 540, 248, 39, 58),
      FocusSample(191.5, 538, 243, 33, 56),
      FocusSample(192, 538, 246, 40, 70),
      FocusSample(192.5, 544, 259, 56, 66),
      FocusSample(193, 514, 244, 33, 78),
      FocusSample(193.5, 466, 237, 38, 77),
      FocusSample(194, 446, 230, 31, 74),
      FocusSample(194.5, 438, 218, 39, 73),
      FocusSample(195, 425, 209, 45, 72),
      FocusSample(195.5, 416, 203, 35, 75),
      FocusSample(196, 392, 212, 34, 75),
      FocusSample(196.5, 369, 206, 33, 75),
      FocusSample(197, 340, 208, 38, 81),
      FocusSample(197.5, 320, 209, 28, 80),
    ],
  ],
);

// 경기별 이동 거리는 확인된 자료가 없어 비워 두고, 0으로 표시하지 않습니다.
const players = [
  Player(
    name: '아르다 귈러',
    position: '미드필더 · 튀르키예 10번',
    distanceKm: null,
    goals: 0,
    assists: 0,
    passes: 70,
    minutes: 90,
    focusTrack: turkeyNumber10Track,
    highlights: turkeyNumber10Highlights,
  ),
  Player(
    name: '바르쉬 알페르 이을마즈',
    position: '공격수 · 튀르키예',
    distanceKm: null,
    goals: 1,
    assists: 0,
    passes: null,
    minutes: 80,
  ),
  Player(
    name: '오우즈 아이든',
    position: '미드필더 · 튀르키예',
    distanceKm: null,
    goals: 0,
    assists: 1,
    passes: null,
    minutes: 90,
  ),
];

class MatchPage extends StatefulWidget {
  const MatchPage({super.key, this.storage, this.focusStorage});

  final HighlightStorage? storage;
  final FocusTrackStorage? focusStorage;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  Player? _selectedPlayer;
  final TextEditingController _playerNameController = TextEditingController();
  String? _playerInputError;
  SavedHighlight? _selectedVideo;
  bool _resultOpened = false;
  late final FocusTrackStorage _focusStorage =
      widget.focusStorage ?? BrowserHighlightStorage();

  void _selectTypedPlayer(String name) {
    final enteredName = name.trim();
    setState(() {
      // 선수 이름은 영상마다 다르므로 미리 정한 명단으로 제한하지 않습니다.
      _selectedPlayer = enteredName.isEmpty
          ? null
          : _playerForVideo(enteredName, _selectedVideo);
      _playerInputError = null;
    });
  }

  Player _playerForVideo(String name, SavedHighlight? video) {
    if (video?.playerName == name &&
        (video!.distanceKm != null ||
            video.goals != null ||
            video.assists != null ||
            video.passes != null ||
            video.minutes != null)) {
      return Player(
        name: name,
        position: '사용자 입력 기록',
        distanceKm: video.distanceKm,
        goals: video.goals,
        assists: video.assists,
        passes: video.passes,
        minutes: video.minutes,
      );
    }
    if (video?.videoId == '9wx0QPdlPc8') {
      for (final player in players) {
        if (player.name == name) return player;
      }
    }
    return Player(
      name: name,
      position: '기록 미등록',
      distanceKm: null,
      goals: null,
      assists: null,
      passes: null,
      minutes: null,
    );
  }

  @override
  void dispose() {
    _playerNameController.dispose();
    super.dispose();
  }

  Future<void> _openPage(Widget page) async {
    if (_resultOpened || !mounted) return;
    // 다른 화면을 여는 동안 경기 재생기를 닫아 재생기를 하나만 유지합니다.
    setState(() => _resultOpened = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() => _resultOpened = false);
  }

  void _showResult() {
    final player = _selectedPlayer;
    if (player != null) unawaited(_openPage(MatchResultPage(player: player)));
  }

  void _showAddVideo() =>
      unawaited(_openPage(AddVideoPage(storage: widget.storage)));

  Future<void> _showHistory() async {
    if (_resultOpened || !mounted) return;
    setState(() => _resultOpened = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final selected = await Navigator.of(context).push<SavedHighlight>(
      MaterialPageRoute(
        builder: (_) => VideoHistoryPage(storage: widget.storage),
      ),
    );
    if (mounted) {
      setState(() {
        if (selected != null) {
          _selectedVideo = selected;
          final name = selected.playerName?.trim();
          if (name != null && name.isNotEmpty) {
            _playerNameController.text = name;
            _selectedPlayer = _playerForVideo(name, selected);
          } else if (_selectedPlayer != null) {
            _selectedPlayer = _playerForVideo(_selectedPlayer!.name, selected);
          }
        }
        _resultOpened = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlayer = _selectedPlayer;
    return Scaffold(
      appBar: AppBar(title: const Text('축구선수 포커스')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '관심 선수와 경기를 함께 읽어요',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (selectedPlayer != null &&
                  _selectedVideo?.videoId == '9wx0QPdlPc8' &&
                  selectedPlayer.position != '사용자 입력 기록' &&
                  selectedPlayer.goals != null) ...[
                const Text('2026.9.28 튀르키예 1–4 이탈리아 · 실제 선수 및 경기 기록'),
                const SizedBox(height: 24),
              ],
              Text(
                '1. 집중해서 볼 선수',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('player-name-input'),
                controller: _playerNameController,
                decoration: InputDecoration(
                  labelText: '선수 이름 입력',
                  errorText: _playerInputError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _selectTypedPlayer,
              ),
              if (selectedPlayer != null) ...[
                const SizedBox(height: 12),
                Text(
                  '선택 선수: ${selectedPlayer.name}',
                  key: const Key('selected-player'),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showAddVideo,
                      icon: const Icon(Icons.add_link),
                      label: const Text('YouTube 영상 추가'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('영상 히스토리'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!_resultOpened &&
                  _selectedVideo != null &&
                  selectedPlayer != null)
                YouTubeMatchVideo(
                  key: ValueKey(_selectedVideo),
                  video: _selectedVideo!,
                  onEnded: _showResult,
                  selectedPlayer: selectedPlayer,
                  focusStorage: _focusStorage,
                ),
              if (selectedPlayer != null && _selectedVideo != null) ...[
                const SizedBox(height: 24),
                Text(
                  '2. ${selectedPlayer.name}의 경기 정보',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  '영상 장면별 누적치가 아닌 이 경기 전체의 기록입니다. 자료가 없는 수치는 표시하지 않습니다.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    StatCard(
                      label: '이동 거리',
                      value: selectedPlayer.distanceKm == null
                          ? '자료 없음'
                          : '${selectedPlayer.distanceKm!.toStringAsFixed(1)} km',
                    ),
                    StatCard(
                      label: '골',
                      value: selectedPlayer.goals == null
                          ? '자료 없음'
                          : '${selectedPlayer.goals}골',
                    ),
                    StatCard(
                      label: '어시스트',
                      value: selectedPlayer.assists == null
                          ? '자료 없음'
                          : '${selectedPlayer.assists}개',
                    ),
                    StatCard(
                      label: '패스 시도',
                      value: selectedPlayer.passes == null
                          ? '자료 없음'
                          : '${selectedPlayer.passes}회',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 53),
                    ),
                    icon: const Icon(Icons.assessment_outlined),
                    label: const Text('경기 종료 기록 미리보기'),
                    onPressed: _showResult,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const SoccerItemList(),
            ],
          ),
        ),
      ),
    );
  }
}

class SoccerItemList extends StatefulWidget {
  const SoccerItemList({super.key, this.storage});

  final BrowserHighlightStorage? storage;

  @override
  State<SoccerItemList> createState() => _SoccerItemListState();
}

class _SoccerItemListState extends State<SoccerItemList> {
  final _titleController = TextEditingController();
  late final BrowserHighlightStorage _storage;
  List<SoccerItem> _items = [];
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? BrowserHighlightStorage();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await _storage.loadItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(List<SoccerItem> items, {bool clearTitle = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _storage.saveItems(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        if (clearTitle) _titleController.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '저장에 실패했습니다. 브라우저 저장소를 확인하세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _add() {
    if (_loading || _saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '경기 제목을 입력하세요.');
      return;
    }
    unawaited(_save([..._items, SoccerItem(title: title)], clearTitle: true));
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('경기 목록', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          key: const Key('match-title-input'),
          controller: _titleController,
          decoration: InputDecoration(
            labelText: '경기 제목',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _loading || _saving ? null : _add,
          child: const Text('경기 추가'),
        ),
        for (var index = 0; index < _items.length; index++)
          ListTile(
            key: ValueKey('match-$index'),
            leading: Checkbox(
              value: _items[index].completed,
              onChanged: _saving
                  ? null
                  : (value) {
                      final updated = List<SoccerItem>.of(_items);
                      updated[index] = SoccerItem(
                        title: updated[index].title,
                        completed: value ?? false,
                      );
                      unawaited(_save(updated));
                    },
            ),
            title: Text(_items[index].title),
            trailing: IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () {
                      final updated = List<SoccerItem>.of(_items)
                        ..removeAt(index);
                      unawaited(_save(updated));
                    },
            ),
          ),
      ],
    );
  }
}

class YouTubeMatchVideo extends StatefulWidget {
  const YouTubeMatchVideo({
    super.key,
    required this.video,
    required this.onEnded,
    required this.selectedPlayer,
    required this.focusStorage,
  });

  final SavedHighlight video;
  final VoidCallback onEnded;
  final Player selectedPlayer;
  final FocusTrackStorage focusStorage;

  @override
  State<YouTubeMatchVideo> createState() => _YouTubeMatchVideoState();
}

class _YouTubeMatchVideoState extends State<YouTubeMatchVideo> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _playerSubscription;
  StreamSubscription<YoutubeVideoState>? _videoSubscription;
  final _focusPosition = ValueNotifier<Duration?>(null);
  Timer? _pausedPositionTimer;
  bool _readingPosition = false;
  // 사용자가 직접 기록한 위치와 편집 상태입니다. _draft는 0~1 비율 사각형입니다.
  List<FocusSample> _saved = [];
  bool _editing = false;
  Rect? _draft;
  Offset? _dragStart;
  String? _editorMessage;

  String get _trackKey =>
      '${widget.video.videoId}|${widget.selectedPlayer.name}';

  // 미리 넣어 둔 위치(아르다 귈러)와 사용자가 기록한 위치를 합칩니다.
  PlayerFocusTrack? get _track {
    final segments = <List<FocusSample>>[
      if (widget.video.videoId == '9wx0QPdlPc8')
        ...?widget.selectedPlayer.focusTrack?.segments,
      ...groupFocusSamples(_saved),
    ];
    if (segments.isEmpty) return null;
    return PlayerFocusTrack(
      label: widget.selectedPlayer.name,
      segments: segments,
    );
  }

  Future<void> _loadSaved() async {
    final key = _trackKey;
    try {
      final samples = await widget.focusStorage.loadTrack(key);
      if (mounted && key == _trackKey) setState(() => _saved = samples);
    } catch (_) {
      if (mounted) setState(() => _saved = []);
    }
  }

  Future<void> _persist(List<FocusSample> samples, String message) async {
    try {
      await widget.focusStorage.saveTrack(_trackKey, samples);
      if (mounted) {
        setState(() {
          _saved = samples;
          _editorMessage = message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _editorMessage = '저장에 실패했습니다. 브라우저 저장소를 확인하세요.');
      }
    }
  }

  // 영상이 멈춘 시점의 위치에 지금 그린 사각형을 기록합니다.
  Future<void> _saveSample() async {
    final controller = _controller;
    final draft = _draft;
    if (controller == null) return;
    if (controller.value.playerState != PlayerState.paused) {
      setState(() => _editorMessage = '영상을 일시정지한 뒤 저장하세요.');
      return;
    }
    if (draft == null) {
      setState(() => _editorMessage = '영상 위에서 선수를 드래그해 박스를 먼저 그리세요.');
      return;
    }
    final seconds = double.parse(
      (await controller.currentTime).toStringAsFixed(2),
    );
    final sample = FocusSample.fromRect(seconds, draft);
    final updated = [
      ..._saved.where((item) => (item.seconds - seconds).abs() >= 0.05),
      sample,
    ]..sort((a, b) => a.seconds.compareTo(b.seconds));
    setState(() => _draft = null);
    await _persist(updated, '${seconds.toStringAsFixed(2)}초 위치를 저장했습니다.');
  }

  Future<void> _seekBy(double delta) async {
    final controller = _controller;
    if (controller == null) return;
    final now = await controller.currentTime;
    await controller.seekTo(
      seconds: (now + delta).clamp(0, double.infinity).toDouble(),
      allowSeekAhead: true,
    );
  }

  Future<void> _readPausedPosition() async {
    final controller = _controller;
    if (_readingPosition ||
        controller?.value.playerState != PlayerState.paused) {
      return;
    }
    _readingPosition = true;
    try {
      final seconds = await controller!.currentTime;
      if (mounted && controller.value.playerState == PlayerState.paused) {
        _focusPosition.value = Duration(
          microseconds: (seconds * Duration.microsecondsPerSecond).round(),
        );
      }
    } catch (_) {
      if (mounted) _focusPosition.value = null;
    } finally {
      _readingPosition = false;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSaved());
    if (kIsWeb) {
      // 사용자가 지정한 영상만 불러오고, 자동 재생은 하지 않습니다.
      _controller = YoutubePlayerController.fromVideoId(
        videoId: widget.video.videoId,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
        ),
      );
      // 영상 종료 이벤트가 오면 선택 선수의 경기 종료 화면을 엽니다.
      _playerSubscription = _controller!.listen((value) {
        if (value.playerState == PlayerState.ended) widget.onEnded();
        if (value.playerState == PlayerState.paused) {
          unawaited(_readPausedPosition());
        } else if (value.playerState != PlayerState.playing) {
          _focusPosition.value = null;
        }
      });
      // 앱 실행 시간이 아니라 영상의 실제 재생 위치를 사용합니다.
      _videoSubscription = _controller!.videoStateStream.listen((value) {
        if (_controller!.value.playerState == PlayerState.playing) {
          _focusPosition.value = value.position;
        }
      });
      // 일시정지 중 탐색 막대를 움직여도 위치를 다시 확인합니다.
      _pausedPositionTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_readPausedPosition()),
      );
    }
  }

  @override
  void didUpdateWidget(YouTubeMatchVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 선수를 바꾸면 그 선수의 기록을 다시 불러옵니다.
    if (oldWidget.selectedPlayer.name != widget.selectedPlayer.name) {
      setState(() {
        _saved = [];
        _draft = null;
      });
      unawaited(_loadSaved());
    }
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _videoSubscription?.cancel();
    _pausedPositionTimer?.cancel();
    _focusPosition.dispose();
    _controller?.close();
    super.dispose();
  }

  // 영상 위에서 드래그해 선수 주변 박스를 그리는 층입니다. 아래 재생 막대는 가리지 않습니다.
  Widget _buildEditLayer(double width, double height) {
    final videoRect = Alignment.center.inscribe(
      applyBoxFit(
        BoxFit.contain,
        const Size(16, 9),
        Size(width, height),
      ).destination,
      Offset.zero & Size(width, height),
    );
    Offset normalize(Offset point) => Offset(
      ((point.dx - videoRect.left) / videoRect.width).clamp(0.0, 1.0),
      ((point.dy - videoRect.top) / videoRect.height).clamp(0.0, 1.0),
    );
    final draft = _draft;
    return Positioned(
      left: 0,
      top: 0,
      right: 0,
      bottom: 60,
      child: GestureDetector(
        key: const Key('focus-edit-layer'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _dragStart = normalize(details.localPosition);
        },
        onPanUpdate: (details) {
          final start = _dragStart;
          if (start == null) return;
          setState(
            () => _draft = Rect.fromPoints(
              start,
              normalize(details.localPosition),
            ),
          );
        },
        onPanEnd: (_) {
          final draft = _draft;
          // 너무 작은 박스는 실수로 보고 버립니다.
          if (draft != null && (draft.width < 0.01 || draft.height < 0.01)) {
            setState(() => _draft = null);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Colors.black12)),
            if (draft != null)
              Positioned(
                left: videoRect.left + draft.left * videoRect.width,
                top: videoRect.top + draft.top * videoRect.height,
                width: draft.width * videoRect.width,
                height: draft.height * videoRect.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    if (!_editing) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('focus-edit-toggle'),
          onPressed: () => setState(() => _editing = true),
          icon: const Icon(Icons.edit_location_alt_outlined),
          label: const Text('포커스 위치 기록'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1) 영상을 일시정지하고 2) 영상 위에서 선수를 드래그해 박스를 그린 뒤 '
          '3) "현재 시점 저장"을 누르세요. 1초 안팎 간격으로 반복하면 사이는 자동으로 이어집니다. '
          '기록 간격이 3초보다 넓으면 그 사이에는 테두리가 숨겨집니다.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => unawaited(_seekBy(-0.5)),
              child: const Text('−0.5초'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_seekBy(0.5)),
              child: const Text('+0.5초'),
            ),
            FilledButton(
              key: const Key('focus-save-sample'),
              onPressed: () => unawaited(_saveSample()),
              child: const Text('현재 시점 저장'),
            ),
            TextButton(
              onPressed: _saved.isEmpty
                  ? null
                  : () => unawaited(_persist([], '기록을 모두 지웠습니다.')),
              child: const Text('내 기록 모두 지우기'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _editing = false;
                _draft = null;
              }),
              child: const Text('편집 닫기'),
            ),
          ],
        ),
        if (_editorMessage != null) ...[
          const SizedBox(height: 8),
          Text(_editorMessage!, key: const Key('focus-editor-message')),
        ],
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sample in _saved)
                InputChip(
                  label: Text('${sample.seconds.toStringAsFixed(2)}초'),
                  onPressed: () => unawaited(
                    _controller?.seekTo(
                      seconds: sample.seconds,
                      allowSeekAhead: true,
                    ),
                  ),
                  onDeleted: () => unawaited(
                    _persist(
                      _saved.where((item) => item != sample).toList(),
                      '${sample.seconds.toStringAsFixed(2)}초 기록을 지웠습니다.',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YouTube 경기 영상',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(widget.video.description),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final aspectHeight = constraints.maxWidth * 9 / 16;
                // YouTube 플레이어는 높이가 최소 200px이어야 합니다.
                final height = aspectHeight < 200 ? 200.0 : aspectHeight;
                return SizedBox(
                  width: double.infinity,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (kIsWeb)
                        YoutubePlayer(
                          key: ValueKey(
                            'youtube-match-${widget.video.videoId}',
                          ),
                          controller: _controller!,
                          aspectRatio: constraints.maxWidth / height,
                        )
                      else
                        const Center(
                          child: Text('영상은 Chrome 웹앱에서 재생할 수 있습니다.'),
                        ),
                      // 테두리만 다시 그려서 영상 플레이어가 재생 중 재생성되지 않습니다.
                      ValueListenableBuilder<Duration?>(
                        valueListenable: _focusPosition,
                        builder: (context, position, _) => PlayerFocusOverlay(
                          track: _track,
                          position: position,
                        ),
                      ),
                      if (kIsWeb && _editing)
                        _buildEditLayer(constraints.maxWidth, height),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              _track == null
                  ? '이 영상에서 ${widget.selectedPlayer.name}의 위치는 등록되지 않았습니다.'
                        '${kIsWeb ? ' 아래에서 직접 기록하세요.' : ''}'
                  : '포커스 대상: ${widget.selectedPlayer.name}',
              key: const Key('focus-target'),
            ),
            if (kIsWeb) ...[const SizedBox(height: 8), _buildEditor()],
            const SizedBox(height: 8),
            const Text(
              '영상 출처: YouTube · 기록 출처: TFF, UEFA, PlaymakerStats (2026.9.28 경기).',
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerFocusOverlay extends StatelessWidget {
  const PlayerFocusOverlay({
    super.key,
    required this.track,
    required this.position,
  });

  final PlayerFocusTrack? track;
  final Duration? position;

  @override
  Widget build(BuildContext context) {
    final bounds = position == null ? null : track?.rectangleAt(position!);
    if (bounds == null) return const SizedBox.shrink();
    // 영상의 재생 버튼·탐색 막대를 클릭할 수 있도록 터치 입력을 통과시킵니다.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 좁은 화면에서 생기는 검은 여백을 제외한 16:9 영상 영역입니다.
          final videoSize = applyBoxFit(
            BoxFit.contain,
            const Size(16, 9),
            constraints.biggest,
          ).destination;
          final videoRect = Alignment.center.inscribe(
            videoSize,
            Offset.zero & constraints.biggest,
          );
          return Stack(
            children: [
              Positioned(
                left: videoRect.left + bounds.left * videoRect.width,
                top: videoRect.top + bounds.top * videoRect.height,
                width: bounds.width * videoRect.width,
                height: bounds.height * videoRect.height,
                child: DecoratedBox(
                  key: const Key('player-focus-border'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFFFD600),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class MatchResultPage extends StatelessWidget {
  const MatchResultPage({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('경기 종료 기록')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${player.name}의 경기 기록',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                player.position == '사용자 입력 기록'
                    ? '이 영상에 사용자가 입력한 선수 경기 기록입니다.'
                    : player.goals == null
                    ? '이 영상의 선수 경기 기록은 아직 등록되지 않았습니다.'
                    : '2026.9.28 튀르키예 1–4 이탈리아 경기 기록입니다.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatCard(
                    label: '득점',
                    value: player.goals == null ? '자료 없음' : '${player.goals}골',
                  ),
                  StatCard(
                    label: '도움',
                    value: player.assists == null
                        ? '자료 없음'
                        : '${player.assists}개',
                  ),
                  StatCard(
                    label: '출전 시간',
                    value: player.minutes == null
                        ? '자료 없음'
                        : '${player.minutes}분',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PlayerHighlights(player: player),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('선수 선택으로 돌아가기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddVideoPage extends StatefulWidget {
  const AddVideoPage({super.key, this.storage});

  final HighlightStorage? storage;

  @override
  State<AddVideoPage> createState() => _AddVideoPageState();
}

class _AddVideoPageState extends State<AddVideoPage> {
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _playerController = TextEditingController();
  final _distanceController = TextEditingController();
  final _goalsController = TextEditingController();
  final _assistsController = TextEditingController();
  final _passesController = TextEditingController();
  final _minutesController = TextEditingController();
  late final HighlightStorage _storage;
  List<SavedHighlight> _savedHighlights = [];
  HighlightClip? _selectedVideo;
  String? _saveError;
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? BrowserHighlightStorage();
    unawaited(_loadSavedVideos());
  }

  Future<void> _loadSavedVideos() async {
    try {
      final loaded = await _storage.load();
      if (mounted) setState(() => _savedHighlights = loaded);
    } catch (_) {
      if (mounted) setState(() => _saveError = '저장한 영상을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _descriptionController.dispose();
    _playerController.dispose();
    _distanceController.dispose();
    _goalsController.dispose();
    _assistsController.dispose();
    _passesController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _saveVideo() async {
    final url = _urlController.text.trim();
    final videoId = youtubeVideoIdFromUrl(url);
    final description = _descriptionController.text.trim();
    final playerName = _playerController.text.trim();
    if (url.isEmpty) {
      setState(() => _saveError = 'YouTube 링크를 입력하세요.');
      return;
    }
    if (videoId == null) {
      setState(() => _saveError = '올바른 YouTube 링크를 입력하세요.');
      return;
    }
    if (description.isEmpty) {
      setState(() => _saveError = '설명을 입력하세요.');
      return;
    }
    // 공백만 입력한 선수 이름도 저장하지 않습니다.
    if (playerName.isEmpty) {
      setState(() => _saveError = '선수 이름을 입력하세요.');
      return;
    }

    final updated = [
      ..._savedHighlights,
      SavedHighlight(
        videoId: videoId,
        startSeconds: 0,
        description: description,
        playerName: playerName,
      ),
    ];
    try {
      await _storage.save(updated);
      if (!mounted) return;
      setState(() {
        _savedHighlights = updated;
        _saveError = null;
        _urlController.clear();
        _descriptionController.clear();
        _playerController.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = '저장에 실패했습니다. 브라우저 저장소를 확인하세요.');
      }
    }
  }

  void _clearInputError(String _) {
    if (_saveError != null) setState(() => _saveError = null);
  }

  @override
  Widget build(BuildContext context) {
    final addedVideos = _savedHighlights
        .where((item) => item.endSeconds == null)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube 영상 추가')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('YouTube 링크, 설명, 선수 이름을 입력하세요. 새 영상은 전체 영상으로 재생됩니다.'),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                key: const Key('new-youtube-url'),
                onChanged: _clearInputError,
                decoration: InputDecoration(
                  labelText: 'YouTube 링크',
                  hintText: 'https://www.youtube.com/watch?v=...',
                  errorText: _saveError?.contains('YouTube') == true
                      ? _saveError
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                key: const Key('new-video-description'),
                onChanged: _clearInputError,
                decoration: InputDecoration(
                  labelText: '영상 설명',
                  errorText: _saveError == '설명을 입력하세요.' ? _saveError : null,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _playerController,
                key: const Key('new-video-player'),
                onChanged: _clearInputError,
                decoration: InputDecoration(
                  labelText: '선수 이름',
                  errorText: _saveError == '선수 이름을 입력하세요.' ? _saveError : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_saveError != null &&
                  !_saveError!.contains('YouTube') &&
                  _saveError != '설명을 입력하세요.' &&
                  _saveError != '선수 이름을 입력하세요.') ...[
                Text(
                  _saveError!,
                  key: const Key('new-video-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _loadingSaved ? null : _saveVideo,
                  child: const Text('영상 저장'),
                ),
              ),
              const SizedBox(height: 24),
              Text('추가한 영상', style: Theme.of(context).textTheme.titleLarge),
              if (addedVideos.isEmpty)
                const Text('추가한 영상이 없습니다.')
              else
                for (final item in addedVideos)
                  ListTile(
                    title: Text(item.description),
                    subtitle: Text(
                      'YouTube ${item.videoId} · 전체 영상 · ${item.playerName ?? '선수 미등록'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        _selectedVideo = HighlightClip(
                          title: item.description,
                          rangeLabel: '전체 영상',
                          startSeconds: 0,
                          videoId: item.videoId,
                        );
                      }),
                      child: const Text('재생'),
                    ),
                  ),
              if (_selectedVideo != null) ...[
                const SizedBox(height: 16),
                HighlightVideo(
                  key: ValueKey(_selectedVideo),
                  clip: _selectedVideo!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class VideoHistoryPage extends StatefulWidget {
  const VideoHistoryPage({super.key, this.storage});

  final HighlightStorage? storage;

  @override
  State<VideoHistoryPage> createState() => _VideoHistoryPageState();
}

class _VideoHistoryPageState extends State<VideoHistoryPage> {
  late final HighlightStorage _storage;
  List<SavedHighlight> _savedHighlights = [];
  HighlightClip? _selectedClip;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? BrowserHighlightStorage();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final saved = await _storage.load();
      if (mounted) setState(() => _savedHighlights = saved);
    } catch (_) {
      if (mounted) setState(() => _loadError = '영상 히스토리를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = _savedHighlights.where((item) => item.endSeconds == null);
    final clips = _savedHighlights.where((item) => item.endSeconds != null);
    return Scaffold(
      appBar: AppBar(title: const Text('영상 히스토리')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_loadError != null) Text(_loadError!),
              Text('내가 추가한 영상', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (!_loading && videos.isEmpty)
                const Text('추가한 영상이 없습니다.')
              else
                for (final item in videos)
                  ListTile(
                    title: Text(item.description),
                    subtitle: Text(
                      'YouTube ${item.videoId} · 전체 영상 · ${item.playerName ?? '선수 미등록'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).pop(item),
                      child: const Text('메인에서 보기'),
                    ),
                  ),
              const SizedBox(height: 24),
              Text('저장한 하이라이트', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (!_loading && clips.isEmpty)
                const Text('저장한 하이라이트가 없습니다.')
              else
                for (final item in clips)
                  ListTile(
                    title: Text(item.description),
                    subtitle: Text(
                      'YouTube ${item.videoId} · '
                      '${item.startSeconds.toStringAsFixed(1)}~${item.endSeconds!.toStringAsFixed(1)}초',
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        _selectedClip = HighlightClip(
                          title: item.description,
                          rangeLabel:
                              '${item.startSeconds.toStringAsFixed(1)}~${item.endSeconds!.toStringAsFixed(1)}초',
                          startSeconds: item.startSeconds,
                          endSeconds: item.endSeconds,
                          videoId: item.videoId,
                        );
                      }),
                      child: const Text('재생'),
                    ),
                  ),
              if (_selectedClip != null) ...[
                const SizedBox(height: 16),
                HighlightVideo(
                  key: ValueKey(_selectedClip),
                  clip: _selectedClip!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerHighlights extends StatefulWidget {
  const PlayerHighlights({super.key, required this.player, this.storage});

  final Player player;
  final HighlightStorage? storage;

  @override
  State<PlayerHighlights> createState() => _PlayerHighlightsState();
}

class _PlayerHighlightsState extends State<PlayerHighlights> {
  HighlightClip? _selectedClip;
  final _descriptionController = TextEditingController();
  late final HighlightStorage _storage;
  List<SavedHighlight> _savedHighlights = [];
  String? _saveError;
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? BrowserHighlightStorage();
    unawaited(_loadSavedHighlights());
  }

  Future<void> _loadSavedHighlights() async {
    try {
      final loaded = await _storage.load();
      if (mounted) setState(() => _savedHighlights = loaded);
    } catch (_) {
      if (mounted) setState(() => _saveError = '저장한 하이라이트를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveHighlight() async {
    final clip = _selectedClip;
    final description = _descriptionController.text.trim();
    if (clip == null) {
      setState(() => _saveError = '저장할 영상을 먼저 선택하세요.');
      return;
    }
    if (description.isEmpty) {
      setState(() => _saveError = '설명을 입력하세요.');
      return;
    }

    final updated = [
      ..._savedHighlights,
      SavedHighlight(
        videoId: clip.videoId,
        startSeconds: clip.startSeconds,
        endSeconds: clip.endSeconds,
        description: description,
      ),
    ];
    try {
      await _storage.save(updated);
      if (!mounted) return;
      setState(() {
        _savedHighlights = updated;
        _saveError = null;
        _descriptionController.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = '저장에 실패했습니다. 브라우저 저장소를 확인하세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('하이라이트', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (widget.player.highlights.isEmpty)
          Text('${widget.player.name}의 하이라이트는 아직 등록되지 않았습니다.')
        else ...[
          const Text('장면을 선택한 뒤 영상의 재생 버튼을 누르세요. 아르다 귈러가 등장하는 구간입니다.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final clip in widget.player.highlights)
                ChoiceChip(
                  label: Text('${clip.title} (${clip.rangeLabel})'),
                  selected: clip == _selectedClip,
                  onSelected: (_) => setState(() {
                    _selectedClip = clip;
                    _saveError = null;
                  }),
                ),
            ],
          ),
          if (_selectedClip != null) ...[
            const SizedBox(height: 16),
            HighlightVideo(
              // 다른 장면을 선택하면 이전 재생기를 닫고 새 구간을 준비합니다.
              key: ValueKey(_selectedClip),
              clip: _selectedClip!,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            key: const Key('highlight-description'),
            decoration: const InputDecoration(
              labelText: '하이라이트 설명',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          if (_saveError != null) ...[
            Text(
              _saveError!,
              key: const Key('highlight-save-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: _loadingSaved ? null : _saveHighlight,
            child: const Text('하이라이트 저장'),
          ),
          const SizedBox(height: 24),
          Text('저장한 하이라이트', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_savedHighlights.where((item) => item.endSeconds != null).isEmpty)
            const Text('저장한 하이라이트가 없습니다.')
          else
            for (final item in _savedHighlights.where(
              (item) => item.endSeconds != null,
            ))
              ListTile(
                title: Text(item.description),
                subtitle: Text(
                  'YouTube ${item.videoId} · '
                  '${item.endSeconds == null ? '전체 영상' : '${item.startSeconds.toStringAsFixed(1)}~${item.endSeconds!.toStringAsFixed(1)}초'}',
                ),
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _selectedClip = HighlightClip(
                      title: item.description,
                      rangeLabel: item.endSeconds == null
                          ? '전체 영상'
                          : '${item.startSeconds.toStringAsFixed(1)}~${item.endSeconds!.toStringAsFixed(1)}초',
                      startSeconds: item.startSeconds,
                      endSeconds: item.endSeconds,
                      videoId: item.videoId,
                    );
                    _saveError = null;
                  }),
                  child: const Text('재생'),
                ),
              ),
        ],
      ],
    );
  }
}

class HighlightVideo extends StatefulWidget {
  const HighlightVideo({super.key, required this.clip});

  final HighlightClip clip;

  @override
  State<HighlightVideo> createState() => _HighlightVideoState();
}

class _HighlightVideoState extends State<HighlightVideo> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubeVideoState>? _positionSubscription;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // 경기 영상과 같은 영상 ID여도 재생기의 식별자는 구분합니다.
      _controller = YoutubePlayerController(
        key: 'highlight-${widget.clip.videoId}-${widget.clip.startSeconds}',
        params: const YoutubePlayerParams(showControls: true),
      );
      unawaited(
        _controller!.cueVideoById(
          videoId: widget.clip.videoId,
          startSeconds: widget.clip.startSeconds,
          endSeconds: widget.clip.endSeconds,
        ),
      );
      // 현재 시간 조회 명령을 반복하지 않고 플레이어가 보내는 위치를 감시합니다.
      _positionSubscription = _controller!.videoStateStream.listen((state) {
        final endSeconds = widget.clip.endSeconds;
        final seconds =
            state.position.inMicroseconds / Duration.microsecondsPerSecond;
        if (endSeconds != null && !_stopping && seconds >= endSeconds) {
          _stopping = true;
          unawaited(_controller!.pauseVideo());
        }
      });
    }
  }

  Future<void> _replay() async {
    // 전체 영상의 처음이 아니라 선택한 장면부터 다시 재생합니다.
    _stopping = false;
    await _controller?.loadVideoById(
      videoId: widget.clip.videoId,
      startSeconds: widget.clip.startSeconds,
      endSeconds: widget.clip.endSeconds,
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '선택 장면: ${widget.clip.title}',
          key: const Key('selected-highlight'),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth,
            height: (constraints.maxWidth * 9 / 16).clamp(200, double.infinity),
            child: _controller == null
                ? const Center(
                    child: Text('YouTube 하이라이트는 Chrome에서 재생할 수 있습니다.'),
                  )
                : YoutubePlayer(controller: _controller!),
          ),
        ),
        const SizedBox(height: 8),
        Text('지정 구간: ${widget.clip.rangeLabel}'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _controller == null ? null : _replay,
          icon: const Icon(Icons.replay),
          label: const Text('이 장면 다시 재생'),
        ),
      ],
    );
  }
}
