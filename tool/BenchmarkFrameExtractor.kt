package com.local.shorts_studio

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * Extracts six actual scenes from a video chosen using Android's document picker.
 * No video or frame is saved; only bounded JPEG bytes are returned for WEB_DETECTION.
 * First/last frames are uncropped; middle frames crop likely top/bottom overlay regions.
 */
object BenchmarkFrameExtractor {
    fun extract(context:Context, source:Uri): List<Map<String,Any>> {
        require(source.scheme=="content" && source.authority!=null){"Android 파일 선택기로 영상을 선택해 주세요."}
        val media=MediaMetadataRetriever()
        try {
            media.setDataSource(context,source)
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
                    val trim=index in 1..4 && frame.height>100
                    val cutTop=if(trim) (frame.height*.12).toInt() else 0
                    val cutHeight=frame.height-2*cutTop
                    val clean=if(trim) Bitmap.createBitmap(frame,0,cutTop,frame.width,cutHeight) else frame
                    try {
                        val buffer=ByteArrayOutputStream()
                        check(clean.compress(Bitmap.CompressFormat.JPEG,82,buffer)){"영상 장면을 JPEG로 변환하지 못했어요."}
                        val bytes=buffer.toByteArray()
                        if(bytes.size in 100..1000000) {
                            result.add(mapOf("timeMs" to timeMs,
                                "crop" to trim,
                                "content" to Base64.encodeToString(bytes,Base64.NO_WRAP)))
                        }
                    } finally {
                        if(clean !== frame)clean.recycle()
                    }
                } finally {frame.recycle()}
            }
            check(result.size>=3){"검색 가능한 주요 장면을 세 장 이상 추출하지 못했어요."}
            return result
        } finally {media.release()}
    }
}
