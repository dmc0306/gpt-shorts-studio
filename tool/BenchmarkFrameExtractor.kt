package com.local.shorts_studio

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Frame extraction from user-picked documents or the bounded internal
 * temporary YouTube stream. Always decodes media locally.
 */
object BenchmarkFrameExtractor {
    fun extract(context:Context, source:Uri): List<Map<String,Any>> {
        require(source.scheme=="content" && source.authority!=null) {
            "Android 파일 선택기로 영상을 선택해 주세요."
        }
        val media=MediaMetadataRetriever()
        try {
            media.setDataSource(context,source)
            return extractInternal(media)
        } finally { media.release() }
    }

    fun extractFile(file:File): List<Map<String,Any>> {
        require(file.isFile && file.length() in 10240L..(80L*1024*1024)) {
            "임시 스트림 영상이 없거나 크기가 잘못됐어요."
        }
        val media=MediaMetadataRetriever()
        try {
            media.setDataSource(file.absolutePath)
            return extractInternal(media)
        } finally { media.release() }
    }

    private fun extractInternal(media:MediaMetadataRetriever): List<Map<String,Any>> {
        val duration=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            ?:error("영상 재생시간을 확인하지 못했어요.")
        require(duration in 500L..600000L){"0.5초~10분 영상만 장면 검색에 사용할 수 있어요."}
        val fractions=listOf(0.12,0.28,0.45,0.62,0.79,0.91)
        val result=mutableListOf<Map<String,Any>>()
        fractions.forEachIndexed { index, fraction ->
            val timeMs=(duration*fraction).toLong().coerceIn(0L,duration-1)
            val frame=media.getScaledFrameAtTime(timeMs*1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,720,720) ?: return@forEachIndexed
            try {
                // All frames: trim persistent subtitle/title overlays before
                // sending images to Cloud Vision; previous code left the
                // first and last samples completely untrimmed.
                val portrait=frame.height>frame.width
                val cutTop=(frame.height*(if(portrait)0.18 else 0.10)).toInt()
                val cutLeft=(frame.width*(if(portrait)0.06 else 0.04)).toInt()
                val cutHeight=frame.height-2*cutTop
                val cutWidth=frame.width-2*cutLeft
                val clean=Bitmap.createBitmap(frame,cutLeft,cutTop,cutWidth,cutHeight)
                try {
                val buffer=ByteArrayOutputStream()
                check(clean.compress(Bitmap.CompressFormat.JPEG,82,buffer)){"영상 장면을 JPEG로 변환하지 못했어요."}
                val bytes=buffer.toByteArray()
                if(bytes.size in 100..1000000) {
                    result.add(mapOf("timeMs" to timeMs,
                        "crop" to true,
                        "content" to Base64.encodeToString(bytes,Base64.NO_WRAP)))
                }
                } finally {
                if(clean !== frame)clean.recycle()
                }
            } finally {frame.recycle()}
        }
        check(result.size>=3){"검색 가능한 주요 장면을 세 장 이상 추출하지 못했어요."}
        return result
    }
}
