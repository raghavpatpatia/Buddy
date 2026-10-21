package com.raghav.buddy_app.channel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

typealias Route = (MethodCall, MethodChannel.Result) -> Unit

/** One domain's slice of the buddy/native channel: method name -> command. */
interface ChannelHandler {
    val routes: Map<String, Route>
}

/** Dispatches buddy/native calls to the domain handlers; any thrown error becomes a channel error. */
class NativeRouter(handlers: List<ChannelHandler>) : MethodChannel.MethodCallHandler {
    private val routes: Map<String, Route> = handlers.flatMap { it.routes.entries }.associate { it.key to it.value }
        .also { m -> check(m.size == handlers.sumOf { it.routes.size }) { "duplicate channel method" } }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val route = routes[call.method] ?: return result.notImplemented()
        try { route(call, result) } catch (e: Exception) { result.error("native", e.message, null) }
    }
}

/** Slow system queries (storage stats can take seconds) run here so the UI never freezes. */
object Background {
    private val pool = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    fun run(result: MethodChannel.Result, work: () -> Any?) {
        pool.execute {
            val r = try { Result.success(work()) } catch (e: Exception) { Result.failure(e) }
            main.post { r.fold({ result.success(it) }, { result.error("native", it.message, null) }) }
        }
    }
}
