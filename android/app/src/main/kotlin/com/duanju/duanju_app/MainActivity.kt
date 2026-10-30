package com.duanju.duanju_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import android.Manifest
import android.app.UiModeManager
import android.app.ActivityManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.os.Build
import android.os.Bundle
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.res.Resources
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Rational
import android.view.InputDevice
import android.view.OrientationEventListener
import android.view.SurfaceHolder
import android.view.WindowManager
import android.provider.Settings
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import kotlin.math.roundToInt

private const val SURFACE_RESIZE_REDRAW_WAIT_MS = 100L
private const val ORIENTATION_SETTLE_MS = 800L
private const val CREATE_DOCUMENT_REQUEST = 7301
private const val STORAGE_PERMISSION_REQUEST = 7302
private const val PICTURE_IN_PICTURE_ACTION = "com.duanju.duanju_app.PICTURE_IN_PICTURE_ACTION"

private data class PlayerPictureInPicture(
    val width: Int,
    val height: Int,
    val playing: Boolean,
    val hasPrevious: Boolean,
    val hasNext: Boolean,
    val autoEnter: Boolean
)

class MainActivity : FlutterActivity() {
    private var pictureInPicture: PlayerPictureInPicture? = null
    private var pictureInPictureReceiver: BroadcastReceiver? = null
    private var documentResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var textInput: TextInputBridge? = null
    private var headroomReadAt = 0L
    private var thermalHeadroom: Double? = null
    private var deviceChannel: MethodChannel? = null
    private var televisionMode = false
    private var orientationListener: OrientationEventListener? = null

