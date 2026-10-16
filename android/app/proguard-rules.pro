# permission_handler is reached through Flutter's plugin registrant, which
# resolves its entry point reflectively — R8 can't see that reference and will
# strip the class under the release build's minification.
-keep class com.baseflow.permissionhandler.** { *; }
