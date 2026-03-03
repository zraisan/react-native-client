# Keep classes annotated with @DoNotStrip and @Keep (used by Nitro codegen)
-keep @com.facebook.proguard.annotations.DoNotStrip class *
-keepclassmembers class * {
    @com.facebook.proguard.annotations.DoNotStrip *;
}
-keep @androidx.annotation.Keep class *
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Keep all native methods (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Nitro module classes accessed from C++ via JNI
-keep class com.margelo.nitro.client.** { *; }
