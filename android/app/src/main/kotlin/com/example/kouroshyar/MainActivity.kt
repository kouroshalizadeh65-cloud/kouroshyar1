package com.example.kouroshyar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Secure by default. Dart may explicitly allow capture after loading
        // the user's local privacy preference.
        setScreenCaptureAllowed(false)
    }

    private fun setScreenCaptureAllowed(allowed: Boolean) {
        if (allowed) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun openSafely(primary: Intent, fallback: Intent? = null): Boolean {
        return try {
            startActivity(primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            if (fallback == null) return false
            try {
                startActivity(fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun appDetailsIntent(): Intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:$packageName")
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kouroshyar/app_info"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getAppVersion") {
                try {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        packageInfo.versionCode.toLong()
                    }
                    result.success(
                        mapOf(
                            "versionName" to (packageInfo.versionName ?: BuildConfig.VERSION_NAME),
                            "versionCode" to versionCode,
                            "packageName" to packageName
                        )
                    )
                } catch (error: Exception) {
                    result.error("APP_VERSION_UNAVAILABLE", error.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kouroshyar/no_backup"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getNoBackupPath") {
                result.success(noBackupFilesDir.absolutePath)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kouroshyar/privacy"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenCaptureAllowed" -> {
                    val allowed = call.argument<Boolean>("allowed") ?: false
                    runOnUiThread { setScreenCaptureAllowed(allowed) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kouroshyar/notifications"
        ).setMethodCallHandler { call, result ->
            val opened = when (call.method) {
                "openNotificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        appDetailsIntent()
                    }
                    openSafely(intent, appDetailsIntent())
                }
                "openExactAlarmSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:$packageName")
                        )
                    } else {
                        appDetailsIntent()
                    }
                    openSafely(intent, appDetailsIntent())
                }
                "openBatterySettings" -> openSafely(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    appDetailsIntent()
                )
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(opened)
        }
    }
}