    @Suppress("DEPRECATION")
    private fun isTelevisionDevice(): Boolean {
        val configuration = resources.configuration
        val mode = (getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
            ?: (configuration.uiMode and Configuration.UI_MODE_TYPE_MASK)
        if (mode == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            packageManager.hasSystemFeature("amazon.hardware.fire_tv")) {
            return true
        }
        if (mode == Configuration.UI_MODE_TYPE_CAR ||
            mode == Configuration.UI_MODE_TYPE_WATCH ||
            mode == Configuration.UI_MODE_TYPE_VR_HEADSET ||
            configuration.touchscreen != Configuration.TOUCHSCREEN_NOTOUCH ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_ACCELEROMETER) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_PC)) {
            return false
        }
        val remoteNavigation = configuration.navigation == Configuration.NAVIGATION_DPAD ||
            InputDevice.getDeviceIds().any { id ->
                val device = InputDevice.getDevice(id)
                device != null && !device.isVirtual && device.supportsSource(InputDevice.SOURCE_DPAD)
            }
        return remoteNavigation || packageManager.hasSystemFeature(PackageManager.FEATURE_LIVE_TV)
    }

    private fun renderingPreferences() =
        getSharedPreferences("duanju_rendering", Context.MODE_PRIVATE)

    private fun compatibleRendering(): Boolean =
        renderingPreferences().getBoolean("compatibleRendering", false)

    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        if (compatibleRendering()) args.add("--enable-impeller=false")
        return args
    }

    private fun restartApplication() {
        startActivity(Intent.makeRestartActivityTask(ComponentName(this, MainActivity::class.java)))
        Runtime.getRuntime().exit(0)
    }

    override fun setRequestedOrientation(requestedOrientation: Int) {
        super.setRequestedOrientation(
            if (televisionMode) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else requestedOrientation
        )
    }

    private fun setPlayerOrientation(mode: String) {
        orientationListener?.disable()
        orientationListener = null
        val landscape = mode == "landscape"
        requestedOrientation = when (mode) {
            "landscape", "lockedLandscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            "lockedPortrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        if (!landscape && mode != "portrait") return
        val listener = object : OrientationEventListener(this) {
            private var reachedAt = 0L

            override fun onOrientationChanged(angle: Int) {
                if (angle == ORIENTATION_UNKNOWN) return
                val reached = if (landscape) angle in 60..120 || angle in 240..300
                    else angle <= 30 || angle >= 330
                val rotation = Settings.System.getInt(
                    contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0
                )
                if (!reached || rotation != 1) {
                    reachedAt = 0L
                    return
                }
                val now = SystemClock.uptimeMillis()
                if (reachedAt == 0L) reachedAt = now
                if (now - reachedAt < ORIENTATION_SETTLE_MS) return
                disable()
                orientationListener = null
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
        if (listener.canDetectOrientation()) {
            listener.enable()
            orientationListener = listener
        }
    }

    private fun battery(): Map<String, Any>? {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        return mapOf(
            "level" to level * 100 / scale,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL)
        )
    }

    private fun playbackPower(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val now = SystemClock.elapsedRealtime()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            (headroomReadAt == 0L || now - headroomReadAt >= 10000L)) {
            headroomReadAt = now
            thermalHeadroom = runCatching {
                power?.getThermalHeadroom(0)?.toDouble()?.takeIf { it.isFinite() }
            }.getOrNull()
        }
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else 0
        return mapOf(
            "batterySaver" to (power?.isPowerSaveMode ?: false),
            "onBattery" to ((battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1) <= 0),
            "thermalStatus" to thermalStatus,
            "headroom" to thermalHeadroom,
            "lowMemory" to (activity?.isLowRamDevice ?: true),
            "gles" to (activity?.deviceConfigurationInfo?.reqGlEsVersion ?: 0)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        televisionMode = if (savedInstanceState?.containsKey("duanju.televisionMode") == true) {
            savedInstanceState.getBoolean("duanju.televisionMode")
        } else isTelevisionDevice()
        super.onCreate(savedInstanceState)
        if (televisionMode) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (pictureInPictureSupported()) registerPictureInPictureReceiver()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun registerPictureInPictureReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.getStringExtra("action") ?: return
                deviceChannel?.invokeMethod("pictureInPictureAction", mapOf("action" to action))
            }
        }
        val filter = IntentFilter(PICTURE_IN_PICTURE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        pictureInPictureReceiver = receiver
    }

    override fun onDestroy() {
        pictureInPictureReceiver?.let { unregisterReceiver(it) }
        pictureInPictureReceiver = null
        super.onDestroy()
    }

    override fun onFlutterSurfaceViewCreated(flutterSurfaceView: FlutterSurfaceView) {
        super.onFlutterSurfaceViewCreated(flutterSurfaceView)
        flutterSurfaceView.holder.addCallback(SurfaceResizeRedrawWait())
    }

    private class SurfaceResizeRedrawWait : SurfaceHolder.Callback2 {
        private val handler = Handler(Looper.getMainLooper())
        private var size: Pair<Int, Int>? = null
        private var resized = false

        override fun surfaceCreated(holder: SurfaceHolder) {}

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            val next = width to height
            resized = size != null && size != next
            size = next
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            size = null
            resized = false
        }

        override fun surfaceRedrawNeeded(holder: SurfaceHolder) {}

        override fun surfaceRedrawNeededAsync(holder: SurfaceHolder, drawingFinished: Runnable) {
            if (!resized) return drawingFinished.run()
            resized = false
            handler.postDelayed(drawingFinished, SURFACE_RESIZE_REDRAW_WAIT_MS)
        }
    }

    override fun onResume() {
        super.onResume()
        if (televisionMode) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("duanju.televisionMode", televisionMode)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        textInput = TextInputBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/device")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "deviceInfo" -> {
                            val version = packageManager.getPackageInfo(packageName, 0).versionName
                            result.success(mapOf("television" to isTelevisionDevice(), "version" to version))
                        }
                        "setTelevisionMode" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_display_mode", "缺少电视模式状态", null)
                            } else {
                                val changed = televisionMode != enabled
                                televisionMode = enabled
                                if (enabled || changed) {
                                    requestedOrientation = if (enabled) {
                                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                                    } else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                }
                                result.success(null)
                            }
                        }
                        "setPlayerOrientation" -> {
                            setPlayerOrientation(call.argument<String>("mode") ?: "auto")
                            result.success(null)
                        }
                        "battery" -> result.success(runCatching { battery() }.getOrNull())
                        "playbackPower" -> result.success(runCatching { playbackPower() }.getOrNull())
                        "compatibleRendering" -> result.success(compatibleRendering())
                        "setCompatibleRendering" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_rendering_mode", "缺少兼容渲染模式状态", null)
                            } else if (!renderingPreferences().edit()
                                    .putBoolean("compatibleRendering", enabled).commit()) {
                                result.error("rendering_mode_not_saved", "兼容渲染模式未能保存", null)
                            } else {
                                result.success(null)
                                restartApplication()
                            }
                        }
                        "systemProxy" -> {
                            val connection = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val proxy = connection.defaultProxy
                            val host = proxy?.host.orEmpty()
                            val address = if (host.isNotEmpty() && (proxy?.port ?: 0) > 0) {
                                "http://${if (host.contains(':')) "[$host]" else host}:${proxy!!.port}"
                            } else ""
                            result.success(mapOf(
                                "http" to address,
                                "https" to address,
                                "bypass" to (proxy?.exclusionList?.toList() ?: emptyList<String>()),
                                "pac" to (proxy != null && proxy.pacFileUrl != Uri.EMPTY)
                            ))
                        }
                        "pictureInPictureStatus" -> result.success(pictureInPictureStatus())
                        "enterPictureInPicture" -> {
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            result.success(enterPlayerPictureInPicture(
                                width,
                                height,
                                call.argument<Int>("left"),
                                call.argument<Int>("top"),
                                call.argument<Int>("right"),
                                call.argument<Int>("bottom")
                            ))
                        }
                        "updatePictureInPicture" -> {
                            pictureInPicture = if (call.arguments == null) null else PlayerPictureInPicture(
                                call.argument<Int>("width") ?: 16,
                                call.argument<Int>("height") ?: 9,
                                call.argument<Boolean>("playing") ?: false,
                                call.argument<Boolean>("hasPrevious") ?: false,
                                call.argument<Boolean>("hasNext") ?: false,
                                call.argument<Boolean>("autoEnter") ?: false
                            )
                            if (pictureInPictureSupported()) {
                                runCatching { setPictureInPictureParams(pictureInPictureParams()) }
                            }
                            result.success(null)
                        }
                        "getBrightness" -> {
                            val lp = window.attributes
                            val current = if (lp.screenBrightness >= 0f) {
                                lp.screenBrightness.toDouble()
                            } else {
                                try {
                                    val sys = Settings.System.getInt(
                                        contentResolver,
                                        Settings.System.SCREEN_BRIGHTNESS
                                    )
                                    val resources = Resources.getSystem()
                                    val maxId = resources.getIdentifier(
                                        "config_screenBrightnessSettingMaximum", "integer", "android"
                                    )
                                    val max = if (maxId != 0) resources.getInteger(maxId) else 255
                                    (sys / max.coerceAtLeast(1).toDouble()).coerceIn(0.0, 1.0)
                                } catch (e: Exception) {
                                    0.5
                                }
                            }
                            result.success(current)
                        }
                        "setBrightness" -> {
                            val value = call.argument<Double>("brightness")?.toFloat()
                            if (value != null) {
                                val lp = window.attributes
                                lp.screenBrightness = value.coerceIn(0.01f, 1.0f)
                                window.attributes = lp
                                result.success(true)
                            } else {
                                result.error("invalid_arg", "缺少亮度数值", null)
                            }
                        }
                        "resetBrightness" -> {
                            val lp = window.attributes
                            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = lp
                            result.success(true)
                        }
                        "volume" -> {
                            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            result.success(
                                if (max > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
                                else null
                            )
                        }
                        "setVolume" -> {
                            val value = call.argument<Double>("volume")
                            if (value == null) {
                                result.error("invalid_arg", "缺少音量数值", null)
                            } else {
                                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                                val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                val index = (value.coerceIn(0.0, 1.0) * max).roundToInt()
                                if (index != audio.getStreamVolume(AudioManager.STREAM_MUSIC)) {
                                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                                }
                                result.success(null)
                            }
                        }
                        "openExternalPlayer" -> {
                            val url = call.argument<String>("url")
                            val title = call.argument<String>("title") ?: "短剧"
                            if (!url.isNullOrEmpty()) {
                                try {
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(Uri.parse(url), "video/*")
                                        putExtra("title", title)
                                        putExtra("return_result", true)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("no_player", "未找到外部播放器: ${e.message}", null)
                                }
                            } else {
                                result.error("invalid_url", "播放地址为空", null)
                            }
                        }
                        "createDocument" -> {
                            val name = call.argument<String>("name")
                            if (name.isNullOrEmpty() || documentResult != null) {
                                result.error("invalid_document", "无法创建文件", null)
                            } else {
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                                    putExtra(Intent.EXTRA_TITLE, name)
                                }
                                try {
                                    documentResult = result
                                    startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
                                } catch (e: Exception) {
                                    documentResult = null
                                    result.error("no_document_picker", "系统没有可用的文件保存界面", null)
                                }
                            }
                        }
                        "deleteDocument" -> {
                            val uri = call.argument<String>("uri")
                            result.success(uri != null && runCatching {
                                DocumentsContract.deleteDocument(contentResolver, Uri.parse(uri))
                            }.getOrDefault(false))
                        }
                        "requestVideoExport" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                                PackageManager.PERMISSION_GRANTED) {
                                result.success(true)
                            } else if (permissionResult != null) {
                                result.error("permission_pending", "正在申请存储权限", null)
                            } else {
                                permissionResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                                    STORAGE_PERMISSION_REQUEST
                                )
                            }
                        }
                        "exportVideo" -> {
                            val source = call.argument<String>("source")
                            val folder = call.argument<String>("folder")
                            val name = call.argument<String>("name")
                            if (source.isNullOrEmpty() || folder.isNullOrEmpty() || name.isNullOrEmpty()) {
                                result.error("invalid_export", "导出参数无效", null)
                            } else {
                                Thread {
                                    val outcome = runCatching { exportVideo(File(source), folder, name) }
                                    runOnUiThread {
                                        outcome.fold(
                                            { result.success(null) },
                                            { result.error("export_failed", "导出失败：${it.message}", null) }
                                        )
                                    }
                                }.start()
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun exportVideo(source: File, folder: String, name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val movies = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            val directory = File(movies, folder)
            if (!directory.isDirectory && !directory.mkdirs()) throw IOException("无法创建 Movies/$folder")
            val target = File(directory, name)
            source.copyTo(target, overwrite = true)
            MediaScannerConnection.scanFile(this, arrayOf(target.path), arrayOf("video/mp4"), null)
            return
        }
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relativePath = "${Environment.DIRECTORY_MOVIES}/$folder/"
        val existing = contentResolver.query(
            collection,
            arrayOf(MediaStore.Video.Media._ID),
            "${MediaStore.Video.Media.RELATIVE_PATH}=? AND ${MediaStore.Video.Media.DISPLAY_NAME}=?",
            arrayOf(relativePath, name),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) ContentUris.withAppendedId(collection, cursor.getLong(0)) else null
        }
        val uri = existing ?: contentResolver.insert(collection, ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }) ?: throw IOException("无法在 Movies 中创建文件")
        try {
            val output = contentResolver.openOutputStream(uri, "wt") ?: throw IOException("无法写入 Movies")
            output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
            contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.Video.Media.IS_PENDING, 0)
            }, null, null)
        } catch (e: Exception) {
            if (existing == null) runCatching { contentResolver.delete(uri, null, null) }
            throw e
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.O)
    private fun pictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pictureInPictureStatus(): Map<String, Any> {
        return mapOf(
            "supported" to pictureInPictureSupported(),
            "active" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode)
        )
    }

    private fun enterPlayerPictureInPicture(
        width: Int,
        height: Int,
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Map<String, Any> {
        if (!pictureInPictureSupported()) return pictureInPictureStatus()
        pictureInPicture = pictureInPicture?.copy(width = width, height = height)
            ?: PlayerPictureInPicture(width, height, true, false, false, false)
        return runCatching {
            val sourceRect = if (left != null && top != null && right != null && bottom != null &&
                right > left && bottom > top) Rect(left, top, right, bottom) else null
            val entered = enterPictureInPictureMode(pictureInPictureParams(sourceRect))
            pictureInPictureStatus() + ("requested" to entered)
        }.getOrElse { pictureInPictureStatus() }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pictureInPictureParams(sourceRect: Rect? = null): PictureInPictureParams {
        val state = pictureInPicture
        val builder = PictureInPictureParams.Builder()
        if (state != null) {
            builder.setAspectRatio(Rational(state.width.coerceIn(1, 10000), state.height.coerceIn(1, 10000)))
            builder.setActions(listOf(
                pictureInPictureAction(1, "previous", R.drawable.ic_pip_previous, "上一集", state.hasPrevious),
                if (state.playing) {
                    pictureInPictureAction(2, "toggle", R.drawable.ic_pip_pause, "暂停", true)
                } else {
                    pictureInPictureAction(2, "toggle", R.drawable.ic_pip_play, "播放", true)
                },
                pictureInPictureAction(3, "next", R.drawable.ic_pip_next, "下一集", state.hasNext)
            ))
        } else {
            builder.setActions(emptyList())
        }
        if (sourceRect != null) builder.setSourceRectHint(sourceRect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(state?.autoEnter == true)
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pictureInPictureAction(
        request: Int,
        action: String,
        icon: Int,
        title: String,
        enabled: Boolean
    ): RemoteAction {
        val intent = Intent(PICTURE_IN_PICTURE_ACTION).setPackage(packageName).putExtra("action", action)
        val pending = PendingIntent.getBroadcast(
            this, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pending).apply {
            isEnabled = enabled
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pictureInPicture?.autoEnter != true || !pictureInPictureSupported()) return
        deviceChannel?.invokeMethod("pictureInPicturePending", null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        val entered = runCatching { enterPictureInPictureMode(pictureInPictureParams()) }.getOrDefault(false)
        if (!entered) deviceChannel?.invokeMethod("pictureInPictureChanged", mapOf("active" to false))
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        deviceChannel?.invokeMethod(
            "pictureInPictureChanged",
            mapOf("active" to isInPictureInPictureMode)
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != CREATE_DOCUMENT_REQUEST) {
            return super.onActivityResult(requestCode, resultCode, data)
        }
        val result = documentResult ?: return
        documentResult = null
        result.success(if (resultCode == RESULT_OK) data?.data?.toString() else null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        orientationListener?.disable()
        orientationListener = null
        textInput?.dispose()
        textInput = null
        deviceChannel?.setMethodCallHandler(null)
        deviceChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
