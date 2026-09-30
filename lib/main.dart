import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

// 실제 선수 정보가 아닌 학습용 가상 데이터입니다.
class Player {
  const Player({
    required this.name,
    required this.position,
    required this.distanceKm,
    required this.goals,
    required this.assists,
    required this.passes,
    required this.minutes,
  });

  final String name;
  final String position;
  final double distanceKm;
  final int goals;
  final int assists;
  final int passes;
  final int minutes;
}

const players = [
  Player(
    name: '아무개',
    position: '공격수',
    distanceKm: 8.4,
    goals: 2,
    assists: 1,
    passes: 32,
    minutes: 90,
  ),
  Player(
    name: '누군가',
    position: '미드필더',
    distanceKm: 10.2,
    goals: 0,
    assists: 2,
    passes: 68,
    minutes: 85,
  ),
  Player(
    name: '어떤이',
    position: '수비수',
    distanceKm: 7.6,
    goals: 0,
    assists: 0,
    passes: 45,
    minutes: 90,
  ),
];

class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  Player _selectedPlayer = players.first;
  bool _resultOpened = false;

  Future<void> _showResult() async {
    if (_resultOpened || !mounted) return;
    _resultOpened = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchResultPage(player: _selectedPlayer),
      ),
    );
    _resultOpened = false;
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('실제 경기 영상 · 선수 이름과 기록은 학습용 가상 데이터입니다.'),
              const SizedBox(height: 24),
              Text(
                '1. 집중해서 볼 선수',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              // 하나의 상태값만 사용하므로 한 번에 한 선수만 선택됩니다.
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final player in players)
                    ChoiceChip(
                      label: Text('${player.name} · ${player.position}'),
                      selected: player == _selectedPlayer,
                      onSelected: (_) {
                        setState(() => _selectedPlayer = player);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '선택 선수: ${_selectedPlayer.name}',
                key: const Key('selected-player'),
              ),
              const SizedBox(height: 24),
              YouTubeMatchVideo(onEnded: _showResult),
              const SizedBox(height: 24),
              Text(
                '2. ${_selectedPlayer.name}의 경기 정보',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('영상에 연동되지 않은 고정 예시 기록입니다.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatCard(
                    label: '이동 거리',
                    value:
                        '${_selectedPlayer.distanceKm.toStringAsFixed(1)} km',
                  ),
                  StatCard(label: '골', value: '${_selectedPlayer.goals}골'),
                  StatCard(label: '어시스트', value: '${_selectedPlayer.assists}개'),
                  StatCard(label: '패스', value: '${_selectedPlayer.passes}회'),
                ],
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 53)),
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('경기 종료 기록 미리보기'),
                  onPressed: _showResult,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class YouTubeMatchVideo extends StatefulWidget {
  const YouTubeMatchVideo({super.key, required this.onEnded});

  final VoidCallback onEnded;

  @override
  State<YouTubeMatchVideo> createState() => _YouTubeMatchVideoState();
}

class _YouTubeMatchVideoState extends State<YouTubeMatchVideo> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _playerSubscription;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // 사용자가 지정한 영상만 불러오고, 자동 재생은 하지 않습니다.
      _controller = YoutubePlayerController.fromVideoId(
        videoId: '9wx0QPdlPc8',
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
        ),
      );
      // 영상 종료 이벤트가 오면 선택 선수의 경기 종료 화면을 엽니다.
      _playerSubscription = _controller!.listen((value) {
        if (value.playerState == PlayerState.ended) widget.onEnded();
      });
    }
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _controller?.close();
    super.dispose();
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
            const Text('SPOTV FOOTBALL · 튀르키예 vs 이탈리아 하이라이트'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final aspectHeight = constraints.maxWidth * 9 / 16;
                // YouTube 플레이어는 높이가 최소 200px이어야 합니다.
                final height = aspectHeight < 200 ? 200.0 : aspectHeight;
                return SizedBox(
                  width: double.infinity,
                  height: height,
                  child: kIsWeb
                      ? YoutubePlayer(
                          key: const ValueKey('youtube-match-player'),
                          controller: _controller!,
                          aspectRatio: constraints.maxWidth / height,
                        )
                      : const Center(
                          child: Text('영상은 Chrome 웹앱에서 재생할 수 있습니다.'),
                        ),
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('영상 출처: YouTube. 선수 이름과 경기 기록은 영상과 무관한 가상 데이터입니다.'),
          ],
        ),
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
              const Text('가상 기록으로 만든 경기 종료 화면 미리보기입니다.'),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatCard(label: '득점', value: '${player.goals}골'),
                  StatCard(label: '도움', value: '${player.assists}개'),
                  StatCard(label: '출전 시간', value: '${player.minutes}분'),
                ],
              ),
              const SizedBox(height: 24),
              const Text('하이라이트는 사용할 YouTube 영상을 확정한 뒤 연결합니다.'),
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
