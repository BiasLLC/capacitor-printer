# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep all classes in the plugin package
-keep class com.capgo.printer.** { *; }

# Keep Capacitor classes
-keep class com.getcapacitor.** { *; }

# Keep AndroidX Print classes
-keep class androidx.print.** { *; }

# Keep AndroidX DocumentFile classes
-keep class androidx.documentfile.provider.** { *; }
