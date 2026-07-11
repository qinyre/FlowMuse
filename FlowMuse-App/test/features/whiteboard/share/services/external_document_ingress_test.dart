import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/share/models/external_document_request.dart';
import 'package:flow_muse/features/whiteboard/share/services/external_document_ingress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('入站队列限制三项且按 FIFO 取出', () async {
    final ingress = ExternalDocumentIngress();
    for (var index = 0; index < 3; index++) {
      expect(
        ingress.enqueue(
          ExternalDocumentRequest(
            fileName: '$index.markdraw',
            bytes: Uint8List(1),
          ),
        ),
        isTrue,
      );
    }
    expect(
      ingress.enqueue(
        ExternalDocumentRequest(
          fileName: 'overflow.markdraw',
          bytes: Uint8List(1),
        ),
      ),
      isFalse,
    );
    expect((await ingress.takeNext())!.fileName, '0.markdraw');
  });

  test('拒绝超过二十 MiB的外部文件', () {
    final ingress = ExternalDocumentIngress();
    expect(
      ingress.enqueue(
        ExternalDocumentRequest(
          fileName: 'large.markdraw',
          bytes: Uint8List(20 * 1024 * 1024 + 1),
        ),
      ),
      isFalse,
    );
  });
}
