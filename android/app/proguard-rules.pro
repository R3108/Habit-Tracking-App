# App-specific R8 rules for the release build.
#
# Flutter's own keep rules are contributed by the Flutter Gradle plugin, and
# flutter_local_notifications has shipped its own consumer rules since v19, so
# neither needs to be repeated here.

# Reflection-based lookups in the desugared java.time backport.
-dontwarn java.beans.**
-dontwarn javax.naming.**

# Keep the line numbers in Play Console crash reports meaningful while still
# obfuscating names. Upload the mapping file with each release.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
