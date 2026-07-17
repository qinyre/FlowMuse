import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/settings/services/webdav_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('浏览备份通过 Dart HTTP 发送 PROPFIND 并解析已有文件', () async {
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com',
      username: 'user',
      password: 'password',
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.url.toString(), 'https://dav.example.com/FlowMuse/');
        expect(request.headers['Depth'], '1');
        expect(request.headers['Authorization'], startsWith('Basic '));
        expect(request.headers['Accept-Encoding'], 'identity');
        expect(request.headers['Connection'], 'close');
        return http.Response('''
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/FlowMuse/FlowMuse_2026-07-16_12-00-00.json</d:href>
    <d:propstat><d:prop>
      <d:displayname>FlowMuse_2026-07-16_12-00-00.json</d:displayname>
      <d:getcontentlength>123</d:getcontentlength>
    </d:prop></d:propstat>
  </d:response>
</d:multistatus>
''', 207);
      }),
    );

    final entries = await client.listDirectory('/FlowMuse/');
    expect(entries.single.name, 'FlowMuse_2026-07-16_12-00-00.json');
    expect(entries.single.sizeBytes, 123);
  });

  test('备份通过 Dart HTTP 发送 MKCOL 和 PUT', () async {
    final methods = <String>[];
    final client = WebDavClient(
      baseUrl: 'https://dav.example.com',
      username: 'user',
      password: 'password',
      httpClient: MockClient((request) async {
        methods.add(request.method);
        return http.Response('', request.method == 'MKCOL' ? 405 : 201);
      }),
    );

    await client.ensureDirectory('/FlowMuse/');
    await client.putFile(
      '/FlowMuse/FlowMuse_test.json',
      Uint8List.fromList('{}'.codeUnits),
    );

    expect(methods, ['MKCOL', 'PUT']);
  });
}
