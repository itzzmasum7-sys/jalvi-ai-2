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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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