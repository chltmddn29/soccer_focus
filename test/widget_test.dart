import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_planner/main.dart';

class MemoryHighlightStorage implements HighlightStorage {
  List<SavedHighlight> items = [];

  @override
  Future<List<SavedHighlight>> load() async => List.of(items);

  @override
  Future<void> save(List<SavedHighlight> highlights) async =>
      items = List.of(highlights);
}

class MemorySoccerStorage extends BrowserHighlightStorage {
  List<SoccerItem> items = [];

  @override
  Future<List<SoccerItem>> loadItems() async => List.of(items);

  @override
  Future<void> saveItems(List<SoccerItem> updated) async =>
      items = List.of(updated);
}

void main() {
  testWidgets('경기 추가·완료·삭제 상태와 순서를 다시 불러온다', (tester) async {
    final storage = MemorySoccerStorage();
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SoccerItemList(key: UniqueKey(), storage: storage),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    await tester.tap(find.text('경기 추가'));
    await tester.pump();
    expect(find.text('경기 제목을 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    for (final title in ['첫 경기', '둘째 경기', '셋째 경기']) {
      await tester.enterText(find.byKey(const Key('match-title-input')), title);
      await tester.tap(find.text('경기 추가'));
      await tester.pumpAndSettle();
    }
    expect(storage.items.map((item) => item.title).toList(), [
      '첫 경기',
      '둘째 경기',
      '셋째 경기',
    ]);
    await show();
    expect(find.text('첫 경기'), findsOneWidget);
    expect(find.text('둘째 경기'), findsOneWidget);
    expect(find.text('셋째 경기'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('삭제').first);
    await tester.pumpAndSettle();
    await show();
    expect(storage.items.map((item) => item.title).toList(), [
      '둘째 경기',
      '셋째 경기',
    ]);
    expect(storage.items.first.completed, isTrue);
    expect(find.text('첫 경기'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });

  test('YouTube 주소에서 영상 ID만 추출하고 다른 도메인은 거부한다', () {
    expect(
      youtubeVideoIdFromUrl(
        'https://www.youtube.com/watch?si=example&v=AbC123_xY-z&t=40',
      ),
      'AbC123_xY-z',
    );
    expect(
      youtubeVideoIdFromUrl('https://youtu.be/AbC123_xY-z'),
      'AbC123_xY-z',
    );
    expect(
      youtubeVideoIdFromUrl('https://youtube.com/shorts/AbC123_xY-z'),
      'AbC123_xY-z',
    );
    expect(
      youtubeVideoIdFromUrl(
        'https://youtube.com.evil.test/watch?v=AbC123_xY-z',
      ),
      isNull,
    );
    expect(youtubeVideoIdFromUrl('https://example.com/video'), isNull);
  });

  testWidgets('영상 추가 페이지에서 새 YouTube 링크를 저장하고 재생을 선택한다', (tester) async {
    final storage = MemoryHighlightStorage();
    await tester.pumpWidget(MaterialApp(home: AddVideoPage(storage: storage)));
    await tester.pumpAndSettle();

    final urlField = find.byKey(const Key('new-youtube-url'));
    final descriptionField = find.byKey(const Key('new-video-description'));
    final playerField = find.byKey(const Key('new-video-player'));
    final saveButton = find.text('영상 저장');
    Future<void> tapSave() async {
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pump();
    }

    await tapSave();
    expect(find.text('YouTube 링크를 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    await tester.enterText(urlField, '   ');
    await tester.enterText(descriptionField, '   ');
    await tester.enterText(playerField, '   ');
    await tapSave();
    expect(find.text('YouTube 링크를 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    await tester.enterText(urlField, 'https://example.com/watch?v=AbC123_xY-z');
    await tester.enterText(descriptionField, '새 영상');
    await tapSave();
    expect(find.text('올바른 YouTube 링크를 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    await tester.enterText(
      urlField,
      'https://www.youtube.com/watch?v=AbC123_xY-z&t=40',
    );
    await tester.enterText(descriptionField, '   ');
    await tapSave();
    expect(find.text('설명을 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);
    await tester.enterText(descriptionField, '새 영상');
    await tapSave();
    expect(find.text('선수 이름을 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);
    await tester.enterText(playerField, '  아르다 귈러  ');
    await tapSave();
    expect(storage.items.single.videoId, 'AbC123_xY-z');
    expect(storage.items.single.startSeconds, 0);
    expect(storage.items.single.endSeconds, isNull);
    expect(storage.items.single.playerName, '아르다 귈러');
    expect(storage.items.single.toJson().keys, {
      'videoId',
      'startSeconds',
      'description',
      'playerName',
    });
    expect(find.text('새 영상'), findsOneWidget);

    await tester.ensureVisible(find.text('재생'));
    await tester.tap(find.text('재생'));
    await tester.pump();
    final selected = tester.widget<HighlightVideo>(find.byType(HighlightVideo));
    expect(selected.clip.videoId, 'AbC123_xY-z');
    expect(selected.clip.endSeconds, isNull);
  });

  testWidgets('영상 추가는 첫 화면에서 열리고 돌아오면 빈 상태다', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('YouTube 영상 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(AddVideoPage), findsOneWidget);
    expect(find.byKey(const Key('new-youtube-url')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-player')), findsNothing);
    expect(find.byType(StatCard), findsNothing);
    expect(find.byKey(const Key('new-youtube-url')), findsNothing);
  });

  testWidgets('영상 미선택과 빈 설명을 거부하고 저장 목록을 다시 불러온다', (tester) async {
    final storage = MemoryHighlightStorage();
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerHighlights(
              key: UniqueKey(),
              player: players.first,
              storage: storage,
            ),
          ),
        ),
      ),
    );
    Future<void> tapSave() async {
      final button = find.text('하이라이트 저장');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
    }

    await show();
    await tester.pumpAndSettle();
    await tapSave();
    expect(find.text('저장할 영상을 먼저 선택하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    await tester.ensureVisible(find.text('아르다 귈러 · 초반 장면 (0:23.5~0:32.0)'));
    await tester.tap(find.text('아르다 귈러 · 초반 장면 (0:23.5~0:32.0)'));
    await tester.pump();
    await tapSave();
    expect(find.text('설명을 입력하세요.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('highlight-description')),
      '   ',
    );
    await tapSave();
    expect(find.text('설명을 입력하세요.'), findsOneWidget);
    expect(storage.items, isEmpty);

    await tester.enterText(
      find.byKey(const Key('highlight-description')),
      '  패스 장면  ',
    );
    await tapSave();
    expect(find.text('패스 장면'), findsOneWidget);
    expect(storage.items.single.description, '패스 장면');
    expect(storage.items.single.videoId, '9wx0QPdlPc8');
    expect(storage.items.single.startSeconds, 23.5);
    expect(storage.items.single.endSeconds, 32);
    expect(storage.items.single.toJson().keys, {
      'videoId',
      'startSeconds',
      'endSeconds',
      'description',
    });

    await show();
    await tester.pumpAndSettle();
    expect(find.text('패스 장면'), findsOneWidget);
  });

  test('확인한 장면 안에서만 위치를 연결하고 장면 사이에서는 숨긴다', () {
    Rect? at(int milliseconds) =>
        turkeyNumber10Track.rectangleAt(Duration(milliseconds: milliseconds));

    expect(at(0), isNull);
    expect(at(23499), isNull);
    expect(at(23500), const FocusSample(23.5, 361, 269, 30, 67).bounds);
    expect(at(23750)!.left, closeTo(365 / 980, 0.000001));
    expect(at(32000), isNotNull);
    expect(at(32001), isNull);
    expect(at(100000), isNull);
    expect(at(188999), isNull);
    expect(at(189000), isNotNull);
    expect(at(197500), isNotNull);
    expect(at(197501), isNull);
    // 뒤로 탐색해도 이전 호출의 위치에 영향을 받지 않습니다.
    expect(at(25000), const FocusSample(25, 375, 274, 34, 72).bounds);
  });

  testWidgets('영상 여백과 화면 크기를 반영하며 재생 조작을 가리지 않는다', (tester) async {
    var videoTaps = 0;
    Future<void> show(Size size) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => videoTaps++,
                    child: const ColoredBox(color: Colors.black),
                  ),
                  const PlayerFocusOverlay(
                    track: turkeyNumber10Track,
                    position: Duration(seconds: 25),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final border = find.byKey(const Key('player-focus-border'));
    await show(const Size(490, 275.625));
    expect(tester.getSize(border).width, closeTo(17, 0.001));
    final wideOrigin = tester.getTopLeft(find.byType(Stack).first);
    expect(tester.getTopLeft(border).dx - wideOrigin.dx, closeTo(187.5, 0.001));
    await tester.tapAt(tester.getCenter(border));
    expect(videoTaps, 1);

    await show(const Size(240, 200));
    final narrowOrigin = tester.getTopLeft(find.byType(Stack).first);
    // 240px 폭의 16:9 영상은 높이 135px, 위쪽 검은 여백은 32.5px입니다.
    expect(
      tester.getTopLeft(border).dy - narrowOrigin.dy,
      closeTo(32.5 + 274 / 551 * 135, 0.001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('위치 미등록 구간과 다른 선수에는 테두리를 표시하지 않는다', (tester) async {
    Future<void> show(PlayerFocusTrack? track, Duration? position) =>
        tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 490,
              height: 276,
              child: PlayerFocusOverlay(track: track, position: position),
            ),
          ),
        );
    final border = find.byKey(const Key('player-focus-border'));
    await show(turkeyNumber10Track, const Duration(seconds: 25));
    expect(border, findsOneWidget);
    await show(null, const Duration(seconds: 25));
    expect(border, findsNothing);
    await show(turkeyNumber10Track, const Duration(seconds: 33));
    expect(border, findsNothing);
    await show(turkeyNumber10Track, null);
    expect(border, findsNothing);
  });

  testWidgets('선수 이름은 고정 명단에 제한되지 않고 빈칸이면 선택을 지운다', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    expect(find.text('축구선수 포커스'), findsOneWidget);
    expect(find.byKey(const Key('selected-player')), findsNothing);
    expect(find.byType(StatCard), findsNothing);
    expect(find.text('경기 종료 기록 미리보기'), findsNothing);
    expect(find.textContaining('2026.9.28 튀르키예'), findsNothing);
    expect(find.textContaining('선택한 영상이 없습니다.'), findsNothing);

    await tester.enterText(find.byKey(const Key('player-name-input')), '새 선수');
    await tester.pumpAndSettle();
    expect(find.text('선택 선수: 새 선수'), findsOneWidget);
    expect(find.byType(StatCard), findsNothing);
    await tester.enterText(find.byKey(const Key('player-name-input')), '   ');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-player')), findsNothing);
    expect(find.byType(StatCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('종료 기록은 선택 선수를 따르며 돌아와도 선택이 유지된다', (tester) async {
    final storage = MemoryHighlightStorage()
      ..items = [
        const SavedHighlight(
          videoId: '9wx0QPdlPc8',
          startSeconds: 0,
          description: '경기 영상',
          playerName: '바르쉬 알페르 이을마즈',
        ),
      ];
    await tester.pumpWidget(MaterialApp(home: MatchPage(storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상 히스토리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메인에서 보기'));
    await tester.pumpAndSettle();
    expect(find.text('선택 선수: 바르쉬 알페르 이을마즈'), findsOneWidget);
    final preview = find.text('경기 종료 기록 미리보기');
    await tester.scrollUntilVisible(
      preview,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.ancestor(of: preview, matching: find.byType(FilledButton)),
          )
          .height,
      53,
    );
    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(find.text('바르쉬 알페르 이을마즈의 경기 기록'), findsOneWidget);
    expect(find.text('1골'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
    expect(find.text('80분'), findsOneWidget);
    expect(find.text('2026.9.28 튀르키예 1–4 이탈리아 경기 기록입니다.'), findsOneWidget);

    await tester.tap(find.text('선수 선택으로 돌아가기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('선택 선수: 바르쉬 알페르 이을마즈'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('선택 선수: 바르쉬 알페르 이을마즈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다른 영상은 저장된 선수 이름을 사용하고 이전 경기 수치를 붙이지 않는다', (tester) async {
    final storage = MemoryHighlightStorage()
      ..items = [
        const SavedHighlight(
          videoId: 'AbC123_xY-z',
          startSeconds: 0,
          description: '새 경기',
          playerName: '새 선수',
        ),
      ];
    await tester.pumpWidget(MaterialApp(home: MatchPage(storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상 히스토리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메인에서 보기'));
    await tester.pumpAndSettle();
    expect(find.text('선택 선수: 새 선수'), findsOneWidget);
    expect(find.textContaining('2026.9.28 튀르키예'), findsNothing);
    expect(find.text('0골'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('경기 종료 기록 미리보기'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('자료 없음'), findsNWidgets(4));
  });

  testWidgets('영상에 입력한 선수 기록을 시청 화면과 종료 화면에서 본다', (tester) async {
    final storage = MemoryHighlightStorage()
      ..items = [
        const SavedHighlight(
          videoId: 'AbC123_xY-z',
          startSeconds: 0,
          description: '새 경기',
          playerName: '새 선수',
          distanceKm: 8.5,
          goals: 2,
          assists: 1,
          passes: 54,
          minutes: 90,
        ),
      ];
    await tester.pumpWidget(MaterialApp(home: MatchPage(storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상 히스토리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메인에서 보기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('경기 종료 기록 미리보기'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (final value in ['8.5 km', '2골', '1개', '54회']) {
      expect(find.text(value), findsOneWidget);
    }
    await tester.tap(find.text('경기 종료 기록 미리보기'));
    await tester.pumpAndSettle();
    expect(find.text('새 선수의 경기 기록'), findsOneWidget);
    expect(find.text('2골'), findsOneWidget);
    expect(find.text('1개'), findsOneWidget);
    expect(find.text('90분'), findsOneWidget);
    expect(find.text('이 영상에 사용자가 입력한 선수 경기 기록입니다.'), findsOneWidget);
  });

  testWidgets('좁은 화면에서도 선수 변경과 종료 기록을 확인할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryHighlightStorage()
      ..items = [
        const SavedHighlight(
          videoId: '9wx0QPdlPc8',
          startSeconds: 0,
          description: '경기 영상',
          playerName: '오우즈 아이든',
        ),
      ];
    await tester.pumpWidget(MaterialApp(home: MatchPage(storage: storage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상 히스토리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메인에서 보기'));
    await tester.pumpAndSettle();
    final preview = find.text('경기 종료 기록 미리보기');
    await tester.scrollUntilVisible(
      preview,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('오우즈 아이든의 경기 기록'), findsOneWidget);
    expect(find.text('90분'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('하이라이트를 하나씩 선택하고 다른 선수에는 표시하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(375, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: MatchResultPage(player: players.first)),
    );
    expect(find.byType(HighlightVideo), findsNothing);
    for (final clip in turkeyNumber10Highlights) {
      final chip = find.widgetWithText(
        ChoiceChip,
        '${clip.title} (${clip.rangeLabel})',
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        tester.widget<HighlightVideo>(find.byType(HighlightVideo)).clip,
        clip,
      );
      expect(find.text('선택 장면: ${clip.title}'), findsOneWidget);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected)
            .length,
        1,
      );
      expect(find.byType(MatchResultPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: MatchResultPage(key: const ValueKey('other'), player: players[1]),
      ),
    );
    expect(find.text('바르쉬 알페르 이을마즈의 하이라이트는 아직 등록되지 않았습니다.'), findsOneWidget);
    expect(find.byType(HighlightVideo), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  test('사용자가 기록한 위치는 3초 이내면 이어 붙이고 더 멀면 장면을 나눈다', () {
    final samples = [
      FocusSample.fromRect(10, const Rect.fromLTWH(0.1, 0.1, 0.1, 0.2)),
      FocusSample.fromRect(11, const Rect.fromLTWH(0.2, 0.1, 0.1, 0.2)),
      FocusSample.fromRect(20, const Rect.fromLTWH(0.5, 0.5, 0.1, 0.2)),
    ];
    final segments = groupFocusSamples(samples.reversed.toList());
    expect(segments.length, 2);
    final track = PlayerFocusTrack(label: '테스트', segments: segments);
    expect(
      track.rectangleAt(const Duration(milliseconds: 10500))!.left,
      closeTo(0.15, 0.000001),
    );
    expect(track.rectangleAt(const Duration(seconds: 15)), isNull);
    // 기록이 하나뿐인 장면은 앞뒤 0.5초만 보입니다.
    expect(track.rectangleAt(const Duration(milliseconds: 20400)), isNotNull);
    expect(track.rectangleAt(const Duration(milliseconds: 20600)), isNull);
  });

  test('포커스 기록은 JSON으로 저장하고 잘못된 값은 버린다', () {
    final sample = FocusSample.fromRect(
      1.5,
      const Rect.fromLTWH(0.25, 0.5, 0.1, 0.2),
    );
    final restored = FocusSample.fromJson(sample.toJson())!;
    expect(restored.seconds, 1.5);
    expect(restored.bounds.left, closeTo(0.25, 0.000001));
    expect(FocusSample.fromJson([1, 2, 3]), isNull);
    expect(FocusSample.fromJson([1, 0, 0, 0, 5]), isNull);
    expect(FocusSample.fromJson('x'), isNull);
  });
}
