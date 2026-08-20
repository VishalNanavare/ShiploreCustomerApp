# Flutter / Dart — keep all Flutter engine classes.
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Flutter's deferred-components support references Play Core split-install
# classes even though this app doesn't use dynamic feature delivery — the
# dependency is never added, so R8 must be told not to fail on the reference.
-dontwarn com.google.android.play.core.**

# Firebase — prevent stripping of Firebase SDK internals.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Firebase Crashlytics — keep crash reporting metadata.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# PayU CheckoutPro — SDK uses reflection; keep all PayU classes.
-keep class com.payu.** { *; }
-dontwarn com.payu.**

# OkHttp / Dio (used internally by some Flutter plugins).
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Flutter Secure Storage — Android Keystore backed; keep its JNI bridge.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Google Maps — keep native map view bridge.
-keep class com.google.maps.** { *; }
-dontwarn com.google.maps.**

# Kotlin metadata / coroutines.
-keepattributes *Annotation*
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
