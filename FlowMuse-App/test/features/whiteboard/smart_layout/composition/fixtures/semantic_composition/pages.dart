/// 独立于生成器/模型的 8 开发 + 4 留出页真值；不包含排名期望分数。
class EffectPage {
  const EffectPage(
    this.name,
    this.order,
    this.texts,
    this.groups, {
    this.titles = const {'title'},
    this.captions = const {},
    this.lists = const {},
    this.sections = const {},
    this.soft = const {},
    this.missing = const {},
    this.portrait = const {},
    this.fixed = false,
    this.alreadyGood = false,
    this.holdout = false,
    this.height = 1400,
  });
  final String name;
  final List<String> order;
  final Map<String, String> texts;
  final List<List<String>> groups;
  final Set<String> titles, lists, missing, portrait;
  final Map<String, String> captions, sections;
  final Map<String, List<int>> soft;
  final bool fixed, alreadyGood, holdout;
  final double height;
}

const effectPages = <EffectPage>[
  EffectPage(
    '01-双图双说明',
    ['title', 'cat', 'cat-note', 'dog', 'dog-note'],
    {'title': '动物观察笔记', 'cat-note': '这是躺着的小猫。', 'dog-note': '这是草地上的小狗。'},
    [
      ['cat', 'cat-note'],
      ['dog', 'dog-note'],
    ],
    captions: {'cat-note': 'cat', 'dog-note': 'dog'},
  ),
  EffectPage(
    '02-交叉摆放',
    ['title', 'red', 'red-note', 'blue', 'blue-note'],
    {'title': '颜色与形态', 'red-note': '红色对象的轮廓柔和。', 'blue-note': '蓝色对象具有另一种结构。'},
    [
      ['red', 'red-note'],
      ['blue', 'blue-note'],
    ],
  ),
  EffectPage(
    '03-单图长正文图注',
    ['title', 'figure', 'caption', 'body'],
    {
      'title': '观察记录',
      'caption': '图一：局部结构。',
      'body':
          '我们先观察整体，再比较细节。图像中的位置关系可以帮助理解这段说明，但不能代替完整的文字内容。'
          '每一个结论都需要对照原始记录，保留不确定之处。再次观察时，应注意形态、颜色和方向发生的变化。'
          '这是一段连续正文，应该形成自然可读的段落，而不是被挤成一条细长的文字列。',
    },
    [
      ['figure', 'caption', 'body'],
    ],
    captions: {'caption': 'figure'},
  ),
  EffectPage(
    '04-两图共同说明',
    ['title', 'left', 'right', 'shared'],
    {'title': '同一种现象的两个视角', 'shared': '两幅图共同展示观察对象，说明只需要出现一次。'},
    [
      ['left', 'right', 'shared'],
    ],
  ),
  EffectPage(
    '05-章节与列表',
    ['title', 'item1', 'item2', 'figure', 'section2', 'body'],
    {
      'title': '一、观察步骤',
      'item1': '1. 先看整体轮廓。',
      'item2': '2. 再比较局部结构。',
      'section2': '二、整理结论',
      'body': '把共同特征记录下来，保留不同点。',
    },
    [
      ['item1', 'item2', 'figure'],
    ],
    titles: {'title', 'section2'},
    lists: {'item1', 'item2'},
    sections: {
      'title': 's1',
      'item1': 's1',
      'item2': 's1',
      'figure': 's1',
      'section2': 's2',
      'body': 's2',
    },
  ),
  EffectPage(
    '06-软换行与硬换行',
    ['title', 'cjk', 'latin', 'native'],
    {
      'title': '文字换行对照',
      'cjk': '这是躺\n着的小\n猫。',
      'latin': 'New\nYork is a city.',
      'native': '保留这一个硬换行\n它是用户主动分段。',
    },
    [],
    soft: {
      'cjk': [0, 1],
      'latin': [0],
    },
  ),
  EffectPage(
    '07-缺资产与固定对象',
    ['title', 'missing', 'caption', 'valid', 'body'],
    {'title': '部分整理', 'caption': '缺失资源的说明保持原位。', 'body': '这张可用图片与说明可以一起整理。'},
    [
      ['missing', 'caption'],
      ['valid', 'body'],
    ],
    captions: {'caption': 'missing'},
    missing: {'missing'},
    fixed: true,
  ),
  EffectPage(
    '08-已经排好',
    ['title', 'one', 'first', 'two', 'second'],
    {'title': '排好的观察笔记', 'first': '第一张图片的简短说明。', 'second': '第二张图片的简短说明。'},
    [
      ['one', 'first'],
      ['two', 'second'],
    ],
    alreadyGood: true,
  ),
  // 留出页只验收，不作为按页名补特判的参数来源。
  EffectPage(
    '09-更换主题位置',
    ['title', 'leaf', 'leaf-note', 'stone', 'stone-note'],
    {
      'title': '植物和矿物',
      'leaf-note': '叶片边缘呈弧形，颜色较浅。',
      'stone-note': '石块表面粗糙，具有不规则纹理。',
    },
    [
      ['leaf', 'leaf-note'],
      ['stone', 'stone-note'],
    ],
    holdout: true,
  ),
  EffectPage(
    '10-横竖三组',
    ['title', 'wide', 'wide-note', 'tall', 'tall-note', 'third', 'third-note'],
    {
      'title': '三种观察对象',
      'wide-note': '横向观察。',
      'tall-note': '竖向结构的补充说明。',
      'third-note': '第三个对象也需要完整保留。',
    },
    [
      ['wide', 'wide-note'],
      ['tall', 'tall-note'],
      ['third', 'third-note'],
    ],
    portrait: {'tall'},
    holdout: true,
  ),
  EffectPage(
    '11-讲义正文列表配图',
    ['title', 'intro', 'step1', 'step2', 'figure', 'caption', 'end'],
    {
      'title': '从观察到结论',
      'intro':
          '在进行比较之前，我们需要记录对象的基本特征。清楚的文字层级能够帮助读者按照顺序理解这些信息。'
          '说明既不能与图片失去联系，也不应占据过窄的区域。每段内容都有自己的重点，整理时必须完整保留原来的意思。',
      'step1': '1. 记录对象的形态、大小与方向。',
      'step2': '2. 找出共同点，并记录仍然存在的差异。',
      'caption': '图示用于解释上面的观察步骤。',
      'end':
          '结论不是图像本身，应该在阅读完记录后再形成。'
          '保留这段较长的补充说明，可以避免把复杂内容误认为几个互不相关的标签。',
    },
    [
      ['step1', 'step2', 'figure', 'caption'],
    ],
    lists: {'step1', 'step2'},
    captions: {'caption': 'figure'},
    holdout: true,
    height: 1800,
  ),
  EffectPage(
    '12-图形箭头与保留对象',
    ['title', 'figure', 'body'],
    {'title': '混合记录', 'body': '文字和图片可以整理，但已有的图形与箭头关系必须保持。'},
    [
      ['figure', 'body'],
    ],
    fixed: true,
    holdout: true,
  ),
];
