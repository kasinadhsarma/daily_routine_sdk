package com.kasinadhsarma.dailyroutine.daily_routine_sdk

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Full-screen interstitial shown in place of a blocked app. Finishing this
 * activity returns the user to the home screen rather than back to the
 * blocked app.
 */
class BlockScreenActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blockedPackage"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )

        val blockedPackage = intent.getStringExtra(EXTRA_BLOCKED_PACKAGE) ?: ""

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#1A1B22"))
            setPadding(64, 64, 64, 64)
        }

        val title = TextView(this).apply {
            text = "This app is blocked right now"
            textSize = 22f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = "$blockedPackage is off-limits during your current routine task."
            textSize = 14f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 48)
        }
        val homeButton = Button(this).apply {
            text = "Back to Home"
            setOnClickListener { goHome() }
        }

        root.addView(title)
        root.addView(subtitle)
        root.addView(homeButton)
        setContentView(root)
    }

    override fun onBackPressed() {
        goHome()
    }

    private fun goHome() {
        val homeIntent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
            addCategory(android.content.Intent.CATEGORY_HOME)
            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(homeIntent)
        finish()
    }
}
