package app.luminar.luminar

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Asks which light a new One light widget switches, from the lights the app
 * last saved (OneLightWidget.lights).
 */
class OneLightConfigureActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val id =
        intent
            ?.extras
            ?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
    val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
    // Backing out leaves no widget behind.
    setResult(RESULT_CANCELED, result)
    if (id == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }
    setTitle(R.string.widget_light_choose)

    val prefs = HomeWidgetPlugin.getData(this)
    val lights = OneLightWidget.lights(prefs)
    if (lights.isEmpty()) {
      val pad = (24 * resources.displayMetrics.density).toInt()
      setContentView(
          TextView(this).apply {
            setText(R.string.widget_light_none)
            textSize = 16f
            setPadding(pad, pad, pad, pad)
          })
      return
    }
    val list = ListView(this)
    list.adapter =
        ArrayAdapter(this, android.R.layout.simple_list_item_1, lights.map { it.second })
    list.setOnItemClickListener { _, _, position, _ ->
      prefs.edit().putInt(OneLightWidget.addrKey(id), lights[position].first).apply()
      OneLightWidget.draw(this, AppWidgetManager.getInstance(this), id, prefs)
      setResult(RESULT_OK, result)
      finish()
    }
    setContentView(list)
  }
}
