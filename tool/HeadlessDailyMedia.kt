package com.local.shorts_studio

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationService
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Native media adapter owned by a FlutterEngine that has no Activity.
 * Existing MainActivity adapter stays intact for manual editing; this one
 * intentionally exposes only the background job's approved method set.
 */
@UnstableApi
class HeadlessDailyMedia(private val context:Context,engine:FlutterEngine) {
    private val main=Handler(Looper.getMainLooper())
    private val io=Executors.newSingleThreadExecutor()
    private val prefs=context.getSharedPreferences("studio",Context.MODE_PRIVATE)
    private val channel=MethodChannel(engine.dartExecutor.binaryMessenger,"studio.local/media")
    private var exporting=false
    private var transformer:Transformer?=null
    private var exportImages=mutableListOf<Bitmap>()
    private var uploadTemp:File?=null

    init {
        channel.setMethodCallHandler {call,result ->
            try{handle(call,result)}catch(e:Exception){
                result.error("DAILY_NATIVE",e.message?:"백그라운드 미디어 오류",null)
            }
        }
    }

    private fun async(r:MethodChannel.Result,run:()->Any?){
        io.execute{
            try{val value=run();main.post{r.success(value)}}
            catch(e:Exception){main.post{r.error("DAILY_NATIVE",e.message,null)}}
        }
    }
    private fun secret():SecretKey{
        val store=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
        (store.getKey("studio-gemini",null) as? SecretKey)?.let{return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
            .apply{
                init(KeyGenParameterSpec.Builder("studio-gemini",
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
    }
    private fun decrypt(prefix:String):String{
        val encoded=prefs.getString("${prefix}Key",null)?:return ""
        return try{
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,secret(),
                GCMParameterSpec(128,Base64.decode(prefs.getString("${prefix}Iv",""),
                    Base64.NO_WRAP)))
            String(cipher.doFinal(Base64.decode(encoded,Base64.NO_WRAP)),Charsets.UTF_8)
        }catch(_:Exception){""}
    }
    private fun encrypt(prefix:String,plain:String){
        val cipher=Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE,secret())
        check(prefs.edit()
            .putString("${prefix}Key",Base64.encodeToString(
                cipher.doFinal(plain.toByteArray(Charsets.UTF_8)),Base64.NO_WRAP))
            .putString("${prefix}Iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP))
            .commit()){"인증 상태 저장 실패"}
    }
    private fun atomicFile(path:File,value:String){
        val tmp=File(path.parentFile,path.name+".tmp")
        tmp.writeText(value)
        check(tmp.renameTo(path)){"상태 파일 저장 실패"}
    }
    private fun loadHistory():JSONObject {
        val text=prefs.getString("daily_headless_history","{}")?:"{}"
        return try{JSONObject(text)}catch(_:Exception){JSONObject()}
    }
    private fun saveHistory(record:JSONObject) {
        check(prefs.edit().putString("daily_headless_history",
            record.toString()).commit()){"중복 업로드 방지 기록 저장 실패"}
    }
    private fun history():Map<String,Any>{
        val state=loadHistory()
        val arr=state.optJSONArray("usedVideoIds")?:JSONArray()
        return mapOf(
            "usedVideoIds" to (0 until arr.length()).map{arr.optString(it)},
            "lastYoutubeId" to state.optString("lastYoutubeId","")
        )
    }
    private fun reserveSource(videoId:String){
        require(Regex("^[0-9]{8,30}$").matches(videoId)){"원본 TikTok ID 오류"}
        val state=loadHistory()
        val arr=state.optJSONArray("usedVideoIds")?:JSONArray()
        val seen=(0 until arr.length()).map{arr.optString(it)}.toMutableSet()
        check(seen.add(videoId)){"이미 이전에 사용한 영상입니다."}
        val compact=JSONArray()
        seen.takeLast(1200).forEach{compact.put(it)}
        state.put("usedVideoIds",compact)
        state.put("pendingSourceId",videoId)
        saveHistory(state)
    }
    private fun recordSuccess(id:String,videoId:String){
        require(Regex("^[0-9]{8,30}$").matches(id))
        require(Regex("^[A-Za-z0-9_-]{11}$").matches(videoId)){"YouTube ID 형식 오류"}
        val state=loadHistory()
        require(state.optString("pendingSourceId")==id){"게시 중복 방지 상태가 없습니다."}
        state.put("lastYoutubeId",videoId)
        state.put("pendingSourceId","")
        saveHistory(state)
    }
    private fun authState():AuthState?{
        val json=decrypt("youtubeChrome")
        if(json.isBlank())return null
        val state=AuthState.jsonDeserialize(json)
        val request=state.lastAuthorizationResponse?.request
        require(request!=null&&
            request.clientId==YouTubeChromeAuth.CLIENT_ID &&
            request.configuration.tokenEndpoint.toString()=="https://oauth2.googleapis.com/token") {
            "앱에서 연결한 Chrome 인증 상태가 올바르지 않습니다."
        }
        return state
    }
    private fun chromeStatus():Map<String,Any>{
        val state=authState()
        return mapOf(
            "hasGrant" to (state?.isAuthorized==true),
            "hasRefreshToken" to !state?.refreshToken.isNullOrBlank(),
            "expiresAt" to (state?.accessTokenExpirationTime?:0L),
        )
    }
    private fun refreshToken(result:MethodChannel.Result,force:Boolean){
        val state=authState()
        if(state?.isAuthorized!=true||state.refreshToken.isNullOrBlank()){
            result.error("DAILY_OAUTH","YouTube Chrome 자동 로그인 갱신이 필요합니다.",null)
            return
        }
        if(force)state.setNeedsTokenRefresh(true)
        val service=AuthorizationService(context)
        try{
            state.performActionWithFreshTokens(service){accessToken,_,error ->
                main.post{
                    try{
                        if(error!=null||accessToken.isNullOrBlank()) {
                            result.error("DAILY_OAUTH","Chrome 인증 갱신 실패",null)
                        }else{
                            encrypt("youtubeChrome",state.jsonSerializeString())
                            result.success(chromeStatus()+mapOf("accessToken" to accessToken))
                        }
                    }catch(e:Exception){result.error("DAILY_OAUTH",e.message,null)}
                    finally{service.dispose()}
                }
            }
        }catch(e:Exception){
            service.dispose()
            result.error("DAILY_OAUTH",e.message,null)
        }
    }
    private fun getVideoInfo(file:File,name:String,id:String):Map<String,Any>{
        val media=MediaMetadataRetriever()
        try{
            media.setDataSource(file.absolutePath)
            val duration=(media.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDouble()?:0.0)/1000
            require(duration in 5.0..60.0){"5~60초 원본만 사용할 수 있습니다."}
            val width=(media.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toDouble()?:0.0)
            val height=(media.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toDouble()?:0.0)
            require(width>0&&height>0&&width<=height){"세로 영상만 사용합니다."}
            val thumb=File(context.filesDir,"thumbnails/$id.jpg")
            thumb.parentFile?.mkdirs()
            media.getScaledFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,360,640)?.let{
                try{thumb.outputStream().use{out->it.compress(Bitmap.CompressFormat.JPEG,80,out)}}
                finally{it.recycle()}
            }
            return mapOf("id" to id,"name" to name,"path" to file.absolutePath,
                "thumbnail" to (if(thumb.exists())thumb.absolutePath else ""),
                "duration" to duration,"videoWidth" to width,"videoHeight" to height)
        }finally{media.release()}
    }
    private fun savedVideo(uriText:String):File {
        val uri=Uri.parse(uriText)
        require(uri.scheme=="content"&&uri.authority=="media"){
            "Shorts Studio 저장 영상만 YouTube에 올릴 수 있습니다."
        }
        val dest=File(context.cacheDir,"youtube_${UUID.randomUUID()}.mp4")
        try{
            context.contentResolver.openInputStream(uri)?.use{src->
                dest.outputStream().use{dst->
                    val buffer=ByteArray(65536)
                    while(true){
                        val read=src.read(buffer)
                        if(read<0)break
                        check(context.cacheDir.usableSpace>32*1024*1024){"저장 공간 부족"}
                        dst.write(buffer,0,read)
                    }
                }
            }?:error("MP4를 열 수 없습니다.")
            return dest
        }catch(e:Exception){dest.delete();throw e}
    }
    private fun publishToGallery(file:File):String {
        val values=ContentValues().apply{
            put(MediaStore.Video.Media.DISPLAY_NAME,
                "ShortsStudio_${System.currentTimeMillis()}.mp4")
            put(MediaStore.Video.Media.MIME_TYPE,"video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH,"Movies/ShortsStudio")
            put(MediaStore.Video.Media.IS_PENDING,1)
        }
        val uri=context.contentResolver.insert(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,values)
            ?:error("갤러리 저장 실패")
        try{
            context.contentResolver.openOutputStream(uri)?.use{dst->
                file.inputStream().use{it.copyTo(dst)}
            }?:error("갤러리 영상 파일을 열 수 없습니다.")
            check(context.contentResolver.update(
                uri,ContentValues().apply{put(MediaStore.Video.Media.IS_PENDING,0)},
                null,null)>0)
            return uri.toString()
        }catch(e:Exception){
            context.contentResolver.delete(uri,null,null)
            throw e
        }
    }
    private data class TimedOverlay(
        val startUs:Long,val endUs:Long,val bitmap:Bitmap,
        val settings:StaticOverlaySettings
    )

    private fun export(call:MethodCall,result:MethodChannel.Result){
        check(!exporting){"다른 백그라운드 영상 변환이 진행 중입니다."}
        val path=File(call.argument<String>("path")?:"").canonicalFile
        val sources=File(context.filesDir,"sources").canonicalFile
        require(path.parentFile==sources&&path.name.endsWith(".mp4")&&path.isFile){
            "앱에서 다운로드한 MP4만 변환할 수 있습니다."
        }
        val start=call.argument<Number>("startMs")?.toLong()?:0L
        val end=call.argument<Number>("endMs")?.toLong()?:0L
        require(start>=0&&end>start&&end-start<=60000){"영상 클립 길이 오류"}
        val poster=call.argument<ByteArray>("overlay")?:error("상단 제목 이미지가 없습니다.")
        require(poster.size in 500..8_000_000){"제목 이미지 크기 오류"}
        val bitmap=BitmapFactory.decodeByteArray(poster,0,poster.size)
            ?:error("제목 이미지를 해석하지 못했습니다.")
        val captions=mutableListOf<TimedOverlay>()
        val images=mutableListOf<Bitmap>(bitmap)
        val entries=call.argument<List<Map<String,Any>>>("timedOverlays")?:emptyList()
        require(entries.size<=20){"자막은 최대 20개입니다."}
        try{
            for(entry in entries){
                val bytes=entry["png"] as? ByteArray ?:error("자막 이미지 누락")
                val image=BitmapFactory.decodeByteArray(bytes,0,bytes.size)
                    ?:error("자막 이미지 오류")
                images.add(image)
                require(image.width==1080&&image.height==200)
                val from=(entry["startUs"] as Number).toLong()
                val to=(entry["endUs"] as Number).toLong()
                require(from>=0&&to>from&&to<=(end-start)*1000+100000)
                val top=(entry["topPx"] as? Number)?.toFloat()?:1200f
                require(top.isFinite()&&top>=420f&&top<=1720f)
                captions.add(TimedOverlay(from,to,image,
                    StaticOverlaySettings.Builder()
                        .setBackgroundFrameAnchor(0f,1f-2f*(top+100f)/1920f)
                        .build()))
            }
            val layers=mutableListOf<TextureOverlay>(
                BitmapOverlay.createStaticBitmapOverlay(bitmap))
            if(captions.isNotEmpty()){
                val blank=Bitmap.createBitmap(1080,200,Bitmap.Config.ARGB_8888)
                images.add(blank)
                val emptySettings=StaticOverlaySettings.Builder().build()
                layers.add(object:BitmapOverlay(){
                    override fun getBitmap(presentationTimeUs:Long):Bitmap=
                        captions.firstOrNull{
                            presentationTimeUs>=it.startUs && presentationTimeUs<it.endUs
                        }?.bitmap?:blank
                    override fun getOverlaySettings(presentationTimeUs:Long)=
                        captions.firstOrNull{
                            presentationTimeUs>=it.startUs && presentationTimeUs<it.endUs
                        }?.settings?:emptySettings
                })
            }
            val fit=if(call.argument<Boolean>("crop")==true)
                Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
            else Presentation.LAYOUT_SCALE_TO_FIT
            val item=MediaItem.Builder().setUri(Uri.fromFile(path))
                .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(start).setEndPositionMs(end).build()).build()
            val effects=Effects(emptyList(),listOf(
                Presentation.createForWidthAndHeight(1080,1080,fit),
                Presentation.createForWidthAndHeight(1080,1920,
                    Presentation.LAYOUT_SCALE_TO_FIT),
                OverlayEffect(layers)))
            val edited=EditedMediaItem.Builder(item)
                .setRemoveAudio(call.argument<Boolean>("mute")==true)
                .setEffects(effects).build()
            val output=File(context.cacheDir,"daily_${UUID.randomUUID()}.mp4")
            exporting=true
            exportImages=images
            transformer=Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object:Transformer.Listener{
                    override fun onCompleted(composition:Composition,export:ExportResult){
                        io.execute{
                            try{
                                val uri=publishToGallery(output)
                                main.post{result.success(uri)}
                            }catch(e:Exception){
                                main.post{result.error("DAILY_EXPORT",e.message,null)}
                            }finally{main.post{cleanupExport(output)}}
                        }
                    }
                    override fun onError(composition:Composition,export:ExportResult,
                                         error:ExportException){
                        result.error("DAILY_EXPORT","영상 변환 실패: ${error.errorCode}",null)
                        cleanupExport(output)
                    }
                }).build()
            transformer!!.start(edited,output.absolutePath)
        }catch(e:Exception){
            exporting=false
            transformer=null
            images.forEach{it.recycle()}
            exportImages.clear()
            throw e
        }
    }
    private fun cleanupExport(output:File){
        output.delete()
        transformer=null
        exporting=false
        exportImages.forEach{if(!it.isRecycled)it.recycle()}
        exportImages.clear()
    }

    private fun handle(call:MethodCall,result:MethodChannel.Result){
        when(call.method){
            "loadAiSettings" -> result.success(mapOf(
                "key" to decrypt("ai"),
                "searchKey" to decrypt("search"),
                "model" to (prefs.getString("aiModel","gemini-3.5-flash-lite")
                    ?:"gemini-3.5-flash-lite")
            ))
            "loadProjects" -> async(result){
                val file=File(context.filesDir,"projects.json")
                if(file.exists())file.readText()else "[]"
            }
            "saveProjects" -> async(result){
                val json=call.argument<String>("json")?:error("프로젝트 누락")
                JSONArray(json)
                atomicFile(File(context.filesDir,"projects.json"),json)
                null
            }
            "loadDailyHistory" -> result.success(history())
            "reserveDailySource" -> {
                reserveSource(call.argument<String>("videoId")?:error("ID 누락"))
                result.success(null)
            }
            "dailyUploadSuccess" -> {
                recordSuccess(call.argument<String>("sourceId")?:"",
                    call.argument<String>("youtubeVideoId")?:"")
                result.success(null)
            }
            "downloadPath" -> async(result) {
                require(context.filesDir.usableSpace>64L*1024*1024){"저장 공간 부족"}
                File(context.filesDir,"sources").apply{mkdirs()}
                File(context.filesDir,"sources/${UUID.randomUUID()}.part").absolutePath
            }
            "inspectDownload" -> async(result){
                val part=File(call.argument<String>("path")?:"").canonicalFile
                require(part.parentFile==File(context.filesDir,"sources").canonicalFile &&
                    part.name.endsWith(".part")&&part.isFile)
                val id=part.name.removeSuffix(".part")
                val target=File(part.parentFile,"$id.mp4")
                check(part.renameTo(target)){"MP4 파일 이름 변경 실패"}
                try{getVideoInfo(target,call.argument<String>("name")?:"TikTok",id)}
                catch(e:Exception){target.delete();throw e}
            }
            "scanOriginalText" -> async(result){
                val file=File(call.argument<String>("path")?:"").canonicalFile
                require(file.parentFile==File(context.filesDir,"sources").canonicalFile &&
                    file.name.endsWith(".mp4")&&file.isFile)
                OriginalTextScanner.scan(file,
                    (call.argument<Number>("startMs")?.toDouble()?:0.0)/1000,
                    (call.argument<Number>("endMs")?.toDouble()?:0.0)/1000,
                    call.argument<Boolean>("crop")==true)
            }
            "export" -> export(call,result)
            "youtubeSettings" -> result.success(prefs.getString("youtubeSettings",null))
            "youtubeChromeStatus" -> async(result){chromeStatus()}
            "youtubeChromeToken" ->
                refreshToken(result,call.argument<Boolean>("forceRefresh")==true)
            "youtubeUploadState" ->
                result.success(prefs.getString(
                    "youtubeUpload:${call.argument<String>("uri")?:error("uri 누락")}",null))
            "saveYoutubeUploadState" -> {
                val json=call.argument<String>("json")?:error("업로드 상태 누락")
                JSONObject(json)
                check(prefs.edit().putString(
                    "youtubeUpload:${call.argument<String>("uri")?:error("uri 누락")}",
                    json).commit())
                result.success(null)
            }
            "saveYoutubeSettings" -> {
                val json=call.argument<String>("json")?:error("YouTube 설정 누락")
                JSONObject(json)
                check(prefs.edit().putString("youtubeSettings",json).commit())
                result.success(null)
            }
            "prepareYoutubeVideo" -> async(result){
                savedVideo(call.argument<String>("uri")?:"").absolutePath
            }
            "cleanupYoutubeVideo" -> async(result){
                val f=File(call.argument<String>("path")?:"").canonicalFile
                require(f.parentFile==context.cacheDir.canonicalFile&&
                    f.name.startsWith("youtube_"))
                f.delete()
                null
            }
            "youtubeKeepAwake" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    fun close(){
        channel.setMethodCallHandler(null)
        transformer?.cancel()
        exportImages.forEach{if(!it.isRecycled)it.recycle()}
        exportImages.clear()
        io.shutdownNow()
    }
}
