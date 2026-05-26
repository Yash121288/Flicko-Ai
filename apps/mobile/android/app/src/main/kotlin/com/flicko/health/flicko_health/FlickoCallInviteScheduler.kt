package com.flicko.health.flicko_health

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max

class FlickoCallInviteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != FlickoCallInviteScheduler.ACTION_SHOW_CALL_INVITE) {
            return
        }
        val title = intent.getStringExtra(FlickoCallInviteScheduler.EXTRA_TITLE)
            ?: "Flicko AI is calling"
        val body = intent.getStringExtra(FlickoCallInviteScheduler.EXTRA_BODY)
            ?: "Pick up to continue your health check-in."
        val payload = intent.getStringExtra(FlickoCallInviteScheduler.EXTRA_PAYLOAD)
            ?: return
        FlickoCallInviteScheduler.showNow(context, title, body, payload)
        if (intent.getBooleanExtra(FlickoCallInviteScheduler.EXTRA_REPEATS_DAILY, false)) {
            val previous = intent.getLongExtra(
                FlickoCallInviteScheduler.EXTRA_SCHEDULED_AT,
                System.currentTimeMillis(),
            )
            val next = FlickoCallInviteScheduler.nextDailyTrigger(previous)
            FlickoCallInviteScheduler.schedule(
                context = context,
                title = title,
                body = body,
                payload = payload,
                scheduledAtMillis = next,
                repeatsDaily = true,
            )
        } else {
            FlickoCallInviteScheduler.removeStoredSchedule(context, payload)
        }
    }
}

class FlickoCallInviteBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            FlickoCallInviteScheduler.restoreStoredSchedules(context)
        }
    }
}

object FlickoCallInviteScheduler {
    const val ACTION_SHOW_CALL_INVITE =
        "com.flicko.health.flicko_health.SHOW_AI_CALL_INVITE"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_PAYLOAD = "payload"
    const val EXTRA_SCHEDULED_AT = "scheduledAtMillis"
    const val EXTRA_REPEATS_DAILY = "repeatsDaily"

    private const val CHANNEL_ID = "flicko_native_ai_call_invites_v2"
    private const val CHANNEL_NAME = "Flicko AI incoming calls"
    private val PREMIUM_CALL_VIBRATION_PATTERN = longArrayOf(
        0L,
        70L,
        42L,
        110L,
        42L,
        160L,
    )
    private const val CALL_INVITE_PREFIX = "call-invite:"
    private const val CALL_DECLINED_PREFIX = "call-invite-declined:"
    private const val CALL_ACCEPT_ACTION_ID = "flicko_call_accept"
    private const val CALL_DECLINE_ACTION_ID = "flicko_call_decline"
    private const val FLUTTER_NOTIFICATION_PAYLOAD = "payload"
    private const val FLUTTER_NOTIFICATION_ACTION_ID = "actionId"
    private const val PREFS_NAME = "flicko_native_call_invites"
    private const val PREFS_SCHEDULES = "schedules"

