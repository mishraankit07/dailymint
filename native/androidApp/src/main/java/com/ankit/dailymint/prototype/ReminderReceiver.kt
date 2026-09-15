package com.ankit.dailymint.prototype

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.ankit.dailymint.core.LedgerEngine
import java.time.LocalDate
import java.time.ZoneId
import java.util.Calendar

private const val REMINDER_CHANNEL_ID = "daily-reminder"
private const val REMINDER_REQUEST_CODE = 1320
private const val ACTION_DAILY_REMINDER = "com.ankit.dailymint.prototype.DAILY_REMINDER"

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val engine = LedgerEngine(PreferenceStore(context))
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            ReminderScheduler.apply(context, engine)
            return
        }
        if (intent.action != ACTION_DAILY_REMINDER || !engine.reminderEnabled()) return
        ReminderScheduler.show(context, engine)
    }
}

object ReminderScheduler {
    fun apply(context: Context, engine: LedgerEngine) {
        if (engine.reminderEnabled()) schedule(context, engine.reminderTime()) else cancel(context)
    }

    fun schedule(context: Context, time: String) {
        val parts = time.split(":").mapNotNull { it.toIntOrNull() }
        if (parts.size != 2) return
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextTriggerMillis(parts[0], parts[1]),
            AlarmManager.INTERVAL_DAY,
            reminderIntent(context)
        )
    }

    fun cancel(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(reminderIntent(context))
    }

    fun show(context: Context, engine: LedgerEngine) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(REMINDER_CHANNEL_ID, "Daily reminder", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val daySeed = LocalDate.now(ZoneId.of("Asia/Kolkata")).toEpochDay().toInt()
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, REMINDER_CHANNEL_ID)
        } else {
            android.app.Notification.Builder(context)
        }
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("DailyMint check-in")
            .setContentText(engine.reminderQuote(daySeed) + " Add today's expenses?")
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .build()
        manager.notify(REMINDER_REQUEST_CODE, notification)
    }

    private fun reminderIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REMINDER_REQUEST_CODE,
        Intent(context, ReminderReceiver::class.java).setAction(ACTION_DAILY_REMINDER),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun nextTriggerMillis(hour: Int, minute: Int): Long {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        return calendar.timeInMillis
    }
}
