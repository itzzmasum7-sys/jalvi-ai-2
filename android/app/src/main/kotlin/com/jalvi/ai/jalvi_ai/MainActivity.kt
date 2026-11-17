package com.jalvi.ai.jalvi_ai

import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.provider.Telephony
import android.database.Cursor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "com.jalvi.ai/native"
    private var nativeChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        nativeChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWakeWord" -> {
                        try {
                            val service = Intent(this, WakeWordService::class.java).apply { action = WakeWordService.ACTION_START }
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) startForegroundService(service) else startService(service)
                            result.success(true)
                        } catch (e: Exception) { result.error("WAKE_START", e.message, null) }
                    }
                    "stopWakeWord" -> {
                        stopService(Intent(this, WakeWordService::class.java))
                        result.success(true)
                    }
                    "findContact" -> {
                        if (checkSelfPermission(android.Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                            result.error("PERMISSION", "Contacts permission not granted", null)
                        } else {
                            try {
                                val name = call.argument<String>("name")?.trim().orEmpty()
                                result.success(findContacts(name))
                            } catch (e: Exception) {
                                result.error("CONTACT_ERROR", e.message, null)
                            }
                        }
                    }
                    "getRecentSms" -> {
                        if (checkSelfPermission(android.Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
                            result.error("PERMISSION", "READ_SMS permission not granted", null)
                        } else {
                            try {
                                result.success(readRecentSms())
                            } catch (e: Exception) {
                                result.error("SMS_ERROR", e.message, null)
                            }
                        }
                    }
                    "openMapsSearch" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        if (query.isBlank()) {
                            result.error("EMPTY_QUERY", "Maps search query is empty", null)
                        } else {
                            val uri = Uri.parse("geo:0,0?q=" + Uri.encode(query))
                            val intent = Intent(Intent.ACTION_VIEW, uri)
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("MAPS_ERROR", e.message, null)
                            }
                        }
                    }
                    "searchYoutube" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        if (query.isBlank()) {
                            result.error("EMPTY_QUERY", "YouTube search query is empty", null)
                        } else {
                            val url = "https://www.youtube.com/results?search_query=" +
                                Uri.encode(query)
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                setPackage("com.google.android.youtube")
                            }
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                try {
                                    startActivity(browserIntent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("YOUTUBE_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "openNotificationAccess" -> {
                        try {
                            startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOTIFICATION_SETTINGS_ERROR", e.message, null)
                        }
                    }
                    "getRecentNotifications" -> {
                        result.success(NotificationCaptureService.recentNotifications())
                    }
                    "openSettings" -> {
                        try {
                            startActivity(Intent(android.provider.Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    }
                    "openApp" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val launch = packageManager.getLaunchIntentForPackage(pkg)
                        if (launch != null) {
                            startActivity(launch)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "openDialer" -> {
                        val number = call.argument<String>("number") ?: ""
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                        startActivity(intent)
                        result.success(true)
                    }
                    "setTorch" -> {
                        try {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            val manager = getSystemService(CAMERA_SERVICE) as CameraManager
                            val cameraId = manager.cameraIdList.firstOrNull { id ->
                                manager.getCameraCharacteristics(id).get(
                                    android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE
                                ) == true
                            }
                            if (cameraId == null) {
                                result.success(false)
                            } else {
                                manager.setTorchMode(cameraId, enabled)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("TORCH_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(WakeWordService.EXTRA_WAKE_COMMAND, false)) {
            nativeChannel?.invokeMethod("wakeWordDetected", null)
            intent.removeExtra(WakeWordService.EXTRA_WAKE_COMMAND)
        }
    }

    private fun findContacts(query: String): List<Map<String, String>> {
        if (query.isBlank()) return emptyList()
        val output = mutableListOf<Map<String, String>>()
        val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val projection = arrayOf(
            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        val selection = "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        contentResolver.query(uri, projection, selection, arrayOf("%$query%"), null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIndex = cursor.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext() && output.size < 5) {
                output.add(mapOf(
                    "name" to (cursor.getString(nameIndex) ?: ""),
                    "number" to (cursor.getString(numberIndex) ?: "")
                ))
            }
        }
        return output
    }

    private fun readRecentSms(): List<Map<String, String>> {
        val items = mutableListOf<Map<String, String>>()
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val cursor: Cursor? = contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            null,
            null,
            "${Telephony.Sms.DATE} DESC"
        )
        cursor?.use {
            val addressIndex = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIndex = it.getColumnIndex(Telephony.Sms.BODY)
            val dateIndex = it.getColumnIndex(Telephony.Sms.DATE)
            var count = 0
            while (it.moveToNext() && count < 20) {
                val address = it.getString(addressIndex) ?: "Unknown sender"
                val body = it.getString(bodyIndex) ?: ""
                val millis = it.getLong(dateIndex)
                val date = SimpleDateFormat("dd MMM, hh:mm a", Locale.getDefault()).format(Date(millis))
                items.add(
                    mapOf(
                        "address" to address,
                        "name" to "",
                        "body" to body,
                        "date" to date
                    )
                )
                count++
            }
        }
        return items
    }
}