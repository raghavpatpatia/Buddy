# Plugins called via JNI/reflection (jnigen-based shared_preferences, workmanager callbacks)
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class com.raghav.buddy_app.** { *; }
