import 'dart:typed_data';

import 'package:metadata_audio/metadata_audio.dart' as audio;

import '../util/format.dart';

class TrackMetadata {
  const TrackMetadata({
    this.title,
    this.performers = const [],
    this.album,
    this.albumArtist,
    this.composers = const [],
    this.arrangers = const [],
    this.lyricists = const [],
    this.genres = const [],
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.sampleRate,
    this.bitRate,
    this.bitDepth,
    this.channels,
    this.artwork,
    this.artworkMimeType,
  });

  factory TrackMetadata.fromTags(Map<String, List<String>> tags) {
    final normalized = <String, List<String>>{};
    for (final entry in tags.entries) {
      final values = entry.value
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.isNotEmpty) normalized[entry.key.toUpperCase()] = values;
    }

    List<String> values(List<String> names) {
      for (final name in names) {
        final found = normalized[name];
        if (found != null && found.isNotEmpty) return found;
      }
      return const [];
    }

    String? first(List<String> names) {
      final found = values(names);
      return found.isEmpty ? null : found.first;
    }

    return TrackMetadata(
      title: first(const ['TITLE', 'TIT2']),
      performers: values(const ['ARTIST', 'TPE1', 'PERFORMER']),
      album: first(const ['ALBUM', 'TALB']),
      albumArtist: first(const ['ALBUMARTIST', 'ALBUM ARTIST', 'TPE2']),
      composers: values(const ['COMPOSER', 'TCOM']),
      arrangers: values(const ['ARRANGER', 'ARRANGEMENT']),
      lyricists: values(const ['LYRICIST', 'TEXT', 'WRITER']),
      genres: values(const ['GENRE', 'TCON']),
    );
  }

  factory TrackMetadata.fromAudioMetadata(audio.AudioMetadata metadata) {
    final tags = metadata.common;
    final rawTags = <String, List<String>>{};
    for (final group in metadata.native.values) {
      for (final tag in group) {
        final id = tag.id.split(':').last.toUpperCase();
        final rawValues = tag.value is Iterable
            ? (tag.value as Iterable).map((value) => '$value')
            : ['${tag.value}'];
        rawTags.putIfAbsent(id, () => []).addAll(rawValues);
      }
    }
    final raw = TrackMetadata.fromTags(rawTags);
    final picture = tags.picture?.firstOrNull;
    final performers =
        tags.artists?.where(_notBlank).toList() ??
        (tags.artist == null ? const <String>[] : [tags.artist!]);
    return TrackMetadata(
      title: _clean(tags.title),
      performers: performers.where(_notBlank).toList(),
      album: _clean(tags.album),
      albumArtist: _clean(tags.albumartist),
      composers: tags.composer?.where(_notBlank).toList() ?? raw.composers,
      arrangers: tags.arranger?.where(_notBlank).toList() ?? raw.arrangers,
      lyricists:
          (tags.lyricist ?? tags.writer)?.where(_notBlank).toList() ??
          raw.lyricists,
      genres: tags.genre?.where(_notBlank).toList() ?? const [],
      year: tags.year,
      trackNumber: tags.track.no,
      discNumber: tags.disk.no,
      duration: metadata.format.duration == null
          ? null
          : Duration(milliseconds: (metadata.format.duration! * 1000).round()),
      sampleRate: metadata.format.sampleRate,
      bitRate: metadata.format.bitrate?.round(),
      bitDepth: metadata.format.bitsPerSample,
      channels: metadata.format.numberOfChannels,
      artwork: picture == null ? null : Uint8List.fromList(picture.data),
      artworkMimeType: picture?.format,
    );
  }

  final String? title;
  final List<String> performers;
  final String? album;
  final String? albumArtist;
  final List<String> composers;
  final List<String> arrangers;
  final List<String> lyricists;
  final List<String> genres;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final Duration? duration;
  final int? sampleRate;
  final int? bitRate;
  final int? bitDepth;
  final int? channels;
  final Uint8List? artwork;
  final String? artworkMimeType;

  String displayTitle(String fileName) {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    return stripExtension(fileName);
  }

  String? get artistLine => performers.isEmpty ? null : performers.join('、');

  Map<String, String> get credits => {
    if (performers.isNotEmpty) '演唱': performers.join('、'),
    if (composers.isNotEmpty) '作曲': composers.join('、'),
    if (arrangers.isNotEmpty) '编曲': arrangers.join('、'),
    if (lyricists.isNotEmpty) '作词': lyricists.join('、'),
  };
}

bool _notBlank(String value) => value.trim().isNotEmpty;

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}
