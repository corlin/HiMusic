/// 播放队列索引计算（纯函数，便于单测）。
library;

/// 从队列移除 [removedIndex] 条目后，当前播放索引的新位置。
///
/// - 未在播放（[currentIndex] 为 null）→ null；
/// - 移除项在当前播放项之后 → 不变；
/// - 移除当前项 → 原位置变为下一首（索引不变）；
/// - 移除当前项之前的项 → 索引减一。
int? mapIndexAfterRemoval(int removedIndex, int? currentIndex) {
  if (currentIndex == null) return null;
  if (removedIndex < currentIndex) return currentIndex - 1;
  return currentIndex;
}
