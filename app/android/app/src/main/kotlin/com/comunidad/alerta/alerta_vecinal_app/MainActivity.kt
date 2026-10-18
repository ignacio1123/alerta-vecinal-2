package com.comunidad.alerta.alerta_vecinal_app

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.comunidad.alerta/native_alert"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenVisibility()
    }

    private fun configureLockScreenVisibility() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeUpAndUnlock" -> {
                    try {
                        runOnUiThread {
                            configureLockScreenVisibility()
                        }
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        @Suppress("DEPRECATION")
                        val wakeLock = powerManager.newWakeLock(
                            PowerManager.FULL_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                            "AlertaVecinal:EmergencyWakeLock"
                        )
                        wakeLock.acquire(30 * 1000L /*30 seconds*/)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                            keyguardManager.requestDismissKeyguard(this, null)
                        }

                        val bringIntent = Intent(this@MainActivity, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                        startActivity(bringIntent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKE_ERROR", e.message, null)
                    }
                }
                "setMaxVolume" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        
                        try {
                            val maxAlarm = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarm, 0)
                        } catch (_: Exception) {}

                        try {
                            val maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0)
                        } catch (_: Exception) {}

                        try {
                            val maxRing = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)
                            audioManager.setStreamVolume(AudioManager.STREAM_RING, maxRing, 0)
                        } catch (_: Exception) {}

                        try {
                            val maxNotification = audioManager.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)
                            audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, maxNotification, 0)
                        } catch (_: Exception) {}

                        try {
                            audioManager.ringerMode = AudioManager.RINGER_MODE_NORMAL
                        } catch (_: Exception) {}

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                "showCommunityNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "📢 Comunicado Oficial"
                        val message = call.argument<String>("message") ?: "Hay un nuevo aviso comunitario."
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val channelId = "alerta_vecinal_comunicados"

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val channel = NotificationChannel(
                                channelId,
                                "Comunicados Oficiales de la Comunidad",
                                NotificationManager.IMPORTANCE_HIGH
                            ).apply {
                                description = "Notificaciones de avisos y comunicados oficiales vecinales"
                                enableLights(true)
                                enableVibration(true)
                            }
                            notificationManager.createNotificationChannel(channel)
                        }

                        val intent = Intent(this@MainActivity, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        val pendingIntent = PendingIntent.getActivity(
                            this@MainActivity,
                            0,
                            intent,
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
                        )

                        val notification = NotificationCompat.Builder(this@MainActivity, channelId)
                            .setSmallIcon(R.mipmap.ic_launcher)
                            .setContentTitle(title)
                            .setContentText(message)
                            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                            .setPriority(NotificationCompat.PRIORITY_HIGH)
                            .setAutoCancel(true)
                            .setContentIntent(pendingIntent)
                            .build()

                        notificationManager.notify(202, notification)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "shareWhatsAppDirect" -> {
                    try {
                        val phone = call.argument<String>("phone") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
                        val cleanPhone = phone.replace(Regex("[^0-9]"), "")

                        val fullPhone = when {
                            cleanPhone.length == 9 && cleanPhone.startsWith("9") -> "56$cleanPhone"
                            cleanPhone.length == 8 -> "569$cleanPhone"
                            else -> cleanPhone
                        }
                        val jid = if (fullPhone.isNotEmpty()) "$fullPhone@s.whatsapp.net" else null

                        val pm = packageManager
                        val isStandardInstalled = try {
                            pm.getPackageInfo("com.whatsapp", 0)
                            true
                        } catch (e: Exception) {
                            false
                        }
                        val isBusinessInstalled = try {
                            pm.getPackageInfo("com.whatsapp.w4b", 0)
                            true
                        } catch (e: Exception) {
                            false
                        }

                        val targetPackage = when {
                            isStandardInstalled -> "com.whatsapp"
                            isBusinessInstalled -> "com.whatsapp.w4b"
                            else -> null
                        }

                        if (imagePaths.isNotEmpty()) {
                            val validFiles = imagePaths.map { File(it) }.filter { it.exists() }
                            if (validFiles.isNotEmpty()) {
                                val authority = "${packageName}.fileprovider"
                                val uris = ArrayList<Uri>()
                                for (file in validFiles) {
                                    val uri = FileProvider.getUriForFile(this@MainActivity, authority, file)
                                    uris.add(uri)
                                }

                                val intent = if (uris.size > 1) {
                                    Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                                        type = "image/*"
                                        putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                                        putExtra(Intent.EXTRA_TEXT, text)
                                        if (jid != null) putExtra("jid", jid)
                                        if (targetPackage != null) setPackage(targetPackage)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                } else {
                                    Intent(Intent.ACTION_SEND).apply {
                                        type = "image/*"
                                        putExtra(Intent.EXTRA_STREAM, uris[0])
                                        putExtra(Intent.EXTRA_TEXT, text)
                                        if (jid != null) putExtra("jid", jid)
                                        if (targetPackage != null) setPackage(targetPackage)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                }

                                if (targetPackage != null) {
                                    for (uri in uris) {
                                        grantUriPermission(targetPackage, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    }
                                }

                                startActivity(intent)
                                result.success(true)
                                return@setMethodCallHandler
                            }
                        }

                        // Si no hay imágenes, abrir el chat directo con texto
                        if (targetPackage != null && fullPhone.isNotEmpty()) {
                            val waUri = Uri.parse("whatsapp://send?phone=$fullPhone&text=${Uri.encode(text)}")
                            val intent = Intent(Intent.ACTION_VIEW, waUri).apply {
                                setPackage(targetPackage)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("WHATSAPP_DIRECT_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
