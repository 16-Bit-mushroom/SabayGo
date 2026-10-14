package com.sabaygo.edge.bench

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.TensorBuffer
import kotlin.math.max
import kotlin.math.min

/** The four ways of running the model that the benchmark compares. */
enum class Backend(val label: String) {
    CPU_FP32("cpu-fp32"),
    CPU_FP16("cpu-fp16"),
    GPU_FP16("gpu-fp16"),
    GPU_FP32("gpu-fp32");

    val usesThreads get() = this == CPU_FP32 || this == CPU_FP16
}

class Result(
    val preprocessMs: Double,
    val inferenceMs: Double,
    val postprocessMs: Double,
    val persons: Int,
)

/**
 * YOLOv8n person count on one camera frame, by the rule in
 * ai_service/inference.py: an anchor is a person when its best class is
 * person and that score is at least [CONF]; overlapping boxes merge by NMS
 * at [IOU]. Same thresholds, so the phone and the AI node count alike.
 *
 * The model is the one tools/export_models.sh writes (litert-torch, FP32):
 * input NCHW [1, 3, S, S], RGB scaled 0..1, letterboxed with grey 114 as
 * Ultralytics does; output [1, 84, A] (box centre and size divided by S,
 * then 80 class scores), A = anchors over strides 8, 16 and 32.
 *
 * Timing: preprocess is the frame to input array (rotate, letterbox,
 * convert); inference is input upload + run + output read, because the
 * count cannot start before the output is back on the CPU; postprocess
 * is the person filter and NMS.
 */
class Detector(
    assets: AssetManager,
    val assetPath: String,
    val backend: Backend,
    val threads: Int,
) : AutoCloseable {

    val inputPx: Int = Regex("_(\\d+)\\.tflite$").find(assetPath)?.groupValues?.get(1)?.toInt()
        ?: error("model name must end _<size>.tflite: $assetPath")
    private val anchors = listOf(8, 16, 32).sumOf { (inputPx / it) * (inputPx / it) }

    private val model = CompiledModel.create(assets, assetPath, options())
    private val inputs: List<TensorBuffer> = model.createInputBuffers()
    private val outputs: List<TensorBuffer> = model.createOutputBuffers()

    private val letterboxed = Bitmap.createBitmap(inputPx, inputPx, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(letterboxed)
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val matrix = Matrix()
    private val pixels = IntArray(inputPx * inputPx)
    private val chw = FloatArray(3 * inputPx * inputPx)

    private fun options(): CompiledModel.Options = when (backend) {
        Backend.CPU_FP32 -> CompiledModel.Options(Accelerator.CPU).apply {
            cpuOptions = CompiledModel.CpuOptions(numThreads = threads)
        }
        Backend.CPU_FP16 -> CompiledModel.Options(Accelerator.CPU).apply {
            cpuOptions = CompiledModel.CpuOptions(numThreads = threads, xnnPackFlags = XNNPACK_FORCE_FP16)
        }
        Backend.GPU_FP16 -> CompiledModel.Options(Accelerator.GPU).apply {
            gpuOptions = CompiledModel.GpuOptions(precision = CompiledModel.GpuOptions.Precision.FP16)
        }
        Backend.GPU_FP32 -> CompiledModel.Options(Accelerator.GPU).apply {
            gpuOptions = CompiledModel.GpuOptions(precision = CompiledModel.GpuOptions.Precision.FP32)
        }
    }

    fun count(frame: Bitmap, rotationDegrees: Int): Result {
        val t0 = System.nanoTime()
        toInput(frame, rotationDegrees)
        val t1 = System.nanoTime()
        inputs[0].writeFloat(chw)
        model.run(inputs, outputs)
        val out = outputs[0].readFloat()
        val t2 = System.nanoTime()
        check(out.size == ROWS * anchors) { "output has ${out.size} values, expected $ROWS x $anchors" }
        val persons = countPersons(out)
        val t3 = System.nanoTime()
        return Result(ms(t1 - t0), ms(t2 - t1), ms(t3 - t2), persons)
    }

    /** Rotate upright, scale to fit S x S keeping the aspect, centre on grey. */
    private fun toInput(frame: Bitmap, rotationDegrees: Int) {
        val sideways = rotationDegrees % 180 != 0
        val w = if (sideways) frame.height else frame.width
        val h = if (sideways) frame.width else frame.height
        val scale = min(inputPx.toFloat() / w, inputPx.toFloat() / h)
        matrix.reset()
        matrix.postTranslate(-frame.width / 2f, -frame.height / 2f)
        matrix.postRotate(rotationDegrees.toFloat())
        matrix.postScale(scale, scale)
        matrix.postTranslate(inputPx / 2f, inputPx / 2f)
        canvas.drawColor(LETTERBOX_GREY)
        canvas.drawBitmap(frame, matrix, paint)

        letterboxed.getPixels(pixels, 0, inputPx, 0, 0, inputPx, inputPx)
        val plane = pixels.size
        for (i in 0 until plane) {
            val p = pixels[i]
            chw[i] = ((p shr 16) and 0xFF) / 255f
            chw[plane + i] = ((p shr 8) and 0xFF) / 255f
            chw[2 * plane + i] = (p and 0xFF) / 255f
        }
    }

    private fun countPersons(out: FloatArray): Int {
        val a = anchors
        val boxes = ArrayList<FloatArray>()
        for (i in 0 until a) {
            val person = out[4 * a + i]
            if (person < CONF) continue
            // Ultralytics keeps an anchor's best class only; a tie goes to person.
            var best = true
            for (c in 1 until CLASSES) if (out[(4 + c) * a + i] > person) { best = false; break }
            if (!best) continue
            val cx = out[i]; val cy = out[a + i]; val bw = out[2 * a + i]; val bh = out[3 * a + i]
            boxes += floatArrayOf(cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2, person)
        }
        boxes.sortByDescending { it[4] }
        val kept = ArrayList<FloatArray>()
        for (b in boxes) if (kept.none { iou(it, b) > IOU }) kept += b
        return kept.size
    }

    override fun close() {
        inputs.forEach { it.close() }
        outputs.forEach { it.close() }
        model.close()
    }

    private companion object {
        const val CONF = 0.45f   // ai_service/inference.py AI_NODE_CONF
        const val IOU = 0.50f    // ai_service/inference.py AI_NODE_IOU
        const val CLASSES = 80
        const val ROWS = 4 + CLASSES
        val LETTERBOX_GREY = Color.rgb(114, 114, 114)
        // TFLITE_XNNPACK_DELEGATE_FLAG_FORCE_FP16: FP16 arithmetic on ARMv8.2
        // cores (the A76 and A55 both have it), the CPU's FP16 path.
        const val XNNPACK_FORCE_FP16 = 0x4

        fun ms(nanos: Long) = nanos / 1e6

        fun iou(a: FloatArray, b: FloatArray): Float {
            val iw = max(0f, min(a[2], b[2]) - max(a[0], b[0]))
            val ih = max(0f, min(a[3], b[3]) - max(a[1], b[1]))
            val inter = iw * ih
            val union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
            return if (union <= 0f) 0f else inter / union
        }
    }
}
