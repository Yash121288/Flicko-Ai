package com.flicko.health.flicko_health

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject

class FlickoCallForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null

    private val liveRunning = AtomicBoolean(false)
    private val micEnabled = AtomicBoolean(true)
    private val speakerEnabled = AtomicBoolean(true)
    private val modelSpeaking = AtomicBoolean(false)

    private var okHttpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var audioTrackStarted = false
    private var micThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var flushStopPending = false
    private var callStartedAtMs = 0L
    private val speakingSilenceRunnable = Runnable {
        if (liveRunning.get() && modelSpeaking.compareAndSet(true, false)) {
            val message = if (micEnabled.get()) "Listening" else "Microphone muted"
            publishCallState(
                phase = if (micEnabled.get()) "listening" else "muted",
                message = message,
                connected = true,
            )
        }
    }
    private val firstAudioNudgeRunnable = Runnable {
        if (liveRunning.get() && !firstAudioReceived.get()) {
            Log.w(TAG, "Gemini Live connected but no first audio yet; sending concise nudge")
            sendConciseAudioNudge()
        }
    }
    private val firstAudioFallbackRunnable = Runnable {
        if (liveRunning.get() && !firstAudioReceived.get()) {
            val raw = "Gemini Live produced no first audio for ${currentLiveModel}"
            if (!retryLiveSessionIfModelUnavailable(raw)) {
                updateNotification("Waiting for live voice")
                publishCallState(
                    phase = "listening",
                    message = "Waiting for live voice",
                    connected = true,
                    error = raw,
                )
            }
        }
    }
    private val flushStopRunnable = Runnable {
        flushStopPending = false
        stopCallService()
    }
    private val openingBufferLock = Any()

    private var currentTitle = "Call in progress"
    private var currentSubtitle = ""
    private var currentProblemName = "health"
    private var currentProfileContext = ""
    private var currentOpeningScript = ""
    private var currentApiKey = ""
    private var currentLiveModel = ""
    private var currentVoiceName = "Kore"
    private var currentBaseUri = DEFAULT_GEMINI_LIVE_WS_URL
    private val triedLiveModels = mutableSetOf<String>()
    private val firstAudioReceived = AtomicBoolean(false)
    private val openingReady = AtomicBoolean(false)
    private val deferFirstPlayback = AtomicBoolean(false)
    private val deferredPlaybackReleased = AtomicBoolean(false)
    private val bufferedOpeningAudio = mutableListOf<ByteArray>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopCallService()
            ACTION_FLUSH_AND_STOP -> flushAndStopCallService()
            ACTION_SET_MIC -> setMicrophoneEnabled(intent.getBooleanExtra(EXTRA_ENABLED, true))
            ACTION_SET_SPEAKER -> setSpeakerEnabled(intent.getBooleanExtra(EXTRA_ENABLED, true))
            ACTION_SEND_TEXT_TURN -> sendTextTurn(intent.getStringExtra(EXTRA_TEXT).orEmpty())
            ACTION_RELEASE_DEFERRED_PLAYBACK -> releaseDeferredPlayback()
            else -> startCallService(intent)
        }
        return START_STICKY
    }

    private fun startCallService(intent: Intent?) {
        if (serviceRunning) {
            return
        }
        serviceRunning = true
        mainHandler.removeCallbacks(flushStopRunnable)
        mainHandler.removeCallbacks(speakingSilenceRunnable)
        flushStopPending = false
        callStartedAtMs = System.currentTimeMillis()
        modelSpeaking.set(false)
        FlickoCallEventBus.init(applicationContext)
        currentTitle = intent?.getStringExtra(EXTRA_TITLE) ?: "Call in progress"
        currentSubtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: ""
        currentProblemName = intent?.getStringExtra(EXTRA_PROBLEM_NAME) ?: "health"
        currentProfileContext = intent?.getStringExtra(EXTRA_PROFILE_CONTEXT) ?: ""
        currentOpeningScript = intent?.getStringExtra(EXTRA_OPENING_SCRIPT)?.trim().orEmpty()
        deferFirstPlayback.set(intent?.getBooleanExtra(EXTRA_DEFER_FIRST_PLAYBACK, false) == true)
        deferredPlaybackReleased.set(!deferFirstPlayback.get())
        openingReady.set(false)
        synchronized(openingBufferLock) {
            bufferedOpeningAudio.clear()
        }
        FlickoCallEventBus.clearTranscript()

        ensureNotificationChannel()
        acquireWakeLock()
        configureAudioRoute()

        val notification = buildNotification(currentTitle, currentSubtitle)
        val microphoneForegroundActive = startForegroundForCall(
            notification = notification,
            includeMicrophone = hasMicrophonePermission(),
        )
        if (!microphoneForegroundActive) {
            updateNotification("Microphone permission needed")
            publishCallState(
                phase = "error",
                message = "Microphone permission needed",
                connected = false,
                error = "Microphone permission is not available for the foreground call service",
            )
            mainHandler.postDelayed({ stopCallService() }, MICROPHONE_ERROR_STOP_DELAY_MS)
            return
        }
        publishCallState("connecting", currentSubtitle, connected = false)

        currentApiKey = intent?.getStringExtra(EXTRA_API_KEY)?.trim().orEmpty()
        currentLiveModel = intent?.getStringExtra(EXTRA_MODEL)?.trim().orEmpty()
        currentVoiceName = intent?.getStringExtra(EXTRA_VOICE_NAME)?.trim()
            ?.ifEmpty { "Kore" } ?: "Kore"
        currentBaseUri = intent?.getStringExtra(EXTRA_BASE_URI)?.trim()
            ?.ifEmpty { DEFAULT_GEMINI_LIVE_WS_URL } ?: DEFAULT_GEMINI_LIVE_WS_URL
        triedLiveModels.clear()
        if (currentApiKey.isNotEmpty() && currentLiveModel.isNotEmpty()) {
            startNativeLiveSession(
                apiKey = currentApiKey,
                model = currentLiveModel,
                voiceName = currentVoiceName,
                baseUri = currentBaseUri,
            )
        } else {
            updateNotification("Voice setup missing")
            publishCallState(
                phase = "error",
                message = "Voice setup missing",
                connected = false,
                error = "Missing Gemini Live configuration",
            )
        }
    }

    private fun startNativeLiveSession(
        apiKey: String,
        model: String,
        voiceName: String,
        baseUri: String,
    ) {
        if (liveRunning.getAndSet(true)) {
            return
        }
        currentLiveModel = model.removePrefix("models/")
        currentVoiceName = voiceName.ifBlank { "Kore" }
        currentBaseUri = baseUri.ifBlank { DEFAULT_GEMINI_LIVE_WS_URL }
        triedLiveModels.add(currentLiveModel)
        firstAudioReceived.set(false)
        openingReady.set(false)
        if (!deferFirstPlayback.get()) {
            deferredPlaybackReleased.set(true)
        }
        synchronized(openingBufferLock) {
            bufferedOpeningAudio.clear()
        }
        mainHandler.removeCallbacks(firstAudioNudgeRunnable)
        mainHandler.removeCallbacks(firstAudioFallbackRunnable)
        if (!hasMicrophonePermission()) {
            liveRunning.set(false)
            updateNotification("Microphone permission needed")
            publishCallState(
                phase = "error",
                message = "Microphone permission needed",
                connected = false,
                error = "Microphone permission is not granted",
            )
            return
        }

        try {
            openPlayback()
            val client = OkHttpClient.Builder()
                .pingInterval(20, TimeUnit.SECONDS)
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
            okHttpClient = client

            val url = webSocketBaseToHttpUrl(baseUri).toHttpUrl()
                .newBuilder()
                .addQueryParameter("key", apiKey)
                .build()
                .toString()
            val request = Request.Builder().url(url).build()
            webSocket = client.newWebSocket(
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        Log.i(TAG, "Gemini Live native socket opened")
                        updateNotification("Connecting live voice")
                        publishCallState("connecting", "Connecting live voice", connected = false)
                        sendSetup(webSocket, model, voiceName)
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        handleLiveMessage(text)
                    }

                    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                        handleLiveMessage(bytes.utf8())
                    }

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) {
                        Log.e(TAG, "Gemini Live native socket failed", t)
                        val rawError = listOfNotNull(
                            t.message,
                            t.javaClass.simpleName,
                            response?.code?.toString(),
                            response?.message,
                        ).joinToString(" ")
                        if (retryLiveSessionIfModelUnavailable(rawError)) {
                            return
                        }
                        val message = friendlyNativeError(rawError)
                        updateNotification(message)
                        publishCallState(
                            phase = "error",
                            message = message,
                            connected = false,
                            error = rawError,
                        )
                        stopNativeLiveSession(closeSocket = false)
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        Log.i(TAG, "Gemini Live native socket closed: $code $reason")
                        if (!liveRunning.get()) {
                            return
                        }
                        if (retryLiveSessionIfModelUnavailable("$code $reason")) {
                            return
                        }
                        publishCallState(
                            phase = "disconnected",
                            message = "Live voice disconnected",
                            connected = false,
                        )
                        stopNativeLiveSession(closeSocket = false)
                    }
                },
            )
        } catch (error: Exception) {
            Log.e(TAG, "Native live session could not start", error)
            val message = friendlyNativeError(error.message ?: error.javaClass.simpleName)
            updateNotification(message)
            publishCallState(
                phase = "error",
                message = message,
                connected = false,
                error = error.message ?: error.javaClass.simpleName,
            )
            stopNativeLiveSession()
        }
    }

    private fun sendSetup(socket: WebSocket, model: String, voiceName: String) {
        val normalizedModel = if (model.startsWith("models/")) model else "models/$model"
        val setup = JSONObject()
            .put(
                "setup",
                JSONObject()
                    .put("model", normalizedModel)
                    .put(
                        "generationConfig",
                        JSONObject()
                            .put("responseModalities", JSONArray().put("AUDIO"))
                            .put("temperature", 0.92)
                            .put("enableAffectiveDialog", true)
                            .put(
                                "speechConfig",
                                JSONObject().put(
                                    "voiceConfig",
                                    JSONObject().put(
                                        "prebuiltVoiceConfig",
                                        JSONObject().put("voiceName", voiceName),
                                    ),
                                ),
                            ),
                    )
                    .put(
                        "systemInstruction",
                        JSONObject().put(
                            "parts",
                            JSONArray().put(JSONObject().put("text", buildSystemPrompt())),
                        ),
                    )
                    .put("inputAudioTranscription", JSONObject())
                    .put("outputAudioTranscription", JSONObject()),
            )
        socket.send(setup.toString())
    }

    private fun handleLiveMessage(raw: String) {
        if (!liveRunning.get() || raw.isBlank()) {
            return
        }
        try {
            val json = JSONObject(raw)
            if (json.has("setupComplete")) {
                updateNotification("Live voice connected")
                publishCallState("listening", "Live voice connected", connected = true)
                sendInitialGreeting()
                mainHandler.postDelayed(firstAudioNudgeRunnable, FIRST_AUDIO_NUDGE_TIMEOUT_MS)
                mainHandler.postDelayed(firstAudioFallbackRunnable, FIRST_AUDIO_FALLBACK_TIMEOUT_MS)
                if (!deferFirstPlayback.get()) {
                    startMicrophoneLoop()
                }
            }

            json.optJSONObject("serverContent")?.let { serverContent ->
                handleServerContent(serverContent)
                handleTranscription(serverContent)
            }

            json.optJSONObject("error")?.let { error ->
                val message = error.optString("message", "Live voice error")
                Log.e(TAG, "Gemini Live native error: $message")
                if (retryLiveSessionIfModelUnavailable(message)) {
                    return
                }
                val friendlyMessage = friendlyNativeError(message)
                updateNotification(friendlyMessage)
                publishCallState(
                    phase = "error",
                    message = friendlyMessage,
                    connected = false,
                    error = message,
                )
                stopNativeLiveSession(closeSocket = true)
            }
        } catch (error: Exception) {
            Log.w(TAG, "Non JSON Gemini Live message ignored", error)
        }
    }

    private fun retryLiveSessionIfModelUnavailable(raw: String): Boolean {
        if (!isModelAccessError(raw)) {
            return false
        }
        val fallback = nextFallbackLiveModel() ?: return false
        Log.w(TAG, "Retrying Gemini Live with fallback model $fallback after: $raw")
        updateNotification("Retrying live voice")
        publishCallState(
            phase = "connecting",
            message = "Retrying live voice",
            connected = false,
        )
        stopNativeLiveSession(closeSocket = true)
        startNativeLiveSession(
            apiKey = currentApiKey,
            model = fallback,
            voiceName = currentVoiceName,
            baseUri = currentBaseUri,
        )
        return true
    }

    private fun isModelAccessError(raw: String): Boolean {
        val text = raw.lowercase()
        return "model" in text ||
            "not found" in text ||
            "404" in text ||
            "1007" in text ||
            "1008" in text ||
            "invalid argument" in text ||
            "unsupported" in text ||
            "unavailable" in text
    }

    private fun nextFallbackLiveModel(): String? {
        val normalizedCurrent = currentLiveModel.removePrefix("models/")
        val candidates = listOf(
            "gemini-2.5-flash-native-audio-latest",
            "gemini-2.5-flash-native-audio-preview-09-2025",
        )
        return candidates.firstOrNull { candidate ->
            candidate != normalizedCurrent && !triedLiveModels.contains(candidate)
        }
    }

    private fun handleServerContent(serverContent: JSONObject) {
        val modelTurn = serverContent.optJSONObject("modelTurn")
        val parts = modelTurn?.optJSONArray("parts")
        var playedAudio = false
        var bufferedAudio = false

        if (parts != null) {
            for (index in 0 until parts.length()) {
                val part = parts.optJSONObject(index) ?: continue
                val inlineData = part.optJSONObject("inlineData")
                    ?: part.optJSONObject("inline_data")
                    ?: continue
                val data = inlineData.optString("data")
                if (data.isNotBlank()) {
                    firstAudioReceived.set(true)
                    mainHandler.removeCallbacks(firstAudioNudgeRunnable)
                    mainHandler.removeCallbacks(firstAudioFallbackRunnable)
                    if (queueOrPlayAudio(data)) {
                        playedAudio = true
                    } else {
                        bufferedAudio = true
                    }
                }
            }
        }

        if (playedAudio) {
            modelSpeaking.set(true)
            scheduleSpeakingSilenceWatchdog()
            publishCallState("speaking", "AI is speaking", connected = true)
        } else if (bufferedAudio) {
            openingReady.set(true)
            publishCallState(
                phase = "connecting",
                message = "Opening voice ready",
                connected = true,
            )
        }

        if (
            serverContent.optBoolean("turnComplete", false) ||
            serverContent.optBoolean("generationComplete", false)
        ) {
            markModelTurnComplete()
        }
    }

    private fun webSocketBaseToHttpUrl(value: String): String {
        val trimmed = value.trim().ifBlank { DEFAULT_GEMINI_LIVE_WS_URL }
        return when {
            trimmed.startsWith("wss://", ignoreCase = true) ->
                "https://${trimmed.substringAfter("://")}"
            trimmed.startsWith("ws://", ignoreCase = true) ->
                "http://${trimmed.substringAfter("://")}"
            else -> trimmed
        }
    }

    private fun scheduleSpeakingSilenceWatchdog() {
        mainHandler.removeCallbacks(speakingSilenceRunnable)
        mainHandler.postDelayed(speakingSilenceRunnable, SPEAKING_SILENCE_TIMEOUT_MS)
    }

    private fun markModelTurnComplete() {
        mainHandler.removeCallbacks(speakingSilenceRunnable)
        modelSpeaking.set(false)
        val message = if (micEnabled.get()) "Listening" else "Microphone muted"
        publishCallState(
            phase = if (micEnabled.get()) "listening" else "muted",
            message = message,
            connected = true,
        )
    }

    private fun handleTranscription(serverContent: JSONObject) {
        val inputText = (
            serverContent.optJSONObject("inputTranscription")
                ?: serverContent.optJSONObject("input_transcription")
            )?.optString("text", "").orEmpty()
        if (inputText.isNotBlank()) {
            FlickoCallEventBus.emitTranscript(
                role = "user",
                text = inputText,
                source = "gemini_live_input_audio_transcription",
            )
        }

        val outputText = (
            serverContent.optJSONObject("outputTranscription")
                ?: serverContent.optJSONObject("output_transcription")
            )?.optString("text", "").orEmpty()
        if (outputText.isNotBlank()) {
            FlickoCallEventBus.emitTranscript(
                role = "assistant",
                text = outputText,
                source = "gemini_live_output_audio_transcription",
            )
        }
    }

    private fun sendInitialGreeting() {
        val scriptedOpening = currentOpeningScript.trim()
        val text = if (scriptedOpening.isNotEmpty()) {
            """
Speak the following exact opening naturally in a warm human Hindi or Hinglish health-coach voice.
Do not add a new greeting before it.
After speaking it once, stop and wait for the user response.

$scriptedOpening
""".trimIndent()
        } else {
            initialGreetingInstruction()
        }

        val payload = JSONObject()
            .put(
                "clientContent",
                JSONObject()
                    .put(
                        "turns",
                        JSONArray().put(
                            JSONObject()
                                .put("role", "user")
                                .put(
                                    "parts",
                                    JSONArray().put(JSONObject().put("text", text)),
                                ),
                        ),
                    )
                    .put("turnComplete", true),
            )
        sendJson(payload)
    }

    private fun sendTextTurn(text: String) {
        val cleanText = text.trim()
        if (cleanText.isEmpty() || !liveRunning.get()) {
            return
        }
        val payload = JSONObject()
            .put(
                "clientContent",
                JSONObject()
                    .put(
                        "turns",
                        JSONArray().put(
                            JSONObject()
                                .put("role", "user")
                                .put(
                                    "parts",
                                    JSONArray().put(JSONObject().put("text", cleanText)),
                                ),
                        ),
                    )
                    .put("turnComplete", true),
            )
        sendJson(payload)
    }

    @SuppressLint("MissingPermission")
    private fun startMicrophoneLoop() {
        if (micThread?.isAlive == true || !hasMicrophonePermission()) {
            return
        }
        val minBufferSize = AudioRecord.getMinBufferSize(
            INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(3200)

        val recorder = createAudioRecord(minBufferSize)
        if (recorder == null) {
            updateNotification("Microphone could not start")
            publishCallState(
                phase = "error",
                message = "Microphone could not start",
                connected = false,
                error = "AudioRecord could not initialize with voice or mic source",
            )
            return
        }
        audioRecord = recorder
        try {
            recorder.startRecording()
        } catch (error: Exception) {
            Log.e(TAG, "Microphone recording could not start", error)
            recorder.release()
            audioRecord = null
            updateNotification("Microphone could not start")
            publishCallState(
                phase = "error",
                message = "Microphone could not start",
                connected = false,
                error = error.message ?: error.javaClass.simpleName,
            )
            return
        }
        if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            Log.e(TAG, "Microphone AudioRecord did not enter recording state")
            recorder.release()
            audioRecord = null
            updateNotification("Microphone could not start")
            publishCallState(
                phase = "error",
                message = "Microphone could not start",
                connected = false,
                error = "AudioRecord recording state ${recorder.recordingState}",
            )
            return
        }
        publishCallState("listening", "Listening", connected = true)

        micThread = Thread {
            val buffer = ByteArray(minBufferSize)
            while (liveRunning.get()) {
                val read = try {
                    recorder.read(buffer, 0, buffer.size)
                } catch (error: Exception) {
                    Log.e(TAG, "Microphone read failed", error)
                    break
                }
                if (
                    read > 0 &&
                    micEnabled.get() &&
                    !modelSpeaking.get() &&
                    webSocket != null
                ) {
                    val chunk = if (read == buffer.size) buffer else buffer.copyOf(read)
                    sendAudioChunk(chunk)
                }
            }
        }.apply {
            name = "FlickoGeminiMicLoop"
            isDaemon = true
            start()
        }
    }

    @SuppressLint("MissingPermission")
    private fun createAudioRecord(bufferSize: Int): AudioRecord? {
        val sources = listOf(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            MediaRecorder.AudioSource.MIC,
        )
        for (source in sources) {
            val recorder = try {
                AudioRecord(
                    source,
                    INPUT_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize * 2,
                )
            } catch (error: Exception) {
                Log.w(TAG, "AudioRecord source $source could not be created", error)
                null
            } ?: continue
            if (recorder.state == AudioRecord.STATE_INITIALIZED) {
                return recorder
            }
            Log.w(TAG, "AudioRecord source $source was not initialized")
            try {
                recorder.release()
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun sendAudioChunk(chunk: ByteArray) {
        val encoded = Base64.encodeToString(chunk, Base64.NO_WRAP)
        val payload = JSONObject()
            .put(
                "realtimeInput",
                JSONObject().put(
                    "audio",
                    JSONObject()
                        .put("mimeType", "audio/pcm;rate=$INPUT_SAMPLE_RATE")
                        .put("data", encoded),
                ),
            )
        sendJson(payload)
    }

    private fun hasCompletedIntakeContext(): Boolean {
        val context = currentProfileContext.lowercase()
        return listOf(
            "intake status: complete",
            "latest intake summary:",
            "saved ai call memory:",
            "last ai voice call completed:",
            "saved reports:",
        ).any { marker -> marker in context }
    }

    private fun firstPromptListItem(label: String): String {
        val lines = currentProfileContext.lines()
        val normalizedLabel = "${label.trim().lowercase()}:"
        for (index in lines.indices) {
            val current = lines[index].trim().lowercase()
            if (current != normalizedLabel) {
                continue
            }
            for (cursor in index + 1 until lines.size) {
                val candidate = lines[cursor].trim()
                if (candidate.isBlank()) {
                    continue
                }
                if (!candidate.startsWith("- ")) {
                    break
                }
                val value = candidate.removePrefix("- ").trim()
                if (value.isNotEmpty()) {
                    return value
                }
            }
        }
        return ""
    }

    private fun defaultFirstIntakeQuestion(): String {
        val normalizedProblem = currentProblemName.lowercase()
        return when {
            "diabetes" in normalizedProblem ->
                "Sabse pehle mujhe bataiye, aapka sugar issue kis type ka hai aur aaj kal fasting ya random reading kitni aa rahi hai?"
            "blood pressure" in normalizedProblem || "heart" in normalizedProblem ->
                "Sabse pehle bataiye, blood pressure ya heart problem kab se hai aur recent BP reading ya symptom kya chal raha hai?"
            "weight" in normalizedProblem ->
                "Sabse pehle bataiye, weight concern me abhi sabse badi dikkat kya hai aur pichhle do hafton me weight badha, ghata, ya same raha?"
            "thyroid" in normalizedProblem ->
                "Sabse pehle bataiye, thyroid issue kab se hai aur abhi kaunsi medicine kis time le rahe hain?"
            "pcos" in normalizedProblem || "pcod" in normalizedProblem || "hormone" in normalizedProblem ->
                "Sabse pehle bataiye, cycle ya hormone issue me abhi sabse zyada problem kya chal rahi hai aur ye kab se hai?"
            "pregnan" in normalizedProblem ->
                "Sabse pehle bataiye, pregnancy ka kaunsa month ya week chal raha hai aur abhi koi symptom ya concern kya hai?"
            "sleep" in normalizedProblem ->
                "Sabse pehle bataiye, neend ki dikkat kya hai aur sone me problem, beech me uthna, ya subah thakan me se kya zyada ho raha hai?"
            "stress" in normalizedProblem || "mood" in normalizedProblem ->
                "Sabse pehle bataiye, stress ya mood me abhi sabse badi dikkat kya hai aur ye pichhle kitne dino se chal rahi hai?"
            "sexual" in normalizedProblem ->
                "Sabse pehle bataiye, sexual health concern me abhi exact problem kya hai aur ye kab se chal rahi hai?"
            else ->
                "Sabse pehle bataiye, $currentProblemName ko lekar abhi sabse badi dikkat kya hai aur ye kab se chal rahi hai?"
        }
    }

    private fun suggestedFirstIntakeQuestion(): String {
        val directQuestion = firstPromptListItem("Next best intake questions")
        if (directQuestion.isNotEmpty()) {
            return directQuestion
        }
        val localQuestion = firstPromptListItem("Local next best intake questions")
        if (localQuestion.isNotEmpty()) {
            return localQuestion
        }
        return defaultFirstIntakeQuestion()
    }

    private fun initialGreetingInstruction(): String {
        val userName = contextValue("User name").ifBlank { "user" }
        val timeHint = contextValue("Time-of-day opening hint").ifBlank { localTimeHint() }
        val seed = contextValue("Dynamic greeting seed").ifBlank { System.currentTimeMillis().toString() }
        val returning = hasCompletedIntakeContext()
        val mode = if (returning) "returning follow-up call" else "first intake call"
        val suggestedQuestion = suggestedFirstIntakeQuestion()
        val scheduledReminderHint = contextValue("Scheduled daily reminders")
        val recentOpenings = contextValue("Recent AI call openings to avoid")
        val openingStyle = openingStyleHint(seed)
        val callSource = contextValue("Call initiation source").ifBlank { "unknown" }
        val callPurpose = contextValue("Call purpose/work name").ifBlank { "health call" }

        return """
Generate the first spoken turn for this $mode.

Context to use:
- User name: $userName
- Time hint: $timeHint
- Care focus: $currentProblemName
- Call initiation source: $callSource
- Call purpose/work name: $callPurpose
- Variation seed: $seed
- Opening style hint: $openingStyle
- Scheduled reminder hint: ${if (scheduledReminderHint.isBlank()) "none" else scheduledReminderHint}
- Recent openings to avoid: ${if (recentOpenings.isBlank()) "none" else recentOpenings}
- Known user context is already available in the system prompt.

Hard rules:
- Do not say "Hello Flick", "Hello Flicko", or repeat a fixed canned greeting.
- Do not copy a previous opening from Known user context or transcript memory.
- Do not use the same sentence structure as the previous call.
- Follow the opening style hint so the first line feels different from recent calls.
- The first sentence must sound materially different from anything listed in Recent openings to avoid.
- Mention the user's name naturally if it is available and not "user".
- Mention one real context item if available: last call, missed reminder, care task, report, recent chat, recent glucose/meal/log, or notification memory.
- Keep it human, warm, local Hindi/Hinglish as appropriate, and under 14 seconds of speech.
- Ask exactly one useful next question.
- If call initiation source is user_started, the user opened the call. A warm line like "Ohh $userName, aaj mujhe yaad kiya?" is allowed, then ask what help they need.
- If call initiation source is flicko_started, Flicko started the call. Do not say the user remembered or called you. State the call purpose/work name naturally before the question.
- If this is a returning call, use one short natural continuity or greeting line, then ask whether the current reminder, task, or plan went properly and whether any new problem happened.
- Friendly familiarity is allowed for returning users when context supports it, for example light continuity like remembering the user or their plan, but never reuse one playful phrase every call.
- If scheduled reminder hint is present, naturally acknowledge that you are calling at the agreed reminder time and that you want a quick full-day review or summary. Vary the wording every call. Do not use one canned sentence repeatedly.
- Avoid these exact repeated patterns: "main aaj ka quick care check-in lene ke liye call kar rahi hoon", "main aapke fixed check-in time par call kar rahi hoon", "main care task follow-up ke liye call kar rahi hoon".
- If this is a returning call, ask reminder timing details only if the user says the reminder failed, felt inconvenient, was missed, or they want it changed.
- If Known user context already contains a confirmed reminder time or an answered detail, do not ask for that same detail again unless the earlier answer is incomplete, conflicting, or the user wants a change.
- If the user gives a reminder or call time, repeat the exact time with AM/PM. Never round it or guess morning/evening. If the user says an ambiguous hour like "9 baje", ask one short clarification question before confirming it.
- After the user gives one clear detail, do not ask the same thing again in different words.
- If this is the first intake, do not open with social small talk like "kaise ho", "kya haalchal hai", "kya chal raha hai", or any generic wellness greeting.
- If this is the first intake, the first sentence must directly state the reason for the call or care focus.
- If this is the first intake, the second sentence must be the actual intake question. Do not waste the first turn on pleasantries.

Suggested first intake question:
- $suggestedQuestion

If this is a returning call, continue from memory, ask first whether the current reminder or plan worked properly, then ask what changed today only if needed.
If this is the first intake, lead the intake confidently and ask the most relevant first condition-specific question. Stay close to the suggested first intake question unless safety context requires a more urgent opening.
""".trimIndent()
    }

    private fun openingStyleHint(seed: String): String {
        val styles = listOf(
            "continuity-led",
            "reminder-led",
            "progress-led",
            "catch-up-led",
            "support-led",
            "memory-led",
            "friendly-led",
        )
        var hash = 0
        for (unit in seed) {
            hash = (hash * 31 + unit.code) and 0x3fffffff
        }
        return styles[hash % styles.size]
    }

    private fun sendConciseAudioNudge() {
        val text = """
The live call is connected but no audible first response has arrived yet.
Immediately generate a fresh, short spoken opening from the current context.
If this is a first intake call, skip generic greetings and ask the first condition-specific intake question directly.
Use the user's name if present, mention one real memory/notification/task only if it helps, and ask one next question.
Suggested first intake question: ${suggestedFirstIntakeQuestion()}
Variation seed: ${System.currentTimeMillis()}
""".trimIndent()
        val payload = JSONObject()
            .put(
                "clientContent",
                JSONObject()
                    .put(
                        "turns",
                        JSONArray().put(
                            JSONObject()
                                .put("role", "user")
                                .put(
                                    "parts",
                                    JSONArray().put(JSONObject().put("text", text)),
                                ),
                        ),
                    )
                    .put("turnComplete", true),
            )
        sendJson(payload)
    }

    private fun sendAudioStreamEnd() {
        val payload = JSONObject()
            .put(
                "realtimeInput",
                JSONObject().put("audioStreamEnd", true),
            )
        sendJson(payload)
    }

    private fun sendJson(payload: JSONObject) {
        if (!liveRunning.get()) {
            return
        }
        webSocket?.send(payload.toString())
    }

    @Suppress("DEPRECATION")
    private fun openPlayback() {
        if (audioTrack != null) {
            return
        }
        val bufferSize = AudioTrack.getMinBufferSize(
            OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(4096)

        audioTrack = AudioTrack(
            AudioManager.STREAM_MUSIC,
            OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize * 4,
            AudioTrack.MODE_STREAM,
        ).apply {
            setPlaybackVolume()
        }
        audioTrackStarted = false
    }

    private fun queueOrPlayAudio(base64Audio: String): Boolean {
        val bytes = try {
            Base64.decode(base64Audio, Base64.DEFAULT)
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "Invalid Gemini audio payload", error)
            return false
        }
        if (bytes.isEmpty()) {
            return false
        }
        if (deferFirstPlayback.get() && !deferredPlaybackReleased.get()) {
            synchronized(openingBufferLock) {
                bufferedOpeningAudio.add(bytes)
            }
            return false
        }
        playAudioBytes(bytes)
        return true
    }

    private fun playAudioBytes(bytes: ByteArray) {
        if (!speakerEnabled.get()) {
            return
        }
        try {
            val track = audioTrack ?: return
            track.write(bytes, 0, bytes.size)
            if (!audioTrackStarted) {
                track.play()
                audioTrackStarted = true
            }
        } catch (error: Exception) {
            Log.e(TAG, "Native audio playback failed", error)
            updateNotification("Voice playback failed")
        }
    }

    private fun setMicrophoneEnabled(enabled: Boolean) {
        micEnabled.set(enabled)
        val message = if (enabled) "Microphone on" else "Microphone muted"
        publishCallState(
            phase = if (enabled) "listening" else "muted",
            message = message,
            connected = liveRunning.get(),
        )
    }

    private fun setSpeakerEnabled(enabled: Boolean) {
        speakerEnabled.set(enabled)
        configureSpeakerphone(enabled)
        audioTrack?.setPlaybackVolume()
        val message = if (enabled) "Speaker on" else "Speaker muted"
        publishCallState(
            phase = if (modelSpeaking.get()) "speaking" else if (micEnabled.get()) "listening" else "muted",
            message = message,
            connected = liveRunning.get(),
        )
    }

    private fun AudioTrack.setPlaybackVolume() {
        val volume = if (speakerEnabled.get()) 1.0f else 0.0f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            setVolume(volume)
        } else {
            @Suppress("DEPRECATION")
            setStereoVolume(volume, volume)
        }
    }

    private fun stopCallService() {
        mainHandler.removeCallbacks(flushStopRunnable)
        mainHandler.removeCallbacks(speakingSilenceRunnable)
        mainHandler.removeCallbacks(firstAudioNudgeRunnable)
        mainHandler.removeCallbacks(firstAudioFallbackRunnable)
        flushStopPending = false
        serviceRunning = false
        sendAudioStreamEnd()
        stopNativeLiveSession()
        publishCallState("disconnected", "Call ended", connected = false)
        releaseWakeLock()
        restoreAudioRoute()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun flushAndStopCallService() {
        if (flushStopPending) {
            return
        }
        flushStopPending = true
        sendAudioStreamEnd()
        updateNotification("Ending call")
        publishCallState(
            phase = if (liveRunning.get()) "listening" else "disconnected",
            message = "Saving final transcript",
            connected = liveRunning.get(),
        )
        mainHandler.postDelayed(flushStopRunnable, FLUSH_TRANSCRIPT_DELAY_MS)
    }

    private fun stopNativeLiveSession(closeSocket: Boolean = true) {
        liveRunning.set(false)
        modelSpeaking.set(false)
        serviceRunning = false
        openingReady.set(false)
        deferFirstPlayback.set(false)
        deferredPlaybackReleased.set(true)
        mainHandler.removeCallbacks(speakingSilenceRunnable)
        synchronized(openingBufferLock) {
            bufferedOpeningAudio.clear()
        }

        micThread?.interrupt()
        micThread = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null

        try {
            audioTrack?.stop()
        } catch (_: Exception) {
        }
        try {
            audioTrack?.release()
        } catch (_: Exception) {
        }
        audioTrack = null
        audioTrackStarted = false

        if (closeSocket) {
            try {
                webSocket?.close(1000, "Flicko call ended")
            } catch (_: Exception) {
            }
        }
        webSocket = null

        okHttpClient?.dispatcher?.executorService?.shutdown()
        okHttpClient?.connectionPool?.evictAll()
        okHttpClient = null
    }

    private fun buildNotification(title: String, subtitle: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.OPEN_LIVE_CALL_EXTRA, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val normalizedTitle = notificationTitle(title)
        val normalizedSubtitle = notificationSubtitle(subtitle)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(normalizedTitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setLocalOnly(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setContentIntent(pendingIntent)
        if (normalizedSubtitle.isNotBlank()) {
            builder.setContentText(normalizedSubtitle)
        }
        return builder.build()
    }

    private fun updateNotification(subtitle: String) {
        currentSubtitle = subtitle
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(currentTitle, subtitle))
    }

    private fun notificationSubtitle(raw: String): String {
        val lower = raw.lowercase()
        return when {
            "error" in lower ||
                "failed" in lower ||
                "missing" in lower ||
                "permission" in lower ||
                "disconnected" in lower -> raw
            else -> ""
        }
    }

    private fun releaseDeferredPlayback() {
        if (deferredPlaybackReleased.getAndSet(true)) {
            return
        }
        val buffered = synchronized(openingBufferLock) {
            bufferedOpeningAudio.toList().also { bufferedOpeningAudio.clear() }
        }
        openingReady.set(false)
        if (buffered.isNotEmpty()) {
            buffered.forEach(::playAudioBytes)
            modelSpeaking.set(true)
            scheduleSpeakingSilenceWatchdog()
            publishCallState("speaking", "AI is speaking", connected = true)
        } else {
            publishCallState(
                phase = if (micEnabled.get()) "listening" else "muted",
                message = if (micEnabled.get()) "Listening" else "Microphone muted",
                connected = liveRunning.get(),
            )
        }
        startMicrophoneLoop()
    }

    private fun notificationTitle(raw: String): String {
        val lower = raw.lowercase()
        return when {
            "error" in lower ||
                "failed" in lower ||
                "missing" in lower ||
                "permission" in lower -> "Call issue"
            else -> "Call in progress"
        }
    }

    private fun publishCallState(
        phase: String,
        message: String,
        connected: Boolean,
        error: String? = null,
    ) {
        FlickoCallEventBus.emit(
            phase = phase,
            message = message,
            connected = connected,
            micEnabled = micEnabled.get(),
            speakerEnabled = speakerEnabled.get(),
            isSpeaking = modelSpeaking.get(),
            openingReady = openingReady.get(),
            error = error,
        )
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background call service",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the ongoing call active while the app is in use"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundForCall(
        notification: Notification,
        includeMicrophone: Boolean,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification)
            return includeMicrophone
        }

        if (includeMicrophone) {
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
                return true
            } catch (error: Exception) {
                Log.e(TAG, "Could not start microphone foreground service", error)
            }
        }

        return try {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
            false
        } catch (error: Exception) {
            Log.e(TAG, "Could not start fallback media foreground service", error)
            serviceRunning = false
            stopSelf()
            false
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:FlickoLiveCall",
        ).apply {
            setReferenceCounted(false)
            acquire(60L * 60L * 1000L)
        }
    }

    private fun releaseWakeLock() {
        val currentWakeLock = wakeLock
        if (currentWakeLock?.isHeld == true) {
            currentWakeLock.release()
        }
        wakeLock = null
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun configureAudioRoute() {
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        configureSpeakerphone(speakerEnabled.get())
    }

    private fun configureSpeakerphone(enabled: Boolean) {
        audioManager?.isSpeakerphoneOn = enabled
    }

    private fun restoreAudioRoute() {
        audioManager?.isSpeakerphoneOn = false
        audioManager?.mode = AudioManager.MODE_NORMAL
        audioManager = null
    }

    private fun buildSystemPrompt(): String {
        val context = currentProfileContext.ifBlank { "The user profile is incomplete." }
        return """
You are Flicko AI Health Coach in a native Android foreground live voice call.

Care focus: $currentProblemName
Known user context:
$context

Speak like a warm, friendly, naturally conversational human Indian female health coach. Use local Hindi by default, match the user's language and tone, and keep replies short enough for real conversation. Sound caring and real, not polished like an ad, not stiff, and never mention Gemini, providers, API keys, models, sockets, or internal setup.

Dynamic personalization: Before speaking, use Known user context to infer user name, local time, previous call/chat memory, notification memory, reminders, missed tasks, mood, and last assistant wording. Every call opening must be newly generated. Never reuse the same first sentence, same greeting rhythm, or same summary structure consecutively. If the user name is available, use it naturally in the opening or first follow-up.

Call source rule: If Known user context says "Call initiation source: user_started", the user opened the call, so you may warmly say they remembered/called you today and then ask what help they need. If it says "Call initiation source: flicko_started", Flicko started the call, so never say the user remembered you; state the "Call purpose/work name" such as reminder, setup, meal photo, care task, or daily check-in.

Friendly familiarity: for returning users, you may occasionally sound like a known caring coach and lightly acknowledge continuity, but keep it respectful and do not recycle the same phrase on every call.

Memory-aware summary: Summaries must be generated from the current memory, not hardcoded. Include only real context found in Known user context: recent calls, recent chats, missed notifications, unfinished tasks, pending reminders, reports, uploaded files, health logs, and last app activity.

Conversation feel: Use empathy, light everyday acknowledgements, and one question at a time. Listen first, then guide. You may use short human acknowledgements like "haan", "achha", "theek", or "samajh gayi" when they fit, but do not overuse them.

Returning-user rule: If Known user context contains "Intake status: complete", "Latest intake summary", "Saved AI call memory", "Last AI voice call completed", "Saved reports", or any previous call/report memory, this is a returning-user call. Do NOT restart onboarding. Start with continuity: briefly mention that the previous setup or plan is already saved, then ask what changed today, what problem happened, what task/meal/medicine/sleep was missed, or what help is needed now. Use saved context to update dashboard values, reminders, care tasks, meal-photo follow-ups, missed-task recovery calls, and reports.
Returning call question order: For daily routine, reminder, or missed-task follow-up calls, first ask one broad check-in question about whether the reminder or plan worked and whether any new problem happened. Only after the user answers should you ask for schedule changes, reminder timing, blocker detail, medicine detail, or report detail.
Scheduled reminder opener: If Known user context shows a scheduled daily reminder, call window, proactive invite, or pending call reminder, naturally acknowledge that you are calling at the agreed reminder time and that you want a quick full-day review. Use fresh wording every call. Never repeat one canned sentence.

First-intake rule: Flicko leads the intake like a coach. Do not ask the user "what should I ask" or "what do you want me to do". Choose the next useful question from the selected condition, the local protocol context, condition intake questions, dashboard metrics, report blocks, food rules, and safety rules in Known user context.

First-turn rule for first intake: Do not start with generic social greetings like "kaise ho", "kya haalchal hai", or "kya chal raha hai". Start directly with the care focus and the first intake question. The first spoken turn should be at most two short sentences.

Deep intake mode: Only if the context does NOT show completed intake, saved call memory, previous report, or last AI voice call, guide a 15-20 minute intake one question at a time. Ask condition-specific questions first: main concern, onset/duration, disease-specific symptoms or readings, current diagnosis, medicines, relevant lab/report values, routine, meals, sleep, stress, activity, family history, pregnancy/cycle if relevant, red flags, coaching tone, reminder timing, important tasks, and first 7-day goal.

Answered-detail rule: If the user already gave a specific answer such as time, symptom, blocker, medicine name, report status, duration, or reading, acknowledge it and move forward. Do not ask the same detail again unless the answer is incomplete, contradictory, or you need one precise missing value.

Medical report rule: During first intake, ask once whether the user has a recent lab, doctor, prescription, scan, or medical report related to $currentProblemName. If yes, explain that after the call they can open Chat and tap the upload/attachment button to upload a clear report photo or screenshot, so Flicko can save it into profile memory and future reports. If the user says no, accept it and do not ask again in the same intake.

Proactive follow-up: If the user misses meal photos, medicine, water, measurements, exercise, or sleep goals, first ask what difficulty happened. Ask which time Flicko should remind or call only if the user wants help, the current reminder did not work, or no schedule is confirmed yet. Repeat the schedule back clearly so it can be used for reminders, dashboard values, and weekly reports.

Reminder creation: Do not create reminders from guesses. Create a reminder only when the user clearly asks for one or agrees to one. When confirmed, include exactly one structured line in your response: "Reminder: HH:MM - short title/body". Do not repeat an existing reminder unless the user changes the time.
Reminder time precision: If the user gives a reminder time or call time, keep that exact time. Do not round it, shift it, convert it loosely, or guess morning versus evening. If the user says an ambiguous hour like "9 baje" without AM, PM, morning, evening, or night context, ask one short clarification question before creating or confirming the reminder.

Task memory: For missed tasks and meal photos, ask what blocked the task, ask the next realistic recovery time, and remember the answer as dashboard/task/report memory. Keep the spoken reply short; do not read raw memory aloud.

Busy handling: If the user says they are busy, says do not call now, says "baad me", "abhi nahi", or anything similar, stop the intake and ask: "Theek hai, main kis time call karun?" If they give a time, repeat it back. If they do not give a time, say Flicko will try again after 2-3 hours.

Call closing rule: When the call objective is complete, ask exactly once: "Aur koi question ya problem hai?" If the user says no, nahi, nahin, nothing, bas, no problem, no question, or bye, reply exactly: "Theek hai, chalo bye bye. Apna dhyan rakhna." Do not ask another question after that goodbye.

Safety: For emergency symptoms, tell the user to seek urgent medical care now. For medicine changes, pregnancy, insulin, steroids, severe symptoms, or abnormal vitals, ask them to confirm with a licensed clinician.
""".trimIndent()
    }

    private fun contextValue(label: String): String {
        val prefix = "$label:"
        return currentProfileContext
            .lineSequence()
            .map { it.trim() }
            .firstOrNull { it.startsWith(prefix, ignoreCase = true) }
            ?.substringAfter(":")
            ?.trim()
            .orEmpty()
    }

    private fun localTimeHint(): String {
        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        return when {
            hour < 5 -> "late night"
            hour < 12 -> "morning"
            hour < 17 -> "afternoon"
            hour < 21 -> "evening"
            else -> "night"
        }
    }

    private fun friendlyNativeError(raw: String): String {
        val text = raw.lowercase()
        return when {
            "api key" in text || "unauthorized" in text || "403" in text ->
                "Live voice needs valid Gemini Live access"
            "not found" in text || "404" in text || "model" in text ->
                "This live voice model is unavailable"
            "microphone" in text || "permission" in text ->
                "Microphone could not start"
            "network" in text || "socket" in text || "timeout" in text ->
                "Check internet for live voice"
            else -> "Live voice could not stay connected"
        }
    }

    override fun onDestroy() {
        serviceRunning = false
        stopNativeLiveSession()
        releaseWakeLock()
        restoreAudioRoute()
        super.onDestroy()
    }

    companion object {
        @JvmStatic
        @Volatile
        var serviceRunning: Boolean = false

        const val ACTION_START = "com.flicko.health.flicko_health.START_LIVE_CALL"
        const val ACTION_STOP = "com.flicko.health.flicko_health.STOP_LIVE_CALL"
        const val ACTION_FLUSH_AND_STOP = "com.flicko.health.flicko_health.FLUSH_AND_STOP_LIVE_CALL"
        const val ACTION_SET_MIC = "com.flicko.health.flicko_health.SET_LIVE_CALL_MIC"
        const val ACTION_SET_SPEAKER = "com.flicko.health.flicko_health.SET_LIVE_CALL_SPEAKER"
        const val ACTION_SEND_TEXT_TURN =
            "com.flicko.health.flicko_health.SEND_LIVE_CALL_TEXT_TURN"
        const val ACTION_RELEASE_DEFERRED_PLAYBACK =
            "com.flicko.health.flicko_health.RELEASE_LIVE_CALL_DEFERRED_PLAYBACK"

        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_API_KEY = "apiKey"
        const val EXTRA_MODEL = "model"
        const val EXTRA_VOICE_NAME = "voiceName"
        const val EXTRA_PROBLEM_NAME = "problemName"
        const val EXTRA_PROFILE_CONTEXT = "profileContext"
        const val EXTRA_OPENING_SCRIPT = "openingScript"
        const val EXTRA_DEFER_FIRST_PLAYBACK = "deferFirstPlayback"
        const val EXTRA_BASE_URI = "baseUri"
        const val EXTRA_ENABLED = "enabled"
        const val EXTRA_TEXT = "text"

        private const val DEFAULT_GEMINI_LIVE_WS_URL =
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
        private const val CHANNEL_ID = "flicko_live_health_call_v2"
        private const val NOTIFICATION_ID = 4198
        private const val FLUSH_TRANSCRIPT_DELAY_MS = 950L
        private const val MICROPHONE_ERROR_STOP_DELAY_MS = 900L
        private const val SPEAKING_SILENCE_TIMEOUT_MS = 1800L
        private const val FIRST_AUDIO_NUDGE_TIMEOUT_MS = 2500L
        private const val FIRST_AUDIO_FALLBACK_TIMEOUT_MS = 6500L
        private const val INPUT_SAMPLE_RATE = 16000
        private const val OUTPUT_SAMPLE_RATE = 24000
        private const val TAG = "FlickoLiveCall"
    }
}
