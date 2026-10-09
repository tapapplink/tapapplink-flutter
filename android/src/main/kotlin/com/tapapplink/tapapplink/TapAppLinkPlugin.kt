package com.tapapplink.tapapplink

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.atomic.AtomicBoolean

/** Android plugin that reads the Play Install Referrer string. */
class TapAppLinkPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.tapapplink/tapapplink")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "getInstallReferrer" -> {
                val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: DEFAULT_TIMEOUT_MS
                fetchInstallReferrer(timeoutMs, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun fetchInstallReferrer(
        timeoutMs: Long,
        result: Result,
    ) {
        val context = appContext
        if (context == null) {
            result.success(null)
            return
        }

        val completed = AtomicBoolean(false)
        val client = InstallReferrerClient.newBuilder(context).build()
        val mainHandler = Handler(Looper.getMainLooper())

        fun finish(value: String?) {
            if (completed.compareAndSet(false, true)) {
                runCatching { client.endConnection() }
                mainHandler.post { result.success(value) }
            }
        }

        val timeoutRunnable = Runnable { finish(null) }
        mainHandler.postDelayed(timeoutRunnable, timeoutMs)

        try {
            client.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        val referrer =
                            if (responseCode == InstallReferrerResponse.OK) {
                                try {
                                    client.installReferrer.installReferrer
                                } catch (_: Exception) {
                                    null
                                }
                            } else {
                                null
                            }
                        finish(referrer)
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        // Leave the timeout to complete if we never finished.
                    }
                },
            )
        } catch (_: Exception) {
            mainHandler.removeCallbacks(timeoutRunnable)
            finish(null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
    }

    companion object {
        private const val DEFAULT_TIMEOUT_MS = 3000L
    }
}
