package com.local.shorts_studio

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * A full separate Flutter AOT entry point. Unlike MainActivity.dailyRunChannel
 * it works when the Activity/previous Flutter engine no longer exists.
 *
 * Worker owns lifetime; progress and a single final completion are reported
 * to WorkManager through MethodChannel without starting an Activity.
 */
@UnstableApi
object AndroidHeadlessDailyRunner {
    suspend fun execute(
        context:Context,
        allowedCreators:List<String>,
        onProgress:(String)->Unit
    ):Boolean {
        require(allowedCreators.isNotEmpty())
        val completed=CompletableDeferred<Boolean>()
        var engine:FlutterEngine?=null
        var media:HeadlessDailyMedia?=null
        val flutterLoader=FlutterInjector.instance().flutterLoader()
        try{
            withContext(Dispatchers.Main) {
                flutterLoader.startInitialization(context)
                flutterLoader.ensureInitializationComplete(context,null)
                val newEngine=FlutterEngine(context)
                engine=newEngine
                media=HeadlessDailyMedia(context,newEngine)
                val callback=MethodChannel(newEngine.dartExecutor.binaryMessenger,
                    "studio.local/daily_runner")
                callback.setMethodCallHandler{call,result->
                    when(call.method){
                        "settings" -> result.success(mapOf(
                            "creators" to allowedCreators
                        ))
                        "progress" -> {
                            onProgress(call.argument<String>("stage")?.take(140)
                                ?:"진행 중")
                            result.success(null)
                        }
                        "finished" -> {
                            val ok=call.argument<Boolean>("success")==true
                            onProgress(call.argument<String>("message")?.take(200)
                                ?:if(ok)"업로드 성공"else"영상 제작 실패")
                            if(!completed.isCompleted)completed.complete(ok)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
                newEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        flutterLoader.findAppBundlePath(),
                        "dailyHeadlessMain"
                    )
                )
            }
            // Long-running media-processing foreground work is bounded.
            return withTimeoutOrNull(42*60*1000L){
                completed.await()
            } ?: false
        }catch(_:Exception){
            return false
        }finally{
            withContext(Dispatchers.Main){
                try{media?.close()}catch(_:Exception){}
                try{engine?.destroy()}catch(_:Exception){}
            }
        }
    }
}
