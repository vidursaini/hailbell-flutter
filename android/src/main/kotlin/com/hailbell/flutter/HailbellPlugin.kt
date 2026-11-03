package com.hailbell.flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.hailbell.Campaigns
import com.hailbell.Hailbell
import com.hailbell.HailbellPush
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlin.coroutines.resume

/**
 * The Flutter side of Hailbell on Android. Every call goes to the native SDK in `vendor/hailbell`,
 * which draws the chat and talks to the server. This class only translates between Dart and Kotlin.
 *
 * One instance runs per Flutter engine: the app's own, and a second one when `firebase_messaging`
 * starts a background engine for a push. The native SDK is a single object for the whole process,
 * so callbacks into Dart (paywalls, Firebase tokens) go to the engine that called `configure`.
 */
class HailbellPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var unreadChannel: EventChannel
    private var unreadJob: Job? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "hailbell")
        channel.setMethodCallHandler(this)
        unreadChannel = EventChannel(binding.binaryMessenger, "hailbell/unread_count")
        unreadChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                unreadJob?.cancel()
                unreadJob = scope.launch { Hailbell.unreadCount.collect { events.success(it) } }
            }

            override fun onCancel(arguments: Any?) {
                unreadJob?.cancel()
                unreadJob = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        unreadChannel.setStreamHandler(null)
        unreadJob?.cancel()
        if (activeChannel === channel) activeChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        if (currentActivity === activityBinding?.activity) currentActivity = null
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            handle(call, result)
        } catch (e: Exception) {
            result.error("hailbell_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val appId = call.argument<String>("appId")!!
                val baseUrl = call.argument<String>("baseUrl") ?: DEFAULT_BASE_URL
                configure(context, appId, baseUrl)
                activeChannel = channel
                dartConfigured = true
                if (pendingChatOpen) {
                    pendingChatOpen = false
                    // Give the app a moment to call identify, so the chat opens on the right person.
                    openChatWhenReady(attempts = 10)
                }
                result.success(null)
            }
            "open" -> {
                val activity = currentActivity ?: return result.error("no_activity", "The app has no activity on screen.", null)
                Hailbell.open(activity)
                result.success(null)
            }
            "identify" -> {
                val name = call.argument<String>("name")
                val email = call.argument<String>("email")
                if (call.argument<Boolean>("firebase") == true) {
                    activeChannel = channel
                    Hailbell.identify(name = name, email = email) { firebaseIdToken() }
                } else {
                    Hailbell.identify(call.argument("userId"), name, email, call.argument("identityToken"))
                }
                result.success(null)
            }
            "setMetadata" -> {
                Hailbell.setMetadata(call.argument<Map<String, String>>("metadata") ?: emptyMap())
                result.success(null)
            }
            "track" -> {
                Hailbell.track(call.argument<String>("event")!!, call.argument<Map<String, String>>("properties") ?: emptyMap())
                result.success(null)
            }
            "setPaywallPlacements" -> {
                Hailbell.setPaywallPlacements(call.argument<List<String>>("placements") ?: emptyList())
                result.success(null)
            }
            "setPaywallHandler" -> {
                if (call.argument<Boolean>("enabled") == true) {
                    activeChannel = channel
                    Hailbell.onPaywall = ::presentPaywall
                } else {
                    Hailbell.onPaywall = null
                }
                result.success(null)
            }
            "paywallPurchased" -> {
                purchases.remove(call.argument<String>("id"))?.invoke()
                result.success(null)
            }
            "setPushToken" -> {
                Hailbell.setPushToken(call.argument<String>("token")!!)
                result.success(null)
            }
            "handleNotification" -> {
                val data = call.argument<Map<String, String>>("data") ?: emptyMap()
                val activity = currentActivity
                if (!data.containsKey("hailbell") || activity == null) return result.success(false)
                Hailbell.open(activity)
                result.success(true)
            }
            "reset" -> {
                Hailbell.reset()
                result.success(null)
            }
            "deleteData" -> scope.launch {
                try {
                    Hailbell.deleteData()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("delete_failed", e.message ?: "Hailbell couldn't delete the data.", null)
                }
            }
            "setDarkMode" -> {
                Hailbell.darkMode = call.argument<Boolean>("value")
                result.success(null)
            }
            "setAsksForNotifications" -> {
                Hailbell.asksForNotifications = call.argument<Boolean>("value") ?: true
                result.success(null)
            }
            "setTeamPhoto" -> {
                val bytes = call.argument<ByteArray>("bytes")
                Hailbell.teamPhoto = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                result.success(null)
            }
            "push.requestPermission" -> requestPermission(result)
            "push.canNotify" -> result.success(HailbellPush.canNotify(context))
            "push.setTags" -> {
                HailbellPush.setTags(call.argument<Map<String, String?>>("tags") ?: emptyMap())
                result.success(null)
            }
            "push.setMarketing" -> {
                HailbellPush.setMarketing(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }
            "push.optOut" -> {
                HailbellPush.optOut()
                result.success(null)
            }
            "push.handleMessage" -> result.success(
                handleMessage(context, call.argument<Map<String, String>>("data") ?: emptyMap(), call.argument("title"), call.argument("body")),
            )
            "push.setOffersChannel" -> {
                HailbellPush.offersChannel = call.argument<String>("id")!!
                result.success(null)
            }
            // iOS only: on Android a tapped push opens its link as an intent, and the badge is the system's.
            "push.setOpenHandler", "push.clearBadge" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val activity = currentActivity
        if (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED ||
            activity == null || permissionResult != null
        ) return result.success(HailbellPush.canNotify(context))
        permissionResult = result
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionResult?.success(HailbellPush.canNotify(context))
        permissionResult = null
        return true
    }

    companion object {
        private const val DEFAULT_BASE_URL = "https://api.hailbell.com"
        private const val PERMISSION_REQUEST = 0x4842
        private const val PREFS = "hailbell.flutter"

        internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        private val main = Handler(Looper.getMainLooper())

        /** The channel of the engine that configured Hailbell, for calls into Dart. */
        private var activeChannel: MethodChannel? = null
        private var currentActivity: Activity? = null

        /** True once Dart called configure in this process, so identify has had its chance too. */
        @Volatile
        internal var dartConfigured = false

        /** A reply notification was tapped before Dart started: open the chat once it configures. */
        @Volatile
        internal var pendingChatOpen = false

        /** `purchased` callbacks for paywalls that are open, by id. */
        private val purchases = LinkedHashMap<String, () -> Unit>()

        /**
         * Configures the native SDK once per process. A second native configure would register its
         * lifecycle observers twice, so it only runs again when the App ID or server changes. The
         * values are saved, so a push that wakes the app without Dart can still reach the server.
         */
        internal fun configure(context: Context, appId: String, baseUrl: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("appId", appId).putString("baseUrl", baseUrl).apply()
            val client = Hailbell.client
            if (Hailbell.isConfigured && client != null && client.appId == appId && client.baseUrl == baseUrl) return
            Hailbell.configure(context, appId, baseUrl)
        }

        /** Configures the native SDK from the last App ID Dart used, when Dart hasn't run in this process. */
        internal fun ensureConfigured(context: Context) {
            if (Hailbell.isConfigured) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val appId = prefs.getString("appId", null) ?: return
            Hailbell.configure(context, appId, prefs.getString("baseUrl", null) ?: DEFAULT_BASE_URL)
        }

        /**
         * `HailbellPush.handleMessage`, adjusted for `firebase_messaging`. Unlike a native
         * FirebaseMessagingService, its background handler also receives notification messages that
         * Android has already shown, so a chat reply with a title or body arriving in the background is
         * left alone rather than shown twice.
         */
        internal fun handleMessage(context: Context, data: Map<String, String>, title: String?, body: String?): Boolean {
            ensureConfigured(context)
            val isReply = data.containsKey("hailbell") && Campaigns.parse(data) == null
            val shownByAndroid = isReply && (title != null || body != null) &&
                !ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            if (shownByAndroid) return true
            return HailbellPush.handleMessage(context, data, title, body)
        }

        private fun presentPaywall(placement: String, purchased: () -> Unit) {
            val channel = activeChannel ?: return
            val id = UUID.randomUUID().toString()
            purchases[id] = purchased
            while (purchases.size > 20) purchases.remove(purchases.keys.first())
            channel.invokeMethod("paywall", mapOf("placement" to placement, "id" to id))
        }

        /** Asks Dart for the current Firebase ID token. Null when Dart doesn't answer within 15 seconds. */
        private suspend fun firebaseIdToken(): String? = withContext(Dispatchers.Main) {
            withTimeoutOrNull(15_000) {
                suspendCancellableCoroutine { cont ->
                    val channel = activeChannel
                    if (channel == null) {
                        cont.resume(null)
                        return@suspendCancellableCoroutine
                    }
                    channel.invokeMethod("firebaseIdToken", null, object : MethodChannel.Result {
                        override fun success(result: Any?) { if (cont.isActive) cont.resume(result as? String) }
                        override fun error(code: String, message: String?, details: Any?) { if (cont.isActive) cont.resume(null) }
                        override fun notImplemented() { if (cont.isActive) cont.resume(null) }
                    })
                }
            }
        }

        private fun openChatWhenReady(attempts: Int) {
            main.postDelayed({
                val activity = currentActivity
                when {
                    activity != null -> Hailbell.open(activity)
                    attempts > 0 -> openChatWhenReady(attempts - 1)
                }
            }, 600)
        }
    }
}
