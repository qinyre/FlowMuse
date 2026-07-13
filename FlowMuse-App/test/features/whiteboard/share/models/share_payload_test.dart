import 'package:flow_muse/features/whiteboard/share/models/share_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('文本分享拒绝空内容', () {
    expect(
      () => ShareTextPayload(title: '协作邀请', text: '   '),
      throwsArgumentError,
    );
  });

  test('文件分享要求绝对路径和文件名', () {
    expect(
      () => ShareFilePayload(
        title: '白板',
        contentType: ShareContentType.markdraw,
        filePath: 'drawing.markdraw',
        fileName: 'drawing.markdraw',
        mimeType: 'application/x-markdraw',
      ),
      throwsArgumentError,
    );
    expect(
      () => ShareFilePayload(
        title: '白板',
        contentType: ShareContentType.markdraw,
        filePath: '/tmp/drawing.markdraw',
        fileName: ' ',
        mimeType: 'application/x-markdraw',
      ),
      throwsArgumentError,
    );
  });

  test('文件分享需要文件路径或字节内容', () {
    expect(
      () => ShareFilePayload(
        title: '白板',
        contentType: ShareContentType.png,
        fileName: 'drawing.png',
        mimeType: 'image/png',
      ),
      throwsArgumentError,
    );
  });

  test('邀请链接只能构造成文本分享', () {
    final payload = ShareTextPayload(
      title: '协作邀请',
      text: 'https://flowmuse.local/whiteboard/collaboration',
      contentType: ShareContentType.hyperlink,
    );

    expect(payload.contentType, ShareContentType.hyperlink);
    expect(payload, isA<ShareTextPayload>());
  });
}
