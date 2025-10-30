# PassGFW ProGuard Rules

# Keep PassGFW public API
-keep class com.passgfw.PassGFW { *; }
-keep class com.passgfw.LogLevel { *; }
-keepclassmembers class com.passgfw.** { *; }

# Keep Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep generic signature
-keepattributes Signature

# Keep annotations
-keepattributes *Annotation*,SourceFile,LineNumberTable

# Keep exception messages
-keepattributes Exceptions

