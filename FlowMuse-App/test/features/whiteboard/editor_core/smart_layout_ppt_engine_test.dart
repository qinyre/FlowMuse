import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 内容区 100,100 宽400 高300；有配图时：textWidth=400*0.62-12=236，figureLeft=100+236+24=360，figureWidth=140
  const area = Rect.fromLTWH(100, 100, 400, 300);

  PptLayoutResult? run(List<PptGroupItem> groups, Map<String, PptUnit> units) {
    return PptLayoutEngine.place(
      contentArea: area,
      groups: groups,
      units: units,
      occupied: const [],
    );
  }

  test('无配图时单列自上而下、左对齐排布', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
        PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
        'g2': PptUnit(key: 'g2', size: Size(300, 60)),
      },
    );
    expect(result, isNotNull);
    final targets = result!.targets;
    expect(targets['g1'], const Offset(100, 100));
    expect(targets['g2'], const Offset(100, 164)); // 100+40+24
  });

  test('存在配图时双列：文字列左、配图列右', () {
    final result = run(
      const [
        PptGroupItem(key: 'title', role: 'title', memberKeys: ['title']),
        PptGroupItem(key: 'img', role: 'figure', memberKeys: ['img']),
      ],
      const {
        'title': PptUnit(key: 'title', size: Size(200, 40)),
        'img': PptUnit(key: 'img', size: Size(120, 60)),
      },
    );
    expect(result, isNotNull);
    expect(result!.targets['title'], const Offset(100, 100));
    expect(result.targets['img'], const Offset(360, 100));
  });

  test('单元超出列宽返回 null', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(500, 40)),
      },
    );
    expect(result, isNull);
  });

  test('总高超内容区返回 null', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
        PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
        PptGroupItem(key: 'g3', role: 'body', memberKeys: ['g3']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(100, 120)),
        'g2': PptUnit(key: 'g2', size: Size(100, 120)),
        'g3': PptUnit(key: 'g3', size: Size(100, 120)),
      },
    );
    // 100+120+24+120+24+120 = 508 > 400（contentArea.bottom）
    expect(result, isNull);
  });

  test('与障碍相交时整体下移避开', () {
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      units: const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      },
      occupied: const [Rect.fromLTWH(100, 100, 200, 20)],
    );
    expect(result, isNotNull);
    expect(result!.targets['g1'], const Offset(100, 124)); // 下移一步
  });

  test('下移超过上限仍冲突返回 null', () {
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      units: const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      },
      occupied: const [
        // 覆盖整个内容区，任何位置都碰撞（下移也会越界）
        Rect.fromLTWH(100, 100, 400, 300),
      ],
    );
    expect(result, isNull);
  });

  test('配图略宽于默认列时自适应加宽配图列仍成功', () {
    // 默认：textWidth=236, figureLeft=360, figureWidth=140；配图 200 > 140 → 自适应
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'title', role: 'title', memberKeys: ['title']),
        PptGroupItem(key: 'img', role: 'figure', memberKeys: ['img']),
      ],
      units: const {
        'title': PptUnit(key: 'title', size: Size(200, 40)),
        'img': PptUnit(key: 'img', size: Size(200, 60)),
      },
      occupied: const [],
    );
    expect(result, isNotNull);
    // 配图列宽 = 200，紧贴右缘；文本列 = 400-200-24 = 176 ≥ 200？不满足 → 单列回落
    // 这里 textNeeded=200，adaptiveFigureWidth=400-24-200=176 < 200 → 单列全宽堆叠
    final targets = result!.targets;
    expect(targets['title'], const Offset(100, 100));
    expect(targets['img'], const Offset(100, 164)); // 单列：图在文本下方
  });

  test('配图超出默认列但文本列适配时按实际宽度分栏', () {
    // area 宽 400 高 1000：默认 textWidth=236、figureWidth=140、figureLeft=360
    // 配图 300、文本 120：adaptiveFigureWidth=400-24-120=256 < 300 → 单列回落
    final result = PptLayoutEngine.place(
      contentArea: const Rect.fromLTWH(100, 100, 400, 1000),
      groups: const [
        PptGroupItem(key: 'title', role: 'title', memberKeys: ['title']),
        PptGroupItem(key: 'img', role: 'figure', memberKeys: ['img']),
      ],
      units: const {
        'title': PptUnit(key: 'title', size: Size(120, 40)),
        'img': PptUnit(key: 'img', size: Size(300, 60)),
      },
      occupied: const [],
    );
    expect(result, isNotNull);
    expect(result!.targets['img'], const Offset(100, 164));
  });

  test('大到单列也放不下时返回 null（真正没有空间）', () {
    // 配图 500 > 内容区宽 400 → 单列也失败
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
        PptGroupItem(key: 'img', role: 'figure', memberKeys: ['img']),
      ],
      units: const {
        'g1': PptUnit(key: 'g1', size: Size(100, 40)),
        'img': PptUnit(key: 'img', size: Size(500, 60)),
      },
      occupied: const [],
    );
    expect(result, isNull);
  });

  test('确定性：同一输入两次结果相同', () {
    const groups = [
      PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
    ];
    const units = {
      'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      'g2': PptUnit(key: 'g2', size: Size(300, 60)),
    };
    final first = run(groups, units);
    final second = run(groups, units);
    expect(first!.targets, second!.targets);
  });
}
