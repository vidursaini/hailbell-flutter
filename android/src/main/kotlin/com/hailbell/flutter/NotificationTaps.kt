package com.hailbell.flutter

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.hailbell.ChatActivity

/**
 * A tapped chat reply (`click_action` HAILBELL_OPEN_CHAT). A native app configures Hailbell in
 * `Application.onCreate`, so its chat can open straight away. A Flutter app configures it from Dart,
 * which only runs once the app's own activity starts. So when Dart hasn't run yet, this starts the
 * app and the plugin opens the chat after Dart's configure, with the right person signed in.
 */
class HailbellOpenChatActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (HailbellPlugin.dartConfigured) {
            // A chat already open behind this activity comes back to the front instead of a second one stacking.
            startActivity(Intent(this, ChatActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
        } else {
            HailbellPlugin.pendingChatOpen = true
            packageManager.getLaunchIntentForPackage(packageName)?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        finish()
    }
}

/**
 * Runs when the app's process starts, before any activity or push handler, like a native app's
 * `Application.onCreate`. It configures the native SDK from the last App ID Dart used, so a push or a
 * notification tap that starts the process still reaches the server: delivery and open counts work
 * before Dart has run. Dart's own configure then finds the SDK ready and doesn't configure it again.
 */
class HailbellInitProvider : android.content.ContentProvider() {
    override fun onCreate(): Boolean {
        context?.applicationContext?.let(HailbellPlugin::ensureConfigured)
        return true
    }

    override fun query(uri: android.net.Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?) = null
    override fun getType(uri: android.net.Uri) = null
    override fun insert(uri: android.net.Uri, values: android.content.ContentValues?) = null
    override fun delete(uri: android.net.Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: android.net.Uri, values: android.content.ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
