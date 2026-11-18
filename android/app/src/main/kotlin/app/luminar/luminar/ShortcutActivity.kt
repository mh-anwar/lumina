package app.luminar.luminar

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Runs an app shortcut (res/xml/shortcuts.xml) without opening Lumina: hands
 * its luminar:// action to the same background path as the home-screen
 * widgets (lib/widget_entry.dart), says what it is doing, and closes. If the
 * action then fails, a toast says so.
 */
class ShortcutActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val uri = intent?.data
    if (uri != null && uri.scheme == "luminar") {
      watchForFailure(applicationContext)
      HomeWidgetBackgroundIntent.getBroadcast(this, uri).send()
      val what =
          when (uri.host) {
            "toggle" -> "Switching lights…"
            "preset" -> "Lights: ${uri.getQueryParameter("name")}"
            else -> null
          }
      if (what != null) Toast.makeText(applicationContext, what, Toast.LENGTH_SHORT).show()
    }
    finish()
    if (Build.VERSION.SDK_INT >= 34) {
      overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
    } else {
      @Suppress("DEPRECATION") overridePendingTransition(0, 0)
    }
  }

  companion object {
    /** How long to wait for the action's outcome. */
    private const val WATCH_MS = 90_000L

    // SharedPreferences holds listeners weakly; keep the current one here.
    private var watcher: SharedPreferences.OnSharedPreferenceChangeListener? = null

    /**
     * Waits for the background action to save its outcome under "status"
     * (after "busy") and shows a toast if it was "unavailable".
     */
    private fun watchForFailure(app: Context) {
      val prefs = HomeWidgetPlugin.getData(app)
      watcher?.let { prefs.unregisterOnSharedPreferenceChangeListener(it) }
      val handler = Handler(Looper.getMainLooper())
      lateinit var listener: SharedPreferences.OnSharedPreferenceChangeListener
      val stop = Runnable {
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
        if (watcher === listener) watcher = null
      }
      listener =
          SharedPreferences.OnSharedPreferenceChangeListener { p, key ->
            if (key != "status") return@OnSharedPreferenceChangeListener
            val status = p.getString("status", null)
            if (status == "busy") return@OnSharedPreferenceChangeListener
            if (status == "unavailable") {
              Toast.makeText(app, R.string.shortcut_failed, Toast.LENGTH_LONG).show()
            }
            handler.removeCallbacks(stop)
            stop.run()
          }
      watcher = listener
      prefs.registerOnSharedPreferenceChangeListener(listener)
      handler.postDelayed(stop, WATCH_MS)
    }
  }
}
