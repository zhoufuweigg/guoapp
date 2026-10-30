package com.duanju.duanju_app

import android.app.Activity
import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class TextInputBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "duanju/text_input")
    private val keyboard = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    private var input: HiddenInput? = null
    private var editing = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    start(call.argument<String>("text").orEmpty())
                    result.success(null)
                }
                "stop" -> {
                    finish(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun view(): HiddenInput = input ?: HiddenInput(activity).also { view ->
        view.alpha = 0f
        view.background = null
        view.isCursorVisible = false
        view.isSingleLine = true
        view.imeOptions = EditorInfo.IME_ACTION_SEARCH or
            EditorInfo.IME_FLAG_NO_EXTRACT_UI or
            EditorInfo.IME_FLAG_NO_FULLSCREEN
        view.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (editing) channel.invokeMethod("changed", s?.toString().orEmpty())
            }
        })
        view.setOnEditorActionListener { _, action, _ ->
            val submit = action == EditorInfo.IME_ACTION_SEARCH ||
                action == EditorInfo.IME_ACTION_DONE ||
                action == EditorInfo.IME_ACTION_GO
            if (submit) finish(true)
            submit
        }
        view.setOnFocusChangeListener { _, focused -> if (!focused) finish(false) }
        view.onBack = { finish(false) }
        activity.addContentView(view, FrameLayout.LayoutParams(1, 1))
        input = view
    }

    private fun start(text: String) {
        val view = view()
        editing = false
        view.setText(text)
        view.setSelection(text.length)
        editing = true
        view.requestFocus()
        keyboard.showSoftInput(view, 0)
    }

    private fun finish(submit: Boolean) {
        if (!editing) return
        editing = false
        val view = input ?: return
        keyboard.hideSoftInputFromWindow(view.windowToken, 0)
        channel.invokeMethod("done", mapOf("text" to view.text.toString(), "submit" to submit))
        activity.findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID)?.requestFocus()
    }

    fun dispose() {
        finish(false)
        channel.setMethodCallHandler(null)
        input?.let { (it.parent as? ViewGroup)?.removeView(it) }
        input = null
    }
}

private class HiddenInput(context: Context) : EditText(context) {
    var onBack: (() -> Unit)? = null

    override fun onKeyPreIme(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode != KeyEvent.KEYCODE_BACK) return super.onKeyPreIme(keyCode, event)
        if (event.action == KeyEvent.ACTION_UP) onBack?.invoke()
        return true
    }
}
