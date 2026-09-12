/// 通用文本与时长格式化。
library;

/// 去掉文件名中的扩展名；无扩展名时原样返回。
String stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// 格式化为 `m:ss`，秒数不足两位补零。
String formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
