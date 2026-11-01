import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Downloads a video-only public stream solely to inspect frames.
class BenchmarkStreamError implements Exception {
  const BenchmarkStreamError(this.message);
  final String message;
  @override String toString()=>message;
}

class BenchmarkStreamResolver {
  BenchmarkStreamResolver({YoutubeExplode? client}):_youtube=client??YoutubeExplode();
  final YoutubeExplode _youtube;
  static const maxBytes=80*1024*1024;

  static VideoOnlyStreamInfo choose(List<VideoOnlyStreamInfo> streams) {
    final playable=streams.where((s)=>
      s.container==StreamContainer.mp4 &&
      s.videoCodec.toLowerCase().startsWith('avc1') &&
      (s.size.totalBytes<=0||s.size.totalBytes<=maxBytes) &&
      s.videoResolution.height>=240
    ).toList();
    if(playable.isEmpty)throw const BenchmarkStreamError(
      '디코딩 가능한 MP4(H.264) 스트림을 찾지 못했어요. 기존 영상 파일 선택을 사용해 주세요.');
    playable.sort((a,b) {
      // Long edge <= 1280 is preferred; additional resolution brings little
      // benefit to 720px JPEG frames but increases traffic and latency.
      int rank(VideoOnlyStreamInfo s) {
        final longEdge=s.videoResolution.height>s.videoResolution.width
          ?s.videoResolution.height:s.videoResolution.width;
        return longEdge<=1280?100000+longEdge:100000-(longEdge-1280);
      }
      return rank(b).compareTo(rank(a));
    });
    return playable.first;
  }

  Future<void> download(String videoId,String output,
      void Function(String) status) async {
    if(!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)){
      throw const BenchmarkStreamError('잘못된 YouTube 영상 ID예요.');
    }
    if(!output.endsWith('/$videoId.mp4')){
      throw const BenchmarkStreamError('임시 영상 저장 경로가 올바르지 않아요.');
    }
    RandomAccessFile? handle;
    final file=File(output),partial=File('$output.part');
    try {
      status('영상 스트림 형식 확인 중');
      final manifest=await _youtube.videos.streams.getManifest(videoId)
        .timeout(const Duration(seconds:35));
      final selected=choose(manifest.videoOnly);
      final resolution=selected.videoResolution;
      status('영상 스트림 수신 · ${resolution.width}×${resolution.height}');
      await partial.parent.create(recursive:true);
      handle=await partial.open(mode:FileMode.write);
      var bytes=0;
      await for(final chunk in _youtube.videos.streams.get(selected)
          .timeout(const Duration(seconds:45))) {
        bytes+=chunk.length;
        if(bytes>maxBytes)throw const BenchmarkStreamError('프레임 탐색용 영상 80MB 제한을 넘었어요.');
        await handle.writeFrom(chunk);
      }
      await handle.flush();
      await handle.close();handle=null;
      if(bytes<10240)throw const BenchmarkStreamError('영상 스트림 데이터가 충분하지 않아요.');
      if(await file.exists())await file.delete();
      await partial.rename(output);
      status('영상 스트림 확보 완료 · ${(bytes/1048576).toStringAsFixed(1)}MB');
    } on BenchmarkStreamError {
      rethrow;
    } catch (_) {
      throw const BenchmarkStreamError(
        'YouTube 영상 스트림을 받지 못했어요. 일부 영상의 재생 검증 또는 접속 제한 때문일 수 있어요. 직접 파일 선택으로 재시도해 주세요.');
    } finally {
      if(handle!=null)await handle.close();
      if(await partial.exists())await partial.delete();
      _youtube.close();
    }
  }
}
