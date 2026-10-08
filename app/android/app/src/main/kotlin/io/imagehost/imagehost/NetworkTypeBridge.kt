package io.imagehost.imagehost

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Passive observation of the app's default network. No requestNetwork, network
// binding, traffic probes, location fields, or billing information is read.
internal class NetworkTypeBridge(context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {
    private val manager = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "io.imagehost/network")
    private val events = EventChannel(messenger, "io.imagehost/network_changes")
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var currentNetwork: Network? = null
    private var snapshot = state("unknown")
    private var generation = 0L
    private var disposed = false

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
            } else {
                try {
                    // During a subscription, only callback capability evidence
                    // describes the current network; do not race it with queries.
                    result.success(if (callback != null) snapshot else readInitial())
                } catch (_: Exception) {
                    result.error("network_error", "Unable to read network type.", null)
                }
            }
        }
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        stop()
        if (disposed) {
            eventSink.error("network_error", "Network observer is closed.", null)
            return
        }
        sink = eventSink
        val listenerGeneration = ++generation
        val observer = object : ConnectivityManager.NetworkCallback() {
            private fun isCurrent() = !disposed && listenerGeneration == generation &&
                callback === this

            override fun onAvailable(network: Network) {
                if (!isCurrent()) return
                currentNetwork = network
                // Android sends capabilities next. Querying synchronously inside
                // this callback can associate stale capabilities with a new route.
                publish(state("unknown"))
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                if (!isCurrent() || network != currentNetwork) return
                publish(fromCapabilities(caps))
            }

            override fun onLost(network: Network) {
                if (!isCurrent() || network != currentNetwork) return
                currentNetwork = null
                publish(state("offline"))
            }
        }
        callback = observer
        try {
            manager.registerDefaultNetworkCallback(observer, handler)
            // Registration and this initial snapshot both happen on main. The
            // registered callback is also delivered on main, after this call.
            snapshot = readInitial()
            eventSink.success(snapshot)
        } catch (_: Exception) {
            stop()
            eventSink.error("network_error", "Unable to observe network type.", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        stop()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    private fun stop() {
        ++generation
        val previous = callback
        callback = null
        sink = null
        currentNetwork = null
        snapshot = state("unknown")
        if (previous != null) {
            try {
                manager.unregisterNetworkCallback(previous)
            } catch (_: Exception) {
                // An already delivered/queued callback remains inert through its
                // generation check even if the OS cannot confirm unregistration.
            }
        }
    }

    private fun readInitial(): Map<String, Any> {
        val network = manager.activeNetwork
        if (network == null) {
            currentNetwork = null
            return state("offline")
        }
        val caps = manager.getNetworkCapabilities(network)
        if (manager.activeNetwork != network) {
            currentNetwork = null
            return state("unknown")
        }
        currentNetwork = network
        return if (caps == null) state("unknown") else fromCapabilities(caps)
    }

    private fun publish(value: Map<String, Any>) {
        if (value == snapshot) return
        snapshot = value
        sink?.success(value)
    }

    private fun fromCapabilities(caps: NetworkCapabilities): Map<String, Any> {
        val transports = mutableListOf<String>()
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("wifi")
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("ethernet")
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("cellular")
        if (transports.isEmpty()) transports.add("other")
        return state("connected", transports)
    }

    private fun state(status: String, transports: List<String> = emptyList()): Map<String, Any> =
        mapOf("status" to status, "transports" to transports)
}
