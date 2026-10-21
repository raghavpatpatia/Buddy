package com.raghav.buddy_app

import com.raghav.buddy_app.channel.NativeRouter
import com.raghav.buddy_app.channel.PermissionHandler
import com.raghav.buddy_app.channel.ReminderHandler
import com.raghav.buddy_app.channel.ScrollHandler
import com.raghav.buddy_app.channel.SmsHandler
import com.raghav.buddy_app.channel.StorageHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ctx = applicationContext
        val router = NativeRouter(listOf(PermissionHandler(ctx), ReminderHandler(ctx), ScrollHandler(ctx), StorageHandler(ctx), SmsHandler(ctx)))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "buddy/native").setMethodCallHandler(router)
    }
}