    fun showNow(
        context: Context,
        title: String,
        body: String,
        payload: String,
    ): Boolean {
        if (!payload.startsWith(CALL_INVITE_PREFIX)) {
            return false
        }
        if (!hasNotificationPermission(context)) {
            return false
        }
        return try {
            ensureChannel(context)
            NotificationManagerCompat.from(context).notify(
                notificationId(payload),
                buildNotification(context, title, body, payload),
            )
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    fun schedule(
        context: Context,
        title: String,
        body: String,
        payload: String,
        scheduledAtMillis: Long,
        repeatsDaily: Boolean,
    ): Boolean {
        if (!payload.startsWith(CALL_INVITE_PREFIX)) {
            return false
        }
        val triggerAt = max(scheduledAtMillis, System.currentTimeMillis() + 1_000L)
        val scheduled = scheduleAlarm(
            context = context,
            title = title,
            body = body,
            payload = payload,
            scheduledAtMillis = triggerAt,
            repeatsDaily = repeatsDaily,
        )
        if (scheduled) {
            persistSchedule(
                context = context,
                title = title,
                body = body,
                payload = payload,
                scheduledAtMillis = triggerAt,
                repeatsDaily = repeatsDaily,
            )
        }
        return scheduled
    }

    fun cancel(context: Context, payload: String): Boolean {
        val id = notificationId(payload)
        val alarmIntent = Intent(context, FlickoCallInviteReceiver::class.java).apply {
            action = ACTION_SHOW_CALL_INVITE
            putExtra(EXTRA_PAYLOAD, payload)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            id,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)
            NotificationManagerCompat.from(context).cancel(id)
            removeStoredSchedule(context, payload)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun removeStoredSchedule(context: Context, payload: String) {
        val schedules = readStoredSchedules(context)
        val next = JSONArray()
        for (index in 0 until schedules.length()) {
            val item = schedules.optJSONObject(index) ?: continue
            if (item.optString(EXTRA_PAYLOAD) != payload) {
                next.put(item)
            }
        }
        writeStoredSchedules(context, next)
    }

    fun restoreStoredSchedules(context: Context): Int {
        val now = System.currentTimeMillis()
        val schedules = readStoredSchedules(context)
        val retained = JSONArray()
        var restored = 0
        for (index in 0 until schedules.length()) {
            val item = schedules.optJSONObject(index) ?: continue
            val payload = item.optString(EXTRA_PAYLOAD)
            if (!payload.startsWith(CALL_INVITE_PREFIX)) {
                continue
            }
            val repeatsDaily = item.optBoolean(EXTRA_REPEATS_DAILY, false)
            var scheduledAt = item.optLong(EXTRA_SCHEDULED_AT, 0L)
            if (scheduledAt <= now + 1_000L) {
                if (!repeatsDaily) {
                    continue
                }
                scheduledAt = nextDailyTrigger(scheduledAt)
            }
            val title = item.optString(EXTRA_TITLE, "Flicko AI is calling")
            val body = item.optString(
                EXTRA_BODY,
                "Pick up to continue your health check-in.",
            )
            val scheduled = scheduleAlarm(
                context = context,
                title = title,
                body = body,
                payload = payload,
                scheduledAtMillis = scheduledAt,
                repeatsDaily = repeatsDaily,
            )
            if (scheduled) {
                retained.put(
                    scheduleJson(
                        title = title,
                        body = body,
                        payload = payload,
                        scheduledAtMillis = scheduledAt,
                        repeatsDaily = repeatsDaily,
                    ),
                )
                restored += 1
            }
        }
        writeStoredSchedules(context, retained)
        return restored
    }

    fun nextDailyTrigger(previousMillis: Long): Long {
        var next = previousMillis + 24L * 60L * 60L * 1000L
        val now = System.currentTimeMillis()
        while (next <= now + 1_000L) {
            next += 24L * 60L * 60L * 1000L
        }
        return next
    }

    private fun scheduleAlarm(
        context: Context,
        title: String,
        body: String,
        payload: String,
        scheduledAtMillis: Long,
        repeatsDaily: Boolean,
    ): Boolean {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, FlickoCallInviteReceiver::class.java).apply {
            action = ACTION_SHOW_CALL_INVITE
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_PAYLOAD, payload)
            putExtra(EXTRA_SCHEDULED_AT, scheduledAtMillis)
            putExtra(EXTRA_REPEATS_DAILY, repeatsDaily)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId(payload),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    scheduledAtMillis,
                    pendingIntent,
                )
            } else {
                alarmManager.set(
                    AlarmManager.RTC_WAKEUP,
                    scheduledAtMillis,
                    pendingIntent,
                )
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun buildNotification(
        context: Context,
        title: String,
        body: String,
        payload: String,
    ): Notification {
        val openIntent = mainActivityIntent(context, payload)
        val acceptIntent = mainActivityIntent(context, payload, CALL_ACCEPT_ACTION_ID)
        val declineIntent = mainActivityIntent(
            context,
            payload,
            CALL_DECLINE_ACTION_ID,
        )

        val contentPendingIntent = PendingIntent.getActivity(
            context,
            notificationId("$payload:open"),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val acceptPendingIntent = PendingIntent.getActivity(
            context,
            notificationId("$payload:accept"),
            acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val declinePendingIntent = PendingIntent.getActivity(
            context,
            notificationId("$payload:decline"),
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_flicko_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(body)
                    .setSummaryText("Pick up to continue in Flicko"),
            )
            .setSubText("Flicko AI Health Coach")
            .setTicker("Incoming Flicko AI health call")
            .setColor((0xFF149447).toInt())
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setTimeoutAfter(90_000L)
            .setVibrate(PREMIUM_CALL_VIBRATION_PATTERN)
            .setContentIntent(contentPendingIntent)
            .setFullScreenIntent(contentPendingIntent, true)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.sym_call_incoming,
                    "Pick up",
                    acceptPendingIntent,
                )
                    .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_CALL)
                    .setShowsUserInterface(true)
                    .build(),
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Decline",
                    declinePendingIntent,
                )
                    .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_DELETE)
                    .setShowsUserInterface(true)
                    .build(),
            )
            .build()
    }

    private fun mainActivityIntent(
        context: Context,
        payload: String,
        actionId: String? = null,
    ): Intent {
        return Intent(context, MainActivity::class.java).apply {
            action = "com.flicko.health.flicko_health.AI_CALL_INVITE"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(FLUTTER_NOTIFICATION_PAYLOAD, payload)
            if (actionId != null) {
                putExtra(FLUTTER_NOTIFICATION_ACTION_ID, actionId)
            }
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Call-style Flicko AI health check-ins"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(ringtone, audioAttributes)
            enableVibration(true)
            vibrationPattern = PREMIUM_CALL_VIBRATION_PATTERN
            enableLights(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun hasNotificationPermission(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun persistSchedule(
        context: Context,
        title: String,
        body: String,
        payload: String,
        scheduledAtMillis: Long,
        repeatsDaily: Boolean,
    ) {
        val schedules = readStoredSchedules(context)
        val next = JSONArray()
        for (index in 0 until schedules.length()) {
            val item = schedules.optJSONObject(index) ?: continue
            if (item.optString(EXTRA_PAYLOAD) != payload) {
                next.put(item)
            }
        }
        next.put(
            scheduleJson(
                title = title,
                body = body,
                payload = payload,
                scheduledAtMillis = scheduledAtMillis,
                repeatsDaily = repeatsDaily,
            ),
        )
        writeStoredSchedules(context, next)
    }

    private fun scheduleJson(
        title: String,
        body: String,
        payload: String,
        scheduledAtMillis: Long,
        repeatsDaily: Boolean,
    ): JSONObject {
        return JSONObject()
            .put(EXTRA_TITLE, title)
            .put(EXTRA_BODY, body)
            .put(EXTRA_PAYLOAD, payload)
            .put(EXTRA_SCHEDULED_AT, scheduledAtMillis)
            .put(EXTRA_REPEATS_DAILY, repeatsDaily)
    }

    private fun readStoredSchedules(context: Context): JSONArray {
        val raw = context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREFS_SCHEDULES, "[]")
        return try {
            JSONArray(raw ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun writeStoredSchedules(context: Context, schedules: JSONArray) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREFS_SCHEDULES, schedules.toString())
            .apply()
    }

    private fun notificationId(seed: String): Int {
        var hash = 0
        for (unit in seed.encodeToByteArray()) {
            hash = 0x1fffffff and (hash + unit.toInt())
            hash = 0x1fffffff and (hash + ((0x0007ffff and hash) shl 10))
            hash = hash xor (hash shr 6)
        }
        hash = 0x1fffffff and (hash + ((0x03ffffff and hash) shl 3))
        hash = hash xor (hash shr 11)
        hash = 0x1fffffff and (hash + ((0x00003fff and hash) shl 15))
        return if (hash == 0) 1 else hash
    }
}
