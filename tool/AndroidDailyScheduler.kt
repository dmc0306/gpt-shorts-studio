package com.local.shorts_studio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.content.pm.ServiceInfo
import androidx.work.ForegroundInfo
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/** Schedules a local on-device reminder using OS-managed persistent jobs.
 *
 * IMPORTANT: This native bridge only schedules and notifies. It does not
 * claim a background Flutter renderer/uploader is already implemented.
 * Starting UI automatically from a background worker is intentionally avoided.
 */
object AndroidDailyScheduler {
    private const val WORK_NAME = "shorts_daily_device_trigger"
    private const val PREF_NAME = "shorts_daily_schedule"
    private const val ENABLED = "enabled"
    private const val HOUR = "hour"
    private const val MINUTE = "minute"
    private const val LAST_NOTICE = "last_notice_date"
    private const val CREATORS = "licensed_creators"
    private const val RIGHTS = "rights_attested"
    private const val LAST_RESULT = "last_result"
    private val SEOUL = ZoneId.of("Asia/Seoul")

    fun configure(context:Context, enabled:Boolean, hour:Int, minute:Int,
                  creators:String, rights:Boolean):Map<String,Any> {
        require(hour in 0..23 && minute in 0..59){"유효한 시각을 입력해 주세요."}
        val handles=creators.split(",").map{it.trim().removePrefix("@")}
            .filter{it.isNotEmpty()}.map{it.lowercase()}
        require(handles.size in 0..20 && handles.all{
            Regex("[a-z0-9._]{2,24}").matches(it)
        }){"사용 권한이 있는 TikTok 계정을 쉼표로 구분해 입력해 주세요."}
        if(enabled)require(rights&&handles.isNotEmpty()){
            "매일 자동 공개에는 재사용 허가 계정과 권리 확인이 필요합니다."
        }
        val prefs=context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        check(prefs.edit().putBoolean(ENABLED,enabled)
            .putInt(HOUR,hour).putInt(MINUTE,minute)
            .putString(CREATORS,handles.joinToString(","))
            .putBoolean(RIGHTS,rights).commit()){"예약 저장 실패"}
        val manager=WorkManager.getInstance(context)
        if(!enabled){
            manager.cancelUniqueWork(WORK_NAME)
        }else{
            val now=LocalDateTime.now(SEOUL)
            var next=now.toLocalDate().atTime(hour,minute)
            if(!next.isAfter(now))next=next.plusDays(1)
            val ms=Duration.between(now,next).toMillis().coerceAtLeast(1000)
            val constraints=Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()
            val work=PeriodicWorkRequestBuilder<AndroidDailyReminderWorker>(
                24,TimeUnit.HOURS)
                .setInitialDelay(ms,TimeUnit.MILLISECONDS)
                .setConstraints(constraints)
                .addTag(WORK_NAME)
                .build()
            manager.enqueueUniquePeriodicWork(WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,work)
        }
        return status(context)
    }

    fun status(context:Context):Map<String,Any> {
        val prefs=context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
        return mapOf(
            "enabled" to prefs.getBoolean(ENABLED,false),
            "hour" to prefs.getInt(HOUR,9),
            "minute" to prefs.getInt(MINUTE,0),
            "lastNoticeDate" to (prefs.getString(LAST_NOTICE,"") ?: ""),
            "lastResult" to (prefs.getString(LAST_RESULT,"") ?: ""),
            "creators" to (prefs.getString(CREATORS,"") ?: ""),
            "rightsAttested" to prefs.getBoolean(RIGHTS,false),
            "mode" to "in_process_background_or_notification",
        )
    }

    fun creatorList(context:Context):List<String>{
        val prefs=context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
        if(!prefs.getBoolean(RIGHTS,false))return emptyList()
        return (prefs.getString(CREATORS,"") ?: "").split(",").filter{it.isNotBlank()}
    }

    fun record(context:Context,result:String){
        context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
            .edit().putString(LAST_RESULT,result).apply()
    }

    fun shouldNotify(context:Context):Boolean{
        val prefs=context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
        if(!prefs.getBoolean(ENABLED,false))return false
        val now=LocalDateTime.now(SEOUL)
        if(now.toLocalTime()<LocalTime.of(prefs.getInt(HOUR,9),prefs.getInt(MINUTE,0)))
            return false
        val day=LocalDate.now(SEOUL).toString()
        if(prefs.getString(LAST_NOTICE,"")==day)return false
        return prefs.edit().putString(LAST_NOTICE,day).commit()
    }
}

class AndroidDailyReminderWorker(
    context: Context, params:WorkerParameters
):CoroutineWorker(context,params) {
    override suspend fun doWork():Result {
        if(!AndroidDailyScheduler.shouldNotify(applicationContext))
            return Result.success()
        val channel="shorts_daily_reminder"
        val notifications=applicationContext.getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(
            channel,"예약된 쇼츠 제작",NotificationManager.IMPORTANCE_DEFAULT))
        val open=Intent(applicationContext,MainActivity::class.java)
            .setAction("com.local.shorts_studio.DAILY_READY")
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending=PendingIntent.getActivity(
            applicationContext,23,open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val handles=AndroidDailyScheduler.creatorList(applicationContext)
        val channelToFlutter=MainActivity.dailyRunChannel
        if(channelToFlutter!=null && handles.isNotEmpty()){
            val foreground=Notification.Builder(applicationContext,channel)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("쇼츠 1개 자동 제작 진행")
                .setContentText("원본 검색 → Gemini → 자막 → MP4 → YouTube")
                .setContentIntent(pending).setOngoing(true).build()
            try{
                val types=ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                    (if(Build.VERSION.SDK_INT>=35)
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING else 0)
                setForeground(ForegroundInfo(804,foreground,types))
                val result=withTimeoutOrNull(45*60*1000L){
                    withContext(Dispatchers.Main){
                        suspendCancellableCoroutine<Boolean>{ continuation ->
                            channelToFlutter.invokeMethod("startDaily",
                                mapOf("creators" to handles),
                                object:MethodChannel.Result {
                                    override fun success(value:Any?){
                                        if(continuation.isActive)continuation.resume(value==true)
                                    }
                                    override fun error(code:String,message:String?,details:Any?){
                                        if(continuation.isActive)continuation.resume(false)
                                    }
                                    override fun notImplemented(){
                                        if(continuation.isActive)continuation.resume(false)
                                    }
                                })
                        }
                    }
                }
                if(result==true){
                    AndroidDailyScheduler.record(applicationContext,"성공: Youtube 업로드 접수")
                    return Result.success()
                }
                AndroidDailyScheduler.record(applicationContext,"자동 제작 실패 또는 Android 작업 중단")
            }catch(_:Exception){
                AndroidDailyScheduler.record(applicationContext,"Android 백그라운드 실행 제한")
            }
        }else{
            AndroidDailyScheduler.record(applicationContext,
                "앱 프로세스가 종료되어 사용자 실행 대기")
        }
        val note=Notification.Builder(applicationContext,channel)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("오늘의 쇼츠 제작을 확인해 주세요")
            .setContentText("자동 실행이 완료되지 않았어요. 눌러서 앱에서 확인하세요.")
            .setContentIntent(pending).setAutoCancel(true).build()
        notifications.notify(805,note)
        return Result.success()
    }
}
