import 'dart:io';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:path/path.dart' as p;

import 'music_source.dart';

class SmbConnectionRequest {
  const SmbConnectionRequest({
    required this.host,
    required this.share,
    required this.directory,
    required this.user,
    required this.password,
  });
  final String host;
  final String share;
  final String directory;
  final String user;
  final String password;
}

class SmbSource implements MusicSource {
  SmbSource._(this._pool, this.label);
  final Smb2Pool _pool;
  @override
  final String label;
  @override
  String get cacheNamespace => label;
  static Future<SmbSource> connect({
    required String host,
    required String share,
    required String user,
    required String password,
  }) async {
    if (host.trim().isEmpty ||
        share.trim().isEmpty ||
        host.contains('://') ||
        share.contains('/') ||
        share.contains('\\')) {
      throw const FormatException('请输入主机地址与单独的共享名称');
    }
    final pool = await Smb2Pool.connect(
      host: host.trim(),
      share: share.trim(),
      user: user,
      password: password,
      workers: 2,
      timeoutSeconds: 10,
    );
    return SmbSource._(pool, '${host.trim()} / ${share.trim()}');
  }

  @override
  Future<List<MusicEntry>> list(String directory) async {
    final path = safePath(directory);
    final entries = await _pool.listDirectory(path);
    return sortEntries(
      entries
          .where((e) => e.isFile || e.isDirectory)
          .map(
            (e) => MusicEntry(
              path: safePath(
                [path, e.name].where((s) => s.isNotEmpty).join('/'),
              ),
              name: e.name,
              isDirectory: e.isDirectory,
              size: e.size,
              modified: e.stat.modified,
            ),
          )
          .where((e) => e.isDirectory || e.isAudio),
    );
  }

  @override
  Future<Uint8List> read(String path, int offset, int length) =>
      _pool.readFileRange(safePath(path), offset: offset, length: length);
  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) async {
    final parent = p.posix.dirname(entry.path) == '.'
        ? ''
        : p.posix.dirname(entry.path);
    final wanted = '${p.basenameWithoutExtension(entry.name)}$extension';
    final entries = await _pool.listDirectory(parent);
    for (final candidate in entries) {
      if (!candidate.isFile ||
          candidate.name.toLowerCase() != wanted.toLowerCase()) {
        continue;
      }
      if (candidate.size > maxBytes) {
        throw const FileSystemException('歌词文件过大');
      }
      final path = safePath(
        [parent, candidate.name].where((e) => e.isNotEmpty).join('/'),
      );
      return _pool.readFileRange(path, offset: 0, length: candidate.size);
    }
    return null;
  }
  @override
  Future<void> close() => _pool.disconnect();

  @override
  Future<void> writeSidecar(
    MusicEntry entry,
    String extension,
    Uint8List bytes,
  ) =>
      throw UnsupportedError('SMB 共享暂不支持写入歌词文件');
}

String sourceError(Object error) {
  if (error is FormatException) return error.message;
  if (error is Smb2Exception) {
    return switch (error.type) {
      Smb2ErrorType.auth => '认证失败，请检查共享账号和密码。',
      Smb2ErrorType.accessDenied => '访问被拒绝，请检查账号与共享权限。',
      Smb2ErrorType.fileNotFound ||
      Smb2ErrorType.notADirectory => '共享或目录不存在，请检查名称。',
      Smb2ErrorType.timeout ||
      Smb2ErrorType.connection => '连接中断或超时，请检查网络及硬盘状态后重试。',
      _ => '共享读取失败，请检查文件与路由器状态。',
    };
  }
  return '操作未完成，请检查文件访问权限、网络或音频格式后重试。';
}
