package com.flicko.health.flicko_health

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

object FlickoCallEventBus : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var latestEvent: Map<String, Any?> = emptyMap()
    private val transcriptBuffer = mutableListOf<Map<String, Any?>>()
    private var preferences: SharedPreferences? = null

    fun init(context: Context) {
        preferences = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (transcriptBuffer.isEmpty()) {
            transcriptBuffer.addAll(readPersistedTranscript())
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (latestEvent.isNotEmpty()) {
            events?.success(latestEvent)
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(
        phase: String,
        message: String,
        connected: Boolean,
        micEnabled: Boolean,
        speakerEnabled: Boolean,
        isSpeaking: Boolean,
        openingReady: Boolean,
        error: String? = null,
    ) {
        val event = mapOf(
            "type" to "state",
            "phase" to phase,
            "message" to message,
            "connected" to connected,
            "micEnabled" to micEnabled,
            "speakerEnabled" to speakerEnabled,
            "isSpeaking" to isSpeaking,
            "openingReady" to openingReady,
            "error" to error,
            "timestamp" to System.currentTimeMillis(),
        )
        latestEvent = event
        send(event)
    }

    fun emitTranscript(
        role: String,
        text: String,
        isFinal: Boolean = true,
        source: String = "",
    ) {
        val cleanText = text.trim()
        if (cleanText.isEmpty()) {
            return
        }
        val event = mapOf(
            "type" to "transcript",
            "role" to role,
            "text" to cleanText,
            "isFinal" to isFinal,
            "source" to source,
            "createdAt" to System.currentTimeMillis(),
        )
        synchronized(transcriptBuffer) {
            transcriptBuffer.add(event)
            while (transcriptBuffer.size > MAX_TRANSCRIPT_ENTRIES) {
                transcriptBuffer.removeAt(0)
            }
            persistTranscriptLocked()
        }
        send(event)
    }

    fun clearTranscript() {
        synchronized(transcriptBuffer) {
            transcriptBuffer.clear()
            persistTranscriptLocked()
        }
    }

    fun snapshotTranscript(): List<Map<String, Any?>> {
        synchronized(transcriptBuffer) {
            if (transcriptBuffer.isEmpty()) {
                transcriptBuffer.addAll(readPersistedTranscript())
            }
            return transcriptBuffer.toList()
        }
    }

    private fun send(event: Map<String, Any?>) {
        mainHandler.post {
            sink?.success(event)
        }
    }

    private fun persistTranscriptLocked() {
        val prefs = preferences ?: return
        val array = JSONArray()
        transcriptBuffer.forEach { entry ->
            array.put(JSONObject().apply {
                entry.forEach { (key, value) ->
                    put(key, value ?: JSONObject.NULL)
                }
            })
        }
        prefs.edit().putString(PREF_TRANSCRIPT_KEY, array.toString()).apply()
    }

    private fun readPersistedTranscript(): List<Map<String, Any?>> {
        val raw = preferences?.getString(PREF_TRANSCRIPT_KEY, null)
            ?.takeIf { it.isNotBlank() }
            ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val map = mutableMapOf<String, Any?>()
                    val keys = item.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val value = item.opt(key)
                        map[key] = if (value == JSONObject.NULL) null else value
                    }
                    if (map["text"]?.toString()?.trim()?.isNotEmpty() == true) {
                        add(map)
                    }
                }
            }.takeLast(MAX_TRANSCRIPT_ENTRIES)
        } catch (_: Exception) {
            emptyList()
        }
    }

    private const val PREFS_NAME = "flicko_live_call_transcript"
    private const val PREF_TRANSCRIPT_KEY = "latest_transcript"
    private const val MAX_TRANSCRIPT_ENTRIES = 500
}
