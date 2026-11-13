package io.github.instantreplay.replay_capture_android.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import io.github.instantreplay.replay_capture_android.broadcast.BarLayout
import io.github.instantreplay.replay_capture_android.broadcast.CellKind
import io.github.instantreplay.replay_capture_android.broadcast.PlateFont
import io.github.instantreplay.replay_capture_android.broadcast.PlateLayout
import io.github.instantreplay.replay_capture_android.broadcast.Scoreboard
import io.github.instantreplay.replay_capture_android.broadcast.ScoreboardState
import io.github.instantreplay.replay_capture_android.broadcast.ScoreboardText

/**
 * The scoreboard overlay (SPEC §12.1): drawn with [Canvas] into a bitmap only when its text
 * changes (at most once per second while the clock runs), uploaded as a 2D texture and drawn as
 * an alpha-blended quad top-left on every frame. Two styles: the classic one-row bar and the
 * two-row plate ([ScoreboardState.plate]) drawn with the bundled IBM Plex [fonts].
 *
 * [set] may be called from any thread; everything else runs on the GL thread with a current
 * context. The bitmap is sized for a [referenceHeight]-high frame (the program); smaller targets
 * (the 720p handoff) scale the same texture down.
 */
internal class OverlayRenderer(private val referenceHeight: Int, fonts: OverlayFonts) {
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
    private val plateFill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val plateName = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = fonts.condensed
        color = PLATE_TEXT
        letterSpacing = 0.1f
    }
    private val plateMono = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = fonts.mono }
    private val platePeriod = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = fonts.condensed
        color = PLATE_MUTED
        letterSpacing = 0.08f
        textAlign = Paint.Align.CENTER
    }

    /** The last state asked for the plate style (the replay badge follows it). */
    val plate: Boolean get() = received?.state?.plate == true

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

    /** Draws the board top-left with a safe margin into the current target of [frameWidth]×[frameHeight]. */
    fun draw(frameWidth: Int, frameHeight: Int) {
        if (textureWidth == 0) return
        val height = if (shown?.plate == true) {
            maxOf(1, Math.round(textureHeight.toFloat() * frameHeight / referenceHeight))
        } else {
            Scoreboard.barHeight(frameHeight, shown?.scalePercent ?: 100)
        }
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
        val bitmap = if (text.plate) {
            val row = Scoreboard.plateRow(referenceHeight, text.scalePercent)
            plateName.textSize = row * Scoreboard.PLATE_NAME_SIZE
            plateMono.textSize = row * Scoreboard.PLATE_MONO_SIZE
            platePeriod.textSize = row * Scoreboard.PLATE_PERIOD_SIZE
            renderPlate(text, Scoreboard.plateLayout(text, row, ::measurePlate))
        } else {
            val height = Scoreboard.barHeight(referenceHeight, text.scalePercent)
            paint.textSize = height * Scoreboard.TEXT_SIZE
            render(Scoreboard.layout(text, height, paint::measureText))
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        textureWidth = bitmap.width
        textureHeight = bitmap.height
        bitmap.recycle()
    }

    private fun measurePlate(font: PlateFont, s: String) = when (font) {
        PlateFont.NAME -> plateName.measureText(s)
        PlateFont.MONO -> plateMono.measureText(s)
        PlateFont.PERIOD -> platePeriod.measureText(s)
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

    /** The plate (prototype "Placa"): two rows (home, away) and a clock column spanning both. */
    private fun renderPlate(text: ScoreboardText, l: PlateLayout): Bitmap {
        val bitmap = Bitmap.createBitmap(l.width, l.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val w = l.width.toFloat()
        val h = l.height.toFloat()
        val b = l.border
        val f = plateFill
        f.style = Paint.Style.FILL
        f.color = PLATE_BACKGROUND
        canvas.drawRoundRect(RectF(0f, 0f, w, h), l.radius, l.radius, f)
        // Inner fills stay inside the border, so the rounded corners need no clipping.
        f.color = PLATE_SCORE_BACKGROUND
        canvas.drawRect(l.scoreX, b, l.dividerX, h - b, f)
        f.color = PLATE_ROW_DIVIDER
        canvas.drawRect(b, l.row - b / 2, l.dividerX, l.row + b / 2, f)
        f.color = PLATE_LINE
        canvas.drawRect(l.dividerX, b, l.clockX, h - b, f)

        val nameMetrics = plateName.fontMetrics
        val monoMetrics = plateMono.fontMetrics
        plateMono.textAlign = Paint.Align.RIGHT
        plateMono.color = PLATE_TEXT
        val rows = listOf(
            Triple(text.homeName, text.homeScore, text.homeColor),
            Triple(text.awayName, text.awayScore, text.awayColor),
        )
        rows.forEachIndexed { i, (name, score, color) ->
            val center = l.row * i + l.row / 2
            f.color = color or OPAQUE
            canvas.drawRect(
                l.stripeX, center - l.stripeHeight / 2, l.stripeX + l.stripeWidth, center + l.stripeHeight / 2, f,
            )
            canvas.drawText(name, l.nameX, center - (nameMetrics.ascent + nameMetrics.descent) / 2, plateName)
            canvas.drawText(
                score,
                l.dividerX - l.scorePad,
                center - (monoMetrics.ascent + monoMetrics.descent) / 2,
                plateMono,
            )
        }

        // Clock over period, centred as a group in the clock column.
        plateMono.textAlign = Paint.Align.CENTER
        plateMono.color = PLATE_CLOCK
        val clockX = l.clockX + l.clockWidth / 2
        if (text.period.isEmpty()) {
            canvas.drawText(text.clock, clockX, h / 2 - (monoMetrics.ascent + monoMetrics.descent) / 2, plateMono)
        } else {
            val periodMetrics = platePeriod.fontMetrics
            val clockHeight = monoMetrics.descent - monoMetrics.ascent
            val periodHeight = periodMetrics.descent - periodMetrics.ascent
            val top = (h - clockHeight - periodHeight) / 2
            canvas.drawText(text.clock, clockX, top - monoMetrics.ascent, plateMono)
            canvas.drawText(text.period, clockX, top + clockHeight - periodMetrics.ascent, platePeriod)
        }

        f.style = Paint.Style.STROKE
        f.strokeWidth = b
        f.color = PLATE_LINE
        canvas.drawRoundRect(RectF(b / 2, b / 2, w - b / 2, h - b / 2), l.radius, l.radius, f)
        return bitmap
    }

    private companion object {
        const val OPAQUE = 0xFF000000.toInt()
        const val TEXT = 0xFFFFFFFF.toInt()
        // Dark and mostly opaque: white text stays readable over sunlit grass.
        const val BACKGROUND = 0xD9101418.toInt()
        const val SCORE_BACKGROUND = 0x40FFFFFF
        const val CLOCK_BACKGROUND = 0x66000000

        // Plate: rgba(15,16,18,.93), white 14 % lines, white 10 % row divider, white 5 % scores.
        const val PLATE_BACKGROUND = 0xED0F1012.toInt()
        const val PLATE_LINE = 0x24FFFFFF
        const val PLATE_ROW_DIVIDER = 0x1AFFFFFF
        const val PLATE_SCORE_BACKGROUND = 0x0DFFFFFF
        const val PLATE_TEXT = 0xFFECEDEF.toInt()
        const val PLATE_MUTED = 0xFF9AA0A8.toInt()
        const val PLATE_CLOCK = 0xFFFFC107.toInt()

        /** Bitmap rows start at the top, GL texture rows at the bottom. */
        val FLIP_Y = FloatArray(16).also {
            Matrix.setIdentityM(it, 0)
            Matrix.translateM(it, 0, 0f, 1f, 0f)
            Matrix.scaleM(it, 0, 1f, -1f, 1f)
        }
    }
}
