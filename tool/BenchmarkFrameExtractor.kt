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
    fun fingerprints(file:File,bounds:List<Map<String,Double>> = emptyList()):List<Map<String,Any>> {
        require(file.isFile&&file.length() in 10240L..(512L*1024*1024)) {
            "후보 영상 파일 크기 또는 접근 오류"
        }
        val media=MediaMetadataRetriever()
        try {
            media.setDataSource(file.absolutePath)
            val duration=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?:error("후보 영상 길이 확인 실패")
            require(duration in 500L..600000L)
            val rawWidth=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()?:0
            val rawHeight=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()?:0
            val rotation=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()?:0
            val videoWidth=if(rotation%180!=0)rawHeight else rawWidth
            val videoHeight=if(rotation%180!=0)rawWidth else rawHeight
            require(videoWidth>0 && videoHeight>0){"후보 영상의 가로·세로 해상도 확인 실패"}
            val result=mutableListOf<Map<String,Any>>()
            for(i in 0 until 16) {
                val ms=(duration*(i+0.5)/16).toLong().coerceIn(0,duration-1)
                val frame=media.getScaledFrameAtTime(ms*1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,480,480)?:continue
                try {
                    val windows=if(bounds.isEmpty())listOf(
                      mapOf("x" to 0.07,"y" to 0.30,"w" to 0.86,"h" to 0.35))
                      else bounds.take(8)
                    for((cropIndex,window) in windows.withIndex()){
                      val x=((window["x"]?:0.07)*frame.width).toInt().coerceIn(0,frame.width-2)
                      val y=((window["y"]?:0.30)*frame.height).toInt().coerceIn(0,frame.height-2)
                      val w=((window["w"]?:0.86)*frame.width).toInt().coerceIn(2,frame.width-x)
                      val h=((window["h"]?:0.35)*frame.height).toInt().coerceIn(2,frame.height-y)
                      val clean=Bitmap.createBitmap(frame,x,y,w,h)
                      try{
                        val info=perceptualHash(clean)
                        result.add(mapOf("hash" to info.first,"contrast" to info.second,
                            "timeMs" to ms,"durationMs" to duration,
                            "videoWidth" to videoWidth,"videoHeight" to videoHeight,
                            "cropIndex" to cropIndex))
                      }finally{clean.recycle()}
                    }
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
            ?:error("영상 길이 확인 실패")
        require(duration in 500L..600000L){"0.5초~10분 영상만 분석할 수 있어요."}
        val rawWidth=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()?:0
        val rawHeight=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()?:0
        val rotation=media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()?:0
        val videoWidth=if(rotation%180!=0)rawHeight else rawWidth
        val videoHeight=if(rotation%180!=0)rawWidth else rawHeight
        val scenes=mutableListOf<Map<String,Any>>()
        val recognizers=BenchmarkOcrCrop.newRecognizers()
        try{
            // Collect six independently sampled OCR-clean scenes (bounded local cost).
            // Alternate the timeline instead of re-searching identical frames.
            val positions=listOf(0,2,4,6,8,10,1,3,5,7,9,11)
            for(index in positions){
                if(scenes.size>=6)break
                val ms=(duration*(index+.5)/12).toLong().coerceIn(0,duration-1)
                val frame=media.getScaledFrameAtTime(ms*1000,
                    MediaMetadataRetriever.OPTION_CLOSEST,720,960)?:continue
                try{
                    val region=BenchmarkOcrCrop.select(frame,recognizers)?:continue
                    val clean=Bitmap.createBitmap(frame,region.x,region.y,region.w,region.h)
                    try{
                        val croppedBuffer=ByteArrayOutputStream()
                        check(clean.compress(Bitmap.CompressFormat.JPEG,87,croppedBuffer))
                        val cropped=croppedBuffer.toByteArray()
                        if(cropped.size !in 100..1000000)continue
                        val hash=perceptualHash(clean)
                        scenes.add(mapOf("timeMs" to ms,"durationMs" to duration,
                            "videoWidth" to videoWidth,"videoHeight" to videoHeight,
                            "ocrExcluded" to true,"ocrRechecked" to true,
                            "ocrTextBoxes" to region.detected,
                            "bounds" to region.normalized(frame.width,frame.height),
                            "content" to Base64.encodeToString(cropped,Base64.NO_WRAP),
                            "hash" to hash.first,"contrast" to hash.second))
                    }finally{clean.recycle()}
                }finally{frame.recycle()}
            }
        }finally{recognizers.forEach{it.close()}}
        check(scenes.size>=3){"자막과 겹치지 않는 장면이 ${scenes.size}장뿐이에요. 최소 3장 이상 필요해요."}
        return scenes
    }
}
