import 'package:flutter/foundation.dart';

enum GuideTopic {
  start('快速开始', '从第一笔，开始'),
  writing('书写与画布', '让记录跟上你的想法'),
  pdf('PDF 阅读与批注', '把理解，写在资料旁'),
  collaboration('实时协作', '在同一页上，一起思考'),
  smart('智能工具', '把记录，变成更清晰的内容'),
  library('笔记管理', '让每个想法都有位置'),
  backup('备份与偏好', '按自己的习惯，安心记录'),
  messages('好友与提醒', '让讨论和邀请接得上');

  const GuideTopic(this.label, this.headline);
  final String label, headline;

  static GuideTopic? fromSlug(String? slug) =>
      values.where((topic) => topic.name == slug).firstOrNull;
}

enum GuideAction { createNote, library, social, stylus, ai, backup }

@immutable
class GuideSection {
  const GuideSection(this.title, this.steps);
  final String title;
  final List<String> steps;
}

@immutable
class GuideArticle {
  const GuideArticle({
    required this.summary,
    required this.sections,
    required this.note,
    required this.action,
    required this.actionLabel,
  });
  final String summary, note, actionLabel;
  final List<GuideSection> sections;
  final GuideAction action;
}

const guideArticles = <GuideTopic, GuideArticle>{
  GuideTopic.start: GuideArticle(
    summary: '从手写笔记、PDF 批注到多人协作，FlowMuse 把记录与讨论留在同一块画布上。选一个入口，先完成自己的第一份记录。',
    sections: [
      GuideSection('写下第一份笔记', [
        '在“全部笔记”点击“新建笔记”，填写名称并选择分页或无限画布。',
        '分页适合课堂、阅读和逐页整理；无限画布适合自由构思与关系图。',
        '选择模板后点击“创建”，进入白板即可开始记录。',
      ]),
      GuideSection('在资料上做批注', [
        '在新建笔记页面点击“导入 PDF”，选取文件后等待页面导入。',
        '使用画笔、文字和选框补充批注；导入的页面作为阅读底图保留。',
      ]),
      GuideSection('邀请别人一起写', [
        '打开一份笔记，在白板的协作入口创建房间，分享二维码或协作链接。',
        '对方可从“加入房间”扫码或粘贴链接；不需要先添加好友。',
      ]),
    ],
    note: '本地笔记不要求登录。账号登录不会自动把本地资料库同步到所有设备；请通过协作、导出或备份完成相应的数据分享。',
    action: GuideAction.createNote,
    actionLabel: '新建一份笔记',
  ),
  GuideTopic.writing: GuideArticle(
    summary: '画笔负责表达，抓手负责移动，选框负责整理。先熟悉这几个工具，就能流畅地在画布中记录和修改。',
    sections: [
      GuideSection('书写、移动与选择', [
        '在工具栏选择画笔，调整颜色和粗细；不同笔形的参数会分别记忆。',
        '用抓手平移画布；选框可选择笔画、文字或图形，再移动或调整。',
        '“手指绘制”用于决定手指是否落墨。使用手写笔时，可按自己的习惯关闭手指绘制，减少误触。',
      ]),
      GuideSection('擦除与撤销', [
        '选择橡皮工具后擦除目标；撤销和重做可帮助修正刚才的操作。',
        '笔尖重压临时擦除与笔身双击切换属于设备相关能力，请结合手写笔设置和设备实际支持使用。',
        '笔身双击发生在笔杆上；它与用笔尖连续点两下屏幕是不同操作。',
      ]),
      GuideSection('缩放与页面', [
        '使用画布右下角的缩放控件调整比例；触控设备也可使用已配置的缩放手势。',
        'Web 支持 Ctrl＋滚轮缩放，Mac 可使用 Command＋滚轮；普通滚轮仍用于滚动画布。',
        '分页笔记通过页面控件切换和管理纸张。重置画布前先确认是否仍需要当前内容。',
      ]),
    ],
    note: '手写笔能力依赖品牌、系统与笔型，不能把某一台设备的效果视为所有设备都支持。压力和防误触可在“手写笔设置”中调整。',
    action: GuideAction.stylus,
    actionLabel: '打开手写笔设置',
  ),
  GuideTopic.pdf: GuideArticle(
    summary: '在讲义、论文或会议资料旁留下自己的理解。PDF 页面与手写批注放在一起，阅读和表达可以交替进行。',
    sections: [
      GuideSection('导入阅读资料', [
        '点击“新建笔记”，再选择“导入 PDF”。等待导入完成后，文件会成为资料库中的一份笔记。',
        '导入较大的文件需要处理页面，请保留足够空间，并等待完成提示。',
      ]),
      GuideSection('圈注与补充说明', [
        '缩放到适合阅读的比例，再用画笔、文字或图形补充说明。',
        '用抓手移动阅读位置，避免把翻阅操作误当成书写。',
        '通过页码与页面控件定位所需纸张，批注随笔记一起保存。',
      ]),
      GuideSection('分享批注结果', [
        '在白板菜单中选择适合的导出方式，或创建协作房间共同阅读与批注。',
        '需要再次编辑时，优先保留可编辑的笔记文件；图片等展示格式不能替代完整笔记备份。',
      ]),
    ],
    note: '导入后进行的是笔记画布上的阅读与批注，不是直接修改原 PDF 文件里的排版或正文。',
    action: GuideAction.createNote,
    actionLabel: '打开新建与导入',
  ),
  GuideTopic.collaboration: GuideArticle(
    summary: '分享一份笔记，一起书写、批注和讨论。光标、成员状态与视角工具帮助大家知道彼此正在关注哪里。',
    sections: [
      GuideSection('创建或加入房间', [
        '先打开笔记，再从白板协作入口创建房间；把房间二维码或链接交给参与者。',
        'App 内可从“加入房间”扫码或粘贴链接。手机系统相机识别二维码后，可打开 Web 加入。',
        '已添加的好友也可以通过“好友与消息”接收定向邀请；加入前按提示确认当前笔记的保存与退出。',
      ]),
      GuideSection('看清每个人的关注点', [
        '成员光标和头像帮助识别参与者；协作状态入口可查看当前房间与成员信息。',
        '聚焦某位创建者，可以让其内容更醒目；聚焦只改变自己的显示效果。',
        '跟随对方视角适合讲解和演示。操作自己的画布或使用退出跟随入口，即可恢复独立浏览。',
      ]),
      GuideSection('安全地结束协作', [
        '切换房间时遵循应用的保存与退出提示，避免遗漏尚未保存的修改。',
        '房间链接包含加入所需信息，只分享给预期参与者；公开演示时避免展示完整链接。',
      ]),
    ],
    note: '实时协作需要稳定网络，也需要各端使用兼容版本。协作房间与本地资料库备份承担不同用途，重要笔记仍应定期备份。',
    action: GuideAction.library,
    actionLabel: '选择一份笔记开始协作',
  ),
  GuideTopic.smart: GuideArticle(
    summary: '手写识别、智能排版和 AI 笔记助手分别帮助转换、整理与理解内容。根据任务选择工具，比一次启用所有能力更有效。',
    sections: [
      GuideSection('手写识别与智能排版', [
        '在白板中选择相应的识别或排版入口，按提示选取需要处理的手写内容或页面。',
        '先核对识别结果，再决定是否采用整理后的内容；重要原稿可先保留副本或导出。',
      ]),
      GuideSection('配置 AI 笔记助手', [
        '在“设置 → AI笔记助手配置”中填写自己使用的服务地址、API Key 和模型。',
        '回到笔记，从 AI 工具入口发起整理或提问；只提交自己愿意交给所选服务处理的内容。',
      ]),
      GuideSection('语音输入', [
        '使用白板语音入口时按需授权麦克风，在录入后检查识别结果。',
        '识别方式与可用能力受平台和当前配置影响；没有授权时仍可正常手写或输入文字。',
      ]),
    ],
    note: '识别与 AI 可能依赖网络、服务配置或额度。生成内容需要自行核对，不作为事实正确或格式完全一致的保证。',
    action: GuideAction.ai,
    actionLabel: '配置 AI 笔记助手',
  ),
  GuideTopic.library: GuideArticle(
    summary: '用笔记本组织主题，用标签建立关联。资料库负责找到内容，画布负责展开想法。',
    sections: [
      GuideSection('整理笔记', [
        '在侧栏新建笔记本，把同一课程、项目或主题的笔记放在一起。',
        '给笔记添加标签，从不同线索找到同一份内容；笔记名称旁的菜单提供重命名和归类操作。',
      ]),
      GuideSection('查找与批量操作', [
        '在“搜索”中输入笔记标题关键词，并根据笔记本和标签缩小范围。',
        '切换网格或列表视图；需要整理多份笔记时，使用多选执行移动、加标签或删除。',
      ]),
      GuideSection('从回收站恢复', [
        '删除的笔记可在回收站中查看并恢复。',
        '永久删除前确认已有所需备份；回收站不能替代独立备份。',
      ]),
    ],
    note: '当前搜索主要用于查找本地笔记标题，不要把它当作所有 PDF 正文与手写内容的全文搜索。',
    action: GuideAction.library,
    actionLabel: '打开全部笔记',
  ),
  GuideTopic.backup: GuideArticle(
    summary: '把重要记录留一份可恢复的备份，再把纸张、笔形和主题调整到适合自己的状态。',
    sections: [
      GuideSection('保存与备份', [
        '编辑中的笔记会自动保存；如果出现保存失败提示，请先处理错误，再退出或切换。',
        '在“设置 → 本地备份”中导出备份文件，并把文件保存在可靠的位置。',
        '恢复前阅读导入提示，确认导入内容和现有资料的处理方式。',
      ]),
      GuideSection('连接自己的网盘', [
        '“网盘备份”支持配置 WebDAV 地址与凭据，再按需要上传或恢复备份。',
        '验证备份确实能够下载和恢复；WebDAV 备份不是自动合并多端资料库。',
      ]),
      GuideSection('设定自己的书写环境', [
        '在主题设置中选择适合环境的配色；文档设置控制新建笔记的默认模板与排列。',
        '工具、手写笔和手势设置各自管理笔形习惯、输入手感与画布操作。',
      ]),
    ],
    note: '本地数据受当前设备或浏览器存储环境影响。清理浏览器站点数据、卸载应用或更换设备前，请先导出并核对备份。',
    action: GuideAction.backup,
    actionLabel: '打开本地备份',
  ),
  GuideTopic.messages: GuideArticle(
    summary: '通过好友码建立联系，在消息里讨论内容或发送协作邀请。提醒方式由自己决定，记录过程保持安静。',
    sections: [
      GuideSection('添加好友与交流', [
        '登录后打开“好友与消息”，复制自己的好友码，或输入对方提供的完整好友码。',
        '通过好友申请后可发送文字消息，也可以向好友发送协作邀请。',
      ]),
      GuideSection('设置提醒方式', [
        '点击“好友与消息”右上角铃铛，选择应用内提醒、消息预览或免打扰。',
        '需要切到其他应用或浏览器标签页时仍有提醒，可主动开启“系统提醒”并完成系统授权。',
        '正在前台查看的会话不会重复提醒；免打扰不会清空未读消息。',
      ]),
      GuideSection('查看并加入邀请', [
        '点击通知进入对应聊天，再查看邀请是否仍然有效。',
        '确认加入之前，按应用提示保存或退出当前房间；收到邀请本身不会自动切换画布。',
      ]),
    ],
    note: '私聊历史保存在云端。系统提醒要求应用或浏览器仍在运行；进程被系统暂停或结束后，不保证继续接收新消息。',
    action: GuideAction.social,
    actionLabel: '打开好友与消息',
  ),
};
