package com.jalvi.ai.jalvi_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * User-started, visible foreground microphone service.
 * Uses Android's installed speech recognition service as an experimental
 * keyword detector; it is not an offline/always-available hotword engine.
 */
class WakeWordService : Service(), TextToSpeech.OnInitListener {
    companion object {
        const val ACTION_START = "com.jalvi.ai.WAKE_START"
        const val ACTION_STOP = "com.jalvi.ai.WAKE_STOP"
        const val EXTRA_WAKE_COMMAND = "jalvi_wake_command"
        private const val CHANNEL_ID = "jalvi_wake_listener"
        private const val NOTIFICATION_ID = 7302
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ready = false
    private var waitingForUser = false

    override fun onCreate() {
        super.onCreate()
        createChannel()
        tts = TextToSpeech(this, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale("hi", "IN")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_START) {
            val notification = buildNotification("Jarvis wake word is active")
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            ready = SpeechRecognizer.isRecognitionAvailable(this)
            if (ready) startRecognition() else updateNotification("Speech recognition service unavailable")
        }
        return START_STICKY
    }

    private fun startRecognition() {
        if (!ready || waitingForUser) return
        handler.removeCallbacksAndMessages(null)
        try {
            recognizer?.destroy()
            recognizer = SpeechRecognizer.createSpeechRecognizer(this)
            recognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: android.os.Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() { scheduleRestart(700) }
                override fun onError(error: Int) { scheduleRestart(1200) }
                override fun onResults(results: android.os.Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
                    if (matches.any { phrase ->
                        val p = phrase.lowercase(Locale.ROOT)
                        p.contains("jarvis") || p.contains("जार्विस") || p.contains("जार्विस")
                    }) {
                        onWakeWord()
                    } else scheduleRestart(500)
                }
                override fun onPartialResults(partialResults: android.os.Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
                    if (matches.any { it.lowercase(Locale.ROOT).contains("jarvis") || it.contains("जार्विस") }) onWakeWord()
                }
                override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
            })
            val request = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "hi-IN")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            recognizer?.startListening(request)
        } catch (_: Exception) {
            scheduleRestart(1800)
        }
    }

    private fun onWakeWord() {
        if (waitingForUser) return
        waitingForUser = true
        try { recognizer?.cancel() } catch (_: Exception) {}
        updateNotification("Jarvis detected — tap notification to speak")
        tts?.speak("Haan boliye Masum", TextToSpeech.QUEUE_FLUSH, null, "jalvi_wake_ack")
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_WAKE_COMMAND, true)
        }
        if (launch != null) {
            val pending = PendingIntent.getActivity(this, 7303, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification("Jarvis detected — tap to give your command", pending))
        }
        handler.postDelayed({
            waitingForUser = false
            startRecognition()
            updateNotification("Jarvis wake word is active")
        }, 12000)
    }

    private fun scheduleRestart(delay: Long) {
        if (!waitingForUser) handler.postDelayed({ startRecognition() }, delay)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "JALVI wake-word microphone", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Visible status and controls while Jarvis wake-word listening is enabled"
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String, contentIntent: PendingIntent? = null): Notification {
        val stopIntent = PendingIntent.getService(this, 7304,
            Intent(this, WakeWordService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID)
            else Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("JALVI AI — Jarvis mode")
            .setContentText(text)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "STOP", stopIntent)
        if (contentIntent != null) builder.setContentIntent(contentIntent).setAutoCancel(false)
        return builder.build()
    }

    private fun updateNotification(text: String) {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { recognizer?.cancel(); recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
        tts?.stop()
        tts?.shutdown()
        tts = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
