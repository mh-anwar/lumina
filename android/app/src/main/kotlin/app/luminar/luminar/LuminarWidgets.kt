package app.luminar.luminar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONException

/**
 * Lumina's home-screen widgets. Taps run Dart in the background
 * (lib/widget_entry.dart); Dart saves the status ("on", "off", "busy",
 * "unavailable") under "status", or "light_<addr>_status" for one light, and
 * asks for a redraw.
 */
object LuminarWidgets {
  private fun tap(context: Context, uri: String) =
      HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri))

  /** Opens Lumina, which says why the lights couldn't be reached. */
  fun openApp(context: Context): PendingIntent =
      PendingIntent.getActivity(
          context,
          0,
          Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
          PendingIntent.FLAG_UPDATE_CURRENT or
              (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0),
      )

  /**
   * Draws an on/off button for [status] that sends [uri] when tapped, or
   * opens the app after a failure so it can say why. Returns the text color
   * it used.
   */
  fun bindToggle(context: Context, views: RemoteViews, status: String?, uri: String): Int {
    val (background, label) =
        when (status) {
          "on" -> R.drawable.widget_on_bg to "On"
          "busy" -> R.drawable.widget_busy_bg to "…"
          "unavailable" -> R.drawable.widget_off_bg to "Retry"
          else -> R.drawable.widget_off_bg to "Off"
        }
    val ink =
        ContextCompat.getColor(
            context,
            if (status == "on") R.color.widget_on_text else R.color.widget_text,
        )
    views.setInt(R.id.toggle, "setBackgroundResource", background)
    views.setTextViewText(R.id.toggle_label, label)
    views.setTextColor(R.id.toggle_label, ink)
    views.setInt(R.id.toggle_icon, "setColorFilter", ink)
    views.setOnClickPendingIntent(
        R.id.toggle,
        if (status == "unavailable") openApp(context) else tap(context, uri),
    )
    return ink
  }

  fun bindPresets(context: Context, views: RemoteViews) {
    for ((id, name) in
        listOf(
            R.id.preset_relax to "Relax",
            R.id.preset_read to "Read",
            R.id.preset_daylight to "Daylight",
            R.id.preset_night to "Night",
        )) {
      views.setOnClickPendingIntent(id, tap(context, "luminar://preset?name=$name"))
    }
  }
}

/** 1×1: all lights on or off. */
class LightsToggleWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.widget_toggle)
      LuminarWidgets.bindToggle(
          context, views, widgetData.getString("status", "off"), "luminar://toggle")
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}

/** 4×1: on/off plus the four presets. */
class LightsPresetsWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.widget_presets)
      LuminarWidgets.bindToggle(
          context, views, widgetData.getString("status", "off"), "luminar://toggle")
      LuminarWidgets.bindPresets(context, views)
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}

/**
 * 1×1: one light on or off, chosen in [OneLightConfigureActivity] when the
 * widget is added. The app saves its lights under "lights" as JSON
 * (`[{"addr": 16, "name": "Desk"}, …]`).
 */
class OneLightWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) draw(context, appWidgetManager, id, widgetData)
  }

  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    super.onDeleted(context, appWidgetIds)
    val edit = HomeWidgetPlugin.getData(context).edit()
    for (id in appWidgetIds) edit.remove(addrKey(id))
    edit.apply()
  }

  companion object {
    /** Where the address of the light widget [id] switches is saved. */
    fun addrKey(id: Int) = "one_light_$id"

    /** The lights the app saved, as (address, name). */
    fun lights(prefs: SharedPreferences): List<Pair<Int, String>> {
      val json = prefs.getString("lights", null) ?: return emptyList()
      return try {
        val array = JSONArray(json)
        (0 until array.length()).map {
          val light = array.getJSONObject(it)
          light.getInt("addr") to light.getString("name")
        }
      } catch (e: JSONException) {
        emptyList()
      }
    }

    fun draw(context: Context, manager: AppWidgetManager, id: Int, prefs: SharedPreferences) {
      val views = RemoteViews(context.packageName, R.layout.widget_light)
      val addr = prefs.getInt(addrKey(id), -1)
      if (addr < 0) {
        views.setTextViewText(R.id.light_name, context.getString(R.string.widget_light_choose))
        views.setOnClickPendingIntent(R.id.toggle, LuminarWidgets.openApp(context))
      } else {
        val name =
            lights(prefs).firstOrNull { it.first == addr }?.second
                ?: context.getString(R.string.widget_light_missing)
        val ink =
            LuminarWidgets.bindToggle(
                context,
                views,
                prefs.getString("light_${addr}_status", "off"),
                "luminar://light?addr=0x%04x".format(addr),
            )
        views.setTextViewText(R.id.light_name, name)
        views.setTextColor(R.id.light_name, ink)
        views.setContentDescription(R.id.toggle, name)
      }
      manager.updateAppWidget(id, views)
    }
  }
}
