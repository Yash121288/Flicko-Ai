package com.flicko.health.flicko_health

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val callChannelName = "flicko.health/live_call_service"
    private val callEventChannelName = "flicko.health/live_call_events"
    private val emergencyCallChannelName = "flicko.health/emergency_call"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingCallInvitePayload: String? = null
    private var pendingOpenLiveCall = false
    private val consumedCallInvitePayloads = mutableSetOf<String>()

    // Texture mode avoids SurfaceView BLAST buffer starvation on some
    // MediaTek/Mali devices during phone-call and live-audio transitions.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        cacheOpenLiveCallIntent(intent)
        cacheCallInvitePayload(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cacheOpenLiveCallIntent(intent)
        cacheCallInvitePayload(intent)
        FlickoCallEventBus.init(applicationContext)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, callEventChannelName)
            .setStreamHandler(FlickoCallEventBus)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title") ?: "Call in progress"
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val apiKey = call.argument<String>("apiKey") ?: ""
                        val model = call.argument<String>("model") ?: ""
                        val voiceName = call.argument<String>("voiceName") ?: ""
                        val problemName = call.argument<String>("problemName") ?: ""
                        val profileContext = call.argument<String>("profileContext") ?: ""
                        val openingScript = call.argument<String>("openingScript") ?: ""
                        val deferFirstPlayback =
                            call.argument<Boolean>("deferFirstPlayback") ?: false
                        val baseUri = call.argument<String>("baseUri") ?: ""
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_START
                            putExtra(FlickoCallForegroundService.EXTRA_TITLE, title)
                            putExtra(FlickoCallForegroundService.EXTRA_SUBTITLE, subtitle)
                            putExtra(FlickoCallForegroundService.EXTRA_API_KEY, apiKey)
                            putExtra(FlickoCallForegroundService.EXTRA_MODEL, model)
                            putExtra(FlickoCallForegroundService.EXTRA_VOICE_NAME, voiceName)
                            putExtra(FlickoCallForegroundService.EXTRA_PROBLEM_NAME, problemName)
                            putExtra(FlickoCallForegroundService.EXTRA_PROFILE_CONTEXT, profileContext)
                            putExtra(FlickoCallForegroundService.EXTRA_OPENING_SCRIPT, openingScript)
                            putExtra(FlickoCallForegroundService.EXTRA_DEFER_FIRST_PLAYBACK, deferFirstPlayback)
                            putExtra(FlickoCallForegroundService.EXTRA_BASE_URI, baseUri)
                        }
                        result.success(startFlickoCallService(intent))
                    }
                    "stop" -> {
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "endCallAndFlushTranscript" -> {
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_FLUSH_AND_STOP
                        }
                        startService(intent)
                        mainHandler.postDelayed(
                            { result.success(FlickoCallEventBus.snapshotTranscript()) },
                            FLUSH_RESULT_DELAY_MS,
                        )
                    }
                    "setMicEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_SET_MIC
                            putExtra(FlickoCallForegroundService.EXTRA_ENABLED, enabled)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "setSpeakerEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_SET_SPEAKER
                            putExtra(FlickoCallForegroundService.EXTRA_ENABLED, enabled)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "sendTextTurn" -> {
                        val text = call.argument<String>("text") ?: ""
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_SEND_TEXT_TURN
                            putExtra(FlickoCallForegroundService.EXTRA_TEXT, text)
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "releaseDeferredPlayback" -> {
                        val intent = Intent(this, FlickoCallForegroundService::class.java).apply {
                            action = FlickoCallForegroundService.ACTION_RELEASE_DEFERRED_PLAYBACK
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "getTranscript" -> {
                        result.success(FlickoCallEventBus.snapshotTranscript())
                    }
                    "isRunning" -> {
                        result.success(FlickoCallForegroundService.serviceRunning)
                    }
                    "consumeOpenLiveCallSignal" -> {
                        val shouldOpen = pendingOpenLiveCall
                        pendingOpenLiveCall = false
                        result.success(shouldOpen)
                    }
                    "consumeCallInvitePayload" -> {
                        cacheCallInvitePayload(intent)
                        val payload = pendingCallInvitePayload
                        pendingCallInvitePayload = null
                        if (payload != null) {
                            consumedCallInvitePayloads.add(payload)
                        }
                        result.success(payload)
                    }
                    "showNativeCallInvite" -> {
                        val title = call.argument<String>("title") ?: "Flicko AI is calling"
                        val body = call.argument<String>("body") ?: "Pick up to continue your health check-in."
                        val payload = call.argument<String>("payload") ?: ""
                        result.success(
                            FlickoCallInviteScheduler.showNow(
                                this,
                                title,
                                body,
                                payload,
                            ),
                        )
                    }
                    "scheduleNativeCallInvite" -> {
                        val title = call.argument<String>("title") ?: "Flicko AI is calling"
                        val body = call.argument<String>("body") ?: "Pick up to continue your health check-in."
                        val payload = call.argument<String>("payload") ?: ""
                        val scheduledAtMillis = call.argument<Number>("scheduledAtMillis")
                            ?.toLong()
                            ?: 0L
                        val repeatsDaily = call.argument<Boolean>("repeatsDaily") ?: false
                        result.success(
                            FlickoCallInviteScheduler.schedule(
                                context = this,
                                title = title,
                                body = body,
                                payload = payload,
                                scheduledAtMillis = scheduledAtMillis,
                                repeatsDaily = repeatsDaily,
                            ),
                        )
                    }
                    "cancelNativeCallInvite" -> {
                        val payload = call.argument<String>("payload") ?: ""
                        result.success(FlickoCallInviteScheduler.cancel(this, payload))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, emergencyCallChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "placeEmergencyCall" -> {
                        val number = call.argument<String>("number")
                            ?.filterIndexed { index, char ->
                                char.isDigit() || (char == '+' && index == 0)
                            }
                            ?.trim()
                            .orEmpty()
                        if (number.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val preferredSimSlot = call.argument<Number>("simSlot")
                            ?.toInt()
                            ?: DEFAULT_SIM_SLOT
                        if (!hasCallPhonePermission()) {
                            result.error(
                                "missing_call_phone_permission",
                                "CALL_PHONE permission is not granted.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        result.success(placeEmergencyCall(number, preferredSimSlot))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun placeEmergencyCall(number: String, preferredSimSlot: Int): Boolean {
        val phoneAccount = preferredPhoneAccount(preferredSimSlot)
        if (placeCallViaTelecom(number, phoneAccount)) {
            return true
        }
        return placeCallViaIntent(number, phoneAccount, preferredSimSlot)
    }

    private fun placeCallViaTelecom(
        number: String,
        phoneAccount: PhoneAccountHandle?,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return false
        }
        return try {
            val telecomManager = getSystemService(TelecomManager::class.java) ?: return false
            val extras = Bundle().apply {
                if (phoneAccount != null) {
                    putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccount)
                }
            }
            telecomManager.placeCall(Uri.parse("tel:$number"), extras)
            true
        } catch (error: SecurityException) {
            Log.e(TAG, "Telecom emergency call permission denied", error)
            false
        } catch (error: Exception) {
            Log.e(TAG, "Could not place emergency call via TelecomManager", error)
            false
        }
    }

    private fun placeCallViaIntent(
        number: String,
        phoneAccount: PhoneAccountHandle?,
        preferredSimSlot: Int,
    ): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && phoneAccount != null) {
                    putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccount)
                }
                putExtra("com.android.phone.extra.slot", preferredSimSlot)
                putExtra("slot", preferredSimSlot)
                putExtra("simSlot", preferredSimSlot)
                putExtra("sim_slot", preferredSimSlot)
            }
            startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            Log.e(TAG, "No phone call activity available", error)
            false
        } catch (error: SecurityException) {
            Log.e(TAG, "Emergency call permission denied", error)
            false
        } catch (error: Exception) {
            Log.e(TAG, "Could not place emergency call", error)
            false
        }
    }

    private fun preferredPhoneAccount(preferredSimSlot: Int): PhoneAccountHandle? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return null
        }
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return null
            val accounts = telecomManager.callCapablePhoneAccounts
            if (accounts.isNullOrEmpty()) {
                return null
            }
            val index = preferredSimSlot.coerceIn(0, accounts.size - 1)
            accounts[index]
        } catch (error: SecurityException) {
            Log.e(TAG, "SIM phone account access denied", error)
            null
        } catch (error: Exception) {
            Log.e(TAG, "Could not resolve SIM phone account", error)
            null
        }
    }

    private fun hasCallPhonePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.CALL_PHONE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            packageManager.checkPermission(
                Manifest.permission.CALL_PHONE,
                packageName,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun startFlickoCallService(intent: Intent): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (error: Exception) {
            Log.e(TAG, "Could not start Flicko call foreground service", error)
            false
        }
    }

    private fun cacheOpenLiveCallIntent(intent: Intent?) {
        if (intent == null) {
            return
        }
        if (intent.getBooleanExtra(OPEN_LIVE_CALL_EXTRA, false)) {
            pendingOpenLiveCall = true
        }
    }

    private fun cacheCallInvitePayload(intent: Intent?) {
        if (intent == null) {
            return
        }
        val payload = intent.getStringExtra(FLUTTER_NOTIFICATION_PAYLOAD)
            ?.trim()
            .orEmpty()
        if (!payload.startsWith(CALL_INVITE_PREFIX) &&
            !payload.startsWith(CALL_DECLINED_PREFIX)
        ) {
            return
        }
        val actionId = intent.getStringExtra(FLUTTER_NOTIFICATION_ACTION_ID)
            ?.trim()
            .orEmpty()
        val normalizedPayload = if (payload.startsWith(CALL_DECLINED_PREFIX)) {
            payload
        } else if (actionId == CALL_DECLINE_ACTION_ID) {
            "$CALL_DECLINED_PREFIX${payload.removePrefix(CALL_INVITE_PREFIX)}"
        } else {
            payload
        }
        if (normalizedPayload in consumedCallInvitePayloads) {
            return
        }
        pendingCallInvitePayload = normalizedPayload
    }

    companion object {
        private const val TAG = "FlickoMainActivity"
        private const val DEFAULT_SIM_SLOT = 0
        const val FLUSH_RESULT_DELAY_MS = 1150L
        const val FLUTTER_NOTIFICATION_PAYLOAD = "payload"
        const val FLUTTER_NOTIFICATION_ACTION_ID = "actionId"
        const val CALL_INVITE_PREFIX = "call-invite:"
        const val CALL_DECLINED_PREFIX = "call-invite-declined:"
        const val CALL_DECLINE_ACTION_ID = "flicko_call_decline"
        const val OPEN_LIVE_CALL_EXTRA = "openLiveCall"
    }
}
