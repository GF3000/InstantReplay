package io.github.instantreplay.replay_capture_android.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import io.github.instantreplay.replay_capture_android.broadcast.BoardPosition
import io.github.instantreplay.replay_capture_android.broadcast.BoardStyle
import io.github.instantreplay.replay_capture_android.broadcast.Scoreboard

/**
 * A text badge drawn top-right (top-left when [left]) over the program, e.g. `REPETICIÓN` during a
 * replay on air (SPEC §12.6). [text], [style] and [left] may be set from any thread; [draw] runs on
 * the GL thread and uploads the bitmap only when the text or style changed. Sized for a
 * [referenceHeight]-high frame like the scoreboard. It follows the scoreboard [style]: classic, a
 * red box; plate, the dark plate with a red border, a red dot and the text in IBM Plex Mono;
 * banner, the navy bar with red edges.
 */
internal class LabelRenderer(private val referenceHeight: Int, fonts: OverlayFonts) {
    @Volatile var text: String? = null
    @Volatile var style = BoardStyle.CLASSIC
    @Volatile var left = false

    private val renderer = TextureRenderer(external = false)
    private val texture = TextureRenderer.create2dTexture(1, 1)
    private var uploaded: String? = null
    private var uploadedStyle = BoardStyle.CLASSIC
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
    private val bannerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = fonts.mono
        color = 0xFFFFFFFF.toInt()
        letterSpacing = 0.08f
    }
    private val bannerFill = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Draws the badge into the current target of [frameWidth]×[frameHeight]; nothing without text. */
    fun draw(frameWidth: Int, frameHeight: Int) {
        val t = text ?: return
        val st = style
        if (t != uploaded || st != uploadedStyle) upload(t, st)
        if (textureWidth == 0) return
        val height = Scoreboard.barHeight(frameHeight)
        val width = textureWidth * height / textureHeight
        val corner = if (left) BoardPosition.TOP_LEFT else BoardPosition.TOP_RIGHT
        val x = Scoreboard.placeX(corner, frameWidth, width)
        val y = Scoreboard.placeY(corner, frameHeight, height)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        renderer.draw(texture, x, y, width, height, FLIP_Y)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        renderer.release()
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
    }

    private fun upload(t: String, style: BoardStyle) {
        val height = Scoreboard.barHeight(referenceHeight)
        val bitmap = when (style) {
            BoardStyle.CLASSIC -> renderClassic(t, height)
            BoardStyle.PLATE -> renderPlate(t, height)
            BoardStyle.BANNER -> renderBanner(t, height)
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        textureWidth = bitmap.width
        textureHeight = bitmap.height
        bitmap.recycle()
        uploaded = t
        uploadedStyle = style
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

    /** The banner's bar (same navy and proportions): red edges, the text in IBM Plex Mono. */
    private fun renderBanner(t: String, height: Int): Bitmap {
        val h = height.toFloat()
        bannerPaint.textSize = h * 0.42f
        val edge = h * Scoreboard.BANNER_EDGE
        val pad = h * 0.45f
        val width = kotlin.math.ceil(2 * (edge + pad) + bannerPaint.measureText(t)).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val bar = RectF(0f, 0f, width.toFloat(), h)
        val radius = h * Scoreboard.BANNER_RADIUS
        // Navy first, then the edges over it, as on the board: no seam where they meet.
        bannerFill.color = Scoreboard.BANNER_NAVY
        canvas.drawRoundRect(bar, radius, radius, bannerFill)
        canvas.clipPath(Path().apply { addRoundRect(bar, radius, radius, Path.Direction.CW) })
        bannerFill.color = RED
        canvas.drawRect(0f, 0f, edge, h, bannerFill)
        canvas.drawRect(bar.right - edge, 0f, bar.right, h, bannerFill)
        val m = bannerPaint.fontMetrics
        canvas.drawText(t, edge + pad, h / 2 - (m.ascent + m.descent) / 2, bannerPaint)
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
