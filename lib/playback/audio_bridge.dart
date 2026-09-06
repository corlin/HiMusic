import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../sources/music_source.dart';

/// One inclusive HTTP byte range; internal end is exclusive.
class ByteRange {
  const ByteRange(this.start, this.end);
  final int start;
  final int end;
  static ByteRange parse(String? header, int size) {
    if (header == null) return ByteRange(0, size);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
    if (match == null || size == 0) {
      throw const FormatException('Invalid range');
    }
    final left = match[1]!;
    final right = match[2]!;
    if (left.isEmpty) {
      final suffix = int.tryParse(right);
      if (suffix == null || suffix <= 0) {
        throw const FormatException('Invalid suffix');
      }
      return ByteRange(max(0, size - suffix), size);
    }
    final start = int.tryParse(left);
    final last = right.isEmpty ? size - 1 : int.tryParse(right);
    if (start == null || last == null || start >= size || last < start) {
      throw const FormatException('Unsatisfiable range');
    }
    return ByteRange(start, min(last + 1, size));
  }
}

class AudioBridge {
  AudioBridge._(this._server, this._source);
  final HttpServer _server;
  final MusicSource _source;
  final Map<String, MusicEntry> _files = {};
  final _random = Random.secure();
  bool _closed = false;
  int _active = 0;
  static const chunkSize = 128 * 1024;

  static Future<AudioBridge> start(MusicSource source) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bridge = AudioBridge._(server, source);
    server.listen((request) => unawaited(bridge._serve(request)));
    return bridge;
  }

  Uri register(MusicEntry entry) {
    if (_closed) throw StateError('Bridge is closed');
    final token = List.generate(
      24,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = '/$token.${entry.extension}';
    _files[path] = entry;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      path: path,
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    var counted = false;
    try {
      final entry = _files[request.uri.path];
      if (_closed || entry == null) {
        response.statusCode = 404;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = 405;
        response.headers.set('Allow', 'GET, HEAD');
        return;
      }
      if (_active >= 4) {
        response.statusCode = 503;
        return;
      }
      _active++;
      counted = true;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('Content-Type', entry.mimeType);
      final header = request.method == 'HEAD'
          ? null
          : request.headers.value('range');
      late ByteRange range;
      try {
        range = ByteRange.parse(header, entry.size);
      } on FormatException {
        response.statusCode = 416;
        response.headers.set('Content-Range', 'bytes */${entry.size}');
        return;
      }
      response.statusCode = header == null ? 200 : 206;
      response.contentLength = range.end - range.start;
      if (header != null) {
        response.headers.set(
          'Content-Range',
          'bytes ${range.start}-${range.end - 1}/${entry.size}',
        );
      }
      if (request.method == 'HEAD') return;
      var disconnected = false;
      unawaited(
        response.done.then(
          (_) {
            disconnected = true;
          },
          onError: (Object _) {
            disconnected = true;
          },
        ),
      );
      for (
        var offset = range.start;
        offset < range.end && !_closed && !disconnected;
      ) {
        final length = min(chunkSize, range.end - offset);
        final data = await _source
            .read(entry.path, offset, length)
            .timeout(const Duration(seconds: 25));
        if (_closed || disconnected) break;
        if (data.isEmpty || data.length > length) {
          throw const FileSystemException('Unexpected read size');
        }
        response.add(data);
        await response.flush();
        offset += data.length;
      }
    } catch (_) {
      // Do not leak credentials or paths into HTTP error bodies or logs.
      try {
        final socket = await response.detachSocket(writeHeaders: false);
        socket.destroy();
      } catch (_) {}
    } finally {
      if (counted) _active--;
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _closed = true;
    _files.clear();
    await _server.close(force: true);
  }
}
