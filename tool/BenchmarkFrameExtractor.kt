package com.local.shorts_studio

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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

    /**
     * Candidate video is sampled at 16 moments. Return compact visual hashes,
     * not full frames, to avoid unnecessarily large platform-channel payloads.
     */
    fun fingerprints(file:File):List<Map<String,Any>> {
        require(file.isFile&&file.length() in 10240L..(512L*1024*1024)) {
            "후보 영상 파일 크기 또는 접근 오류"
        }
        val media=MediaMetadataRetriever()
        try {
            media.setDataSource(file.absolutePath)
            val duration=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?:error("후보 영상 길이 확인 실패")
            require(duration in 500L..600000L)
            val result=mutableListOf<Map<String,Any>>()
            for(i in 0 until 16) {
                val ms=(duration*(i+0.5)/16).toLong().coerceIn(0,duration-1)
                val frame=media.getScaledFrameAtTime(ms*1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,480,480)?:continue
                try {
                    val clean=centerCrop(frame)
                    try {
                        val info=perceptualHash(clean)
                        result.add(mapOf("hash" to info.first, "contrast" to info.second,
                            "timeMs" to ms))
                    } finally {clean.recycle()}
                } finally {frame.recycle()}
            }
            require(result.size>=4){"후보에서 비교할 장면이 너무 적어요."}
            return result
        } finally {media.release()}
    }

    /** Verifies a downloaded YouTube thumbnail without storing its bytes. */
    fun fingerprintJpeg(bytes:ByteArray):Map<String,Any>{
        require(bytes.size in 128..(1024*1024)){"썸네일 크기가 올바르지 않아요."}
        val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size)
            ?:error("썸네일 이미지 디코딩 실패")
        try{
            require(bitmap.width>=72 && bitmap.height>=72){"썸네일 해상도 부족"}
            val cropped=centerCrop(bitmap)
            try{
                val (hash,contrast)=perceptualHash(cropped)
                return mapOf("hash" to hash,"contrast" to contrast)
            }finally{cropped.recycle()}
        }finally{bitmap.recycle()}
    }

    private fun centerCrop(frame:Bitmap):Bitmap {
        val portrait=frame.height>frame.width
        // Many benchmark Shorts retain creator-added subtitles well inside
        // the first/last 18%, so search only the *central action band*.
        // Identical crop coordinates are used for reference and candidates.
        val top=(frame.height*(if(portrait)0.30 else 0.16)).toInt()
        val bottom=(frame.height*(if(portrait)0.35 else 0.18)).toInt()
        val left=(frame.width*(if(portrait)0.07 else 0.05)).toInt()
        return Bitmap.createBitmap(frame,left,top,
            frame.width-2*left,frame.height-top-bottom)
    }

    /** 64-bit difference hash + grayscale standard deviation for flat frames. */
    private fun perceptualHash(frame:Bitmap):Pair<String,Double> {
        val thumbnail=Bitmap.createScaledBitmap(frame,9,8,true)
        try {
            val pixels=IntArray(9*8)
            thumbnail.getPixels(pixels,0,9,0,0,9,8)
            fun gray(p:Int):Int {
                return (((p shr 16)and 255)*299+((p shr 8)and 255)*587+
                    (p and 255)*114)/1000
            }
            val values=pixels.map(::gray)
            var hash=0L
            for(row in 0 until 8)for(column in 0 until 8){
                hash=hash shl 1
                if(values[row*9+column]>values[row*9+column+1])hash=hash or 1L
            }
            val mean=values.average()
            val variation=values.sumOf {(it-mean)*(it-mean)}/values.size
            return java.lang.Long.toHexString(hash).padStart(16,'0') to kotlin.math.sqrt(variation)
        }finally{thumbnail.recycle()}
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
                val clean=centerCrop(frame)
                try {
                val buffer=ByteArrayOutputStream()
                check(clean.compress(Bitmap.CompressFormat.JPEG,82,buffer)){"영상 장면을 JPEG로 변환하지 못했어요."}
                val bytes=buffer.toByteArray()
                if(bytes.size in 100..1000000) {
                    result.add(mapOf("timeMs" to timeMs,
                        "crop" to true,
                        "content" to Base64.encodeToString(bytes,Base64.NO_WRAP),
                        "hash" to perceptualHash(clean).first,
                        "contrast" to perceptualHash(clean).second))
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
