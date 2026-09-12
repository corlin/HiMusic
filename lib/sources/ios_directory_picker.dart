import 'package:flutter/services.dart';

/// iOS 目录选择器封装。
///
/// 通过原生 UIDocumentPickerViewController 选择文件夹，
/// 并用安全范围书签持久化授权，冷启动可自动恢复。
class IosDirectoryPicker {
  static const _channel = MethodChannel('app.himusic/directory_picker');

  /// 弹出系统文件夹选择器，返回选中的目录路径。
  /// 用户取消时返回 null。
  Future<String?> pickDirectory() =>
      _channel.invokeMethod<String>('pickDirectory');

  /// 从上次保存的安全范围书签恢复目录访问，返回目录路径。
  /// 没有保存过或恢复失败时返回 null。
  Future<String?> restoreDirectory() =>
      _channel.invokeMethod<String>('restoreDirectory');
}
