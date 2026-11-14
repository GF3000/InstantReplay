package io.github.instantreplay.replay_capture_android.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import io.github.instantreplay.replay_capture_android.broadcast.Scoreboard

/**
 * A text badge drawn top-right over the program, e.g. `REPETICIÓN` during a replay on air
 * (SPEC §12.6). [text] and [plate] may be set from any thread; [draw] runs on the GL thread and
 * uploads the bitmap only when one of them changed. Sized for a [referenceHeight]-high frame like
 * the scoreboard. Classic: a red box. [plate] (follows the scoreboard style): the dark plate with
 * a red border, a red dot and the text in IBM Plex Mono.
 */
internal class LabelRenderer(private val referenceHeight: Int, fonts: OverlayFonts) {
    @Volatile var text: String? = null
    @Volatile var plate = false

    private val renderer = TextureRenderer(external = false)
    private val texture = TextureRenderer.create2dTexture(1, 1)
    private var uploaded: String? = null
    private var uploadedPlate = false
    private var textureWidth = 0
    private var textureHeight = 0
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        color = 0xFFFFFFFF.toInt()
        textAlign = Paint.Align.CENTER
    }
    private val fill = Paint().apply { color = BACKGROUND }
    private val platePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = fonts.mono
        color = PLATE_TEXT
        letterSpacing = 0.08f
    }
    private val plateFill = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Draws the badge into the current target of [frameWidth]×[frameHeight]; nothing without text. */
    fun draw(frameWidth: Int, frameHeight: Int) {
        val t = text ?: return
        val p = plate
        if (t != uploaded || p != uploadedPlate) upload(t, p)
        if (textureWidth == 0) return
        val height = Scoreboard.barHeight(frameHeight)
        val width = textureWidth * height / textureHeight
        val x = frameWidth - Scoreboard.margin(frameWidth) - width
        val y = frameHeight - Scoreboard.margin(frameHeight) - height
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        renderer.draw(texture, x, y, width, height, FLIP_Y)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        renderer.release()
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
    }

    private fun upload(t: String, plate: Boolean) {
        val height = Scoreboard.barHeight(referenceHeight)
        val bitmap = if (plate) renderPlate(t, height) else renderClassic(t, height)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        textureWidth = bitmap.width
        textureHeight = bitmap.height
        bitmap.recycle()
        uploaded = t
        uploadedPlate = plate
    }

    private fun renderClassic(t: String, height: Int): Bitmap {
        paint.textSize = height * Scoreboard.TEXT_SIZE
        val width = (paint.measureText(t) + height * 0.8f).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fill)
        val m = paint.fontMetrics
        canvas.drawText(t, width / 2f, height / 2f - (m.ascent + m.descent) / 2, paint)
        return bitmap
    }

    /** Prototype "Placa": padding 0.38 h, dot 0.24 h, gap 0.24 h, text 0.4 h (17 px on a 42 px badge). */
    private fun renderPlate(t: String, height: Int): Bitmap {
        val h = height.toFloat()
        platePaint.textSize = h * 0.4f
        val pad = h * 0.38f
        val dot = h * 0.24f
        val gap = h * 0.24f
        val width = kotlin.math.ceil(pad + dot + gap + platePaint.measureText(t) + pad).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val w = width.toFloat()
        val border = maxOf(1f, kotlin.math.round(h / 42f))
        val radius = h * 0.07f
        plateFill.style = Paint.Style.FILL
        plateFill.color = PLATE_BACKGROUND
        canvas.drawRoundRect(RectF(0f, 0f, w, h), radius, radius, plateFill)
        plateFill.color = RED
        canvas.drawCircle(pad + dot / 2, h / 2, dot / 2, plateFill)
        val m = platePaint.fontMetrics
        canvas.drawText(t, pad + dot + gap, h / 2 - (m.ascent + m.descent) / 2, platePaint)
        plateFill.style = Paint.Style.STROKE
        plateFill.strokeWidth = border
        canvas.drawRoundRect(RectF(border / 2, border / 2, w - border / 2, h - border / 2), radius, radius, plateFill)
        return bitmap
    }

    private companion object {
        /** Broadcast red, opaque enough to read over any picture. */
        const val BACKGROUND = 0xE6C62828.toInt()

        // Plate badge: rgba(15,16,18,.93) with a #FF453A border and dot.
        const val PLATE_BACKGROUND = 0xED0F1012.toInt()
        const val PLATE_TEXT = 0xFFECEDEF.toInt()
        const val RED = 0xFFFF453A.toInt()

        val FLIP_Y = FloatArray(16).also {
            Matrix.setIdentityM(it, 0)
            Matrix.translateM(it, 0, 0f, 1f, 0f)
            Matrix.scaleM(it, 0, 1f, -1f, 1f)
        }
    }
}
