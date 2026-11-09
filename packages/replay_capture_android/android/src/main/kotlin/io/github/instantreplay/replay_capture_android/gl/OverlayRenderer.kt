package io.github.instantreplay.replay_capture_android.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import io.github.instantreplay.replay_capture_android.broadcast.BarLayout
import io.github.instantreplay.replay_capture_android.broadcast.CellKind
import io.github.instantreplay.replay_capture_android.broadcast.Scoreboard
import io.github.instantreplay.replay_capture_android.broadcast.ScoreboardState
import io.github.instantreplay.replay_capture_android.broadcast.ScoreboardText

/**
 * The scoreboard overlay (SPEC §12.1): drawn with [Canvas] into a bitmap only when its text
 * changes (at most once per second while the clock runs), uploaded as a 2D texture and drawn as
 * an alpha-blended quad top-left on every frame.
 *
 * [set] may be called from any thread; everything else runs on the GL thread with a current
 * context. The bitmap is sized for a [referenceHeight]-high frame (the program); smaller targets
 * (the 720p handoff) scale the same texture down.
 */
internal class OverlayRenderer(private val referenceHeight: Int) {
    private class Received(val state: ScoreboardState, val atNs: Long)

    @Volatile private var received: Received? = null

    private val renderer = TextureRenderer(external = false)
    private val texture = TextureRenderer.create2dTexture(1, 1)
    private var textureWidth = 0
    private var textureHeight = 0
    private var shown: ScoreboardText? = null
    private var shownFrom: Received? = null
    private var shownSecond = -1L
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        color = TEXT
        textAlign = Paint.Align.CENTER
    }
    private val fill = Paint()

    /** Replaces the state; a running clock advances from its value from now on. */
    fun set(state: ScoreboardState) {
        received = Received(state, System.nanoTime())
    }

    /**
     * Once per camera frame, before [draw]: refreshes the texture if the shown text changed.
     * Returns false when there is nothing to draw (no state yet, or hidden).
     */
    fun update(): Boolean {
        val r = received ?: return false
        if (!r.state.visible) return false
        val elapsedMs = (System.nanoTime() - r.atNs) / 1_000_000
        // Cheap check first: the text can only change with the state or the clock's second.
        val second = Scoreboard.clockMs(r.state, elapsedMs) / 1000
        if (r === shownFrom && second == shownSecond) return textureWidth > 0
        shownFrom = r
        shownSecond = second
        val text = Scoreboard.text(r.state, elapsedMs)
        if (text != shown) {
            upload(text)
            shown = text
        }
        return textureWidth > 0
    }

    /** Draws the bar top-left with a safe margin into the current target of [frameWidth]×[frameHeight]. */
    fun draw(frameWidth: Int, frameHeight: Int) {
        if (textureWidth == 0) return
        val height = Scoreboard.barHeight(frameHeight, shown?.scalePercent ?: 100)
        val width = textureWidth * height / textureHeight
        val x = Scoreboard.margin(frameWidth)
        val y = frameHeight - Scoreboard.margin(frameHeight) - height // GL origin is bottom-left
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA) // premultiplied bitmap
        renderer.draw(texture, x, y, width, height, FLIP_Y)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        renderer.release()
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
    }

    private fun upload(text: ScoreboardText) {
        val height = Scoreboard.barHeight(referenceHeight, text.scalePercent)
        paint.textSize = height * Scoreboard.TEXT_SIZE
        val layout = Scoreboard.layout(text, height, paint::measureText)
        val bitmap = render(layout)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        bitmap.recycle()
        textureWidth = layout.width
        textureHeight = layout.height
    }

    private fun render(layout: BarLayout): Bitmap {
        val bitmap = Bitmap.createBitmap(layout.width, layout.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val h = layout.height.toFloat()
        fill.color = BACKGROUND
        canvas.drawRect(0f, 0f, layout.width.toFloat(), h, fill)
        val metrics = paint.fontMetrics
        val baseline = h / 2 - (metrics.ascent + metrics.descent) / 2
        for (cell in layout.cells) {
            val cellBackground = when (cell.kind) {
                CellKind.STRIPE -> cell.color or OPAQUE
                CellKind.SCORE -> SCORE_BACKGROUND
                CellKind.CLOCK, CellKind.PERIOD -> CLOCK_BACKGROUND
                CellKind.NAME -> 0
            }
            if (cellBackground != 0) {
                fill.color = cellBackground
                canvas.drawRect(cell.x, 0f, cell.x + cell.width, h, fill)
            }
            if (cell.text.isNotEmpty()) canvas.drawText(cell.text, cell.x + cell.width / 2, baseline, paint)
        }
        return bitmap
    }

    private companion object {
        const val OPAQUE = 0xFF000000.toInt()
        const val TEXT = 0xFFFFFFFF.toInt()
        // Dark and mostly opaque: white text stays readable over sunlit grass.
        const val BACKGROUND = 0xD9101418.toInt()
        const val SCORE_BACKGROUND = 0x40FFFFFF
        const val CLOCK_BACKGROUND = 0x66000000

        /** Bitmap rows start at the top, GL texture rows at the bottom. */
        val FLIP_Y = FloatArray(16).also {
            Matrix.setIdentityM(it, 0)
            Matrix.translateM(it, 0, 0f, 1f, 0f)
            Matrix.scaleM(it, 0, 1f, -1f, 1f)
        }
    }
}
