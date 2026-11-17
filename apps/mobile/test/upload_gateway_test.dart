import 'dart:async';
import 'dart:convert';

import 'package:dartvex/dartvex.dart' as cx;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opengym/data/convex_client.dart';

class _Caller implements cx.ConvexFunctionCaller {
  final List<String> names = <String>[];
  Map<String, dynamic>? registerArgs;

  @override
  Future<dynamic> mutate(String name,
      [Map<String, dynamic> args = const <String, dynamic>{},
      cx.OptimisticUpdate? optimisticUpdate]) async {
    names.add(name);
    if (name == 'commands/files:generateUploadUrl') {
      return 'https://upload.test/u1';
    }
    if (name == 'commands/files:register') {
      registerArgs = args;
      return <String, dynamic>{
        'fileId': args['fileId'],
        'name': args['name'],
        'mime': args['mime'],
        'size': args['size'],
        'kind': 'text',
        'createdAt': 5.0,
      };
    }
    return null;
  }

  @override
  Future<dynamic> query(String name,
      [Map<String, dynamic> args = const <String, dynamic>{}]) async {
    return <String, dynamic>{
      'fileId': 'f1',
      'name': 'a.txt',
      'mime': 'text/plain',
      'size': 3.0,
      'kind': 'text',
      'createdAt': 1.0,
      'url': 'https://files.test/f1',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('upload: get a URL, POST the bytes with the content type, then register', () async {
    final _Caller caller = _Caller();
    http.Request? seen;
    final DartvexConvexClient c = DartvexConvexClient(
      caller: caller,
      token: 't',
      connectionStates: const Stream<ConvexLink>.empty(),
      httpClient: MockClient((http.Request r) async {
        seen = r;
        return http.Response(jsonEncode(<String, String>{'storageId': 'st1'}), 200);
      }),
    );
    final meta = await c.uploadFile(
        fileId: 'f1', name: 'a.txt', mime: 'text/plain', bytes: <int>[1, 2, 3]);
    expect(caller.names, <String>['commands/files:generateUploadUrl', 'commands/files:register']);
    expect(seen!.url.toString(), 'https://upload.test/u1');
    expect(seen!.method, 'POST');
    expect(seen!.headers['content-type'], startsWith('text/plain'));
    expect(seen!.bodyBytes, <int>[1, 2, 3]);
    expect(caller.registerArgs!['storageId'], 'st1');
    expect(caller.registerArgs!['size'], 3);
    expect(meta.id, 'f1');
    final link = await c.fileLink('f1');
    expect(link!.url, 'https://files.test/f1');
    expect(link.meta.name, 'a.txt');
  });

  test('a refused upload is a plain error and nothing is registered', () async {
    final _Caller caller = _Caller();
    final DartvexConvexClient c = DartvexConvexClient(
      caller: caller,
      token: 't',
      connectionStates: const Stream<ConvexLink>.empty(),
      httpClient: MockClient((http.Request r) async => http.Response('no', 500)),
    );
    await expectLater(
        c.uploadFile(fileId: 'f', name: 'a', mime: 'text/plain', bytes: <int>[1]),
        throwsA(isA<ConvexCallException>()));
    expect(caller.names, <String>['commands/files:generateUploadUrl']);
  });
}
