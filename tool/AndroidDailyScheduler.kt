package com.local.shorts_studio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
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
    private val SEOUL = ZoneId.of("Asia/Seoul")

    fun configure(context:Context, enabled:Boolean, hour:Int, minute:Int):Map<String,Any> {
        require(hour in 0..23 && minute in 0..59){"유효한 시각을 입력해 주세요."}
        val prefs=context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        check(prefs.edit().putBoolean(ENABLED,enabled)
            .putInt(HOUR,hour).putInt(MINUTE,minute).commit()){"예약 저장 실패"}
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
            "mode" to "notification_fallback",
        )
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
        val note=Notification.Builder(applicationContext,channel)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("예약된 쇼츠 자동 제작 시작")
            .setContentText("영상을 찾고 제작하려면 눌러서 앱을 열어 주세요.")
            .setStyle(Notification.BigTextStyle().bigText(
                "기기 백그라운드 알림이 도착했습니다. " +
                "영상 검색·Gemini·렌더링·공개 업로드는 아직 자동 시작되지 않습니다."))
            .setContentIntent(pending)
            .setAutoCancel(true).build()
        notifications.notify(804,note)
        return Result.success()
    }
}
