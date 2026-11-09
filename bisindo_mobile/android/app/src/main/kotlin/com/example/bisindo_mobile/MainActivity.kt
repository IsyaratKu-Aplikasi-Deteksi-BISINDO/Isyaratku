
package com.example.bisindo_mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val CHANNEL = "bisindo/holistic"

    private var holisticLandmarker: HolisticLandmarker? = null

    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Simpan satu frame untuk pemeriksaan orientasi.
    private var debugFrameSaved = false

    companion object {
        private const val TARGET_WIDTH = 640
        private const val TARGET_HEIGHT = 360

        // Rotasi sementara untuk pengujian.
        private const val TEST_ROTATION = 0

        private const val TAG = "BISINDO_CAMERA"

        // Dimensi fitur model BISINDO.
        private const val BODY_FEATURES = 24
        private const val HAND_FEATURES = 42
        private const val BODY_RIGHT_FEATURES = 66
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // =========================================
                // INITIALIZE MEDIAPIPE
                // =========================================
                "initializeHolistic" -> {
                    inferenceExecutor.execute {
                        try {
                            if (holisticLandmarker == null) {
                                val baseOptions = BaseOptions.builder()
                                    .setModelAssetPath("holistic_landmarker.task")
                                    .build()

                                val options =
                                    HolisticLandmarker.HolisticLandmarkerOptions.builder()
                                        .setBaseOptions(baseOptions)
                                        .setRunningMode(RunningMode.IMAGE)
                                        .setMinFaceDetectionConfidence(0.5f)
                                        .setMinPoseDetectionConfidence(0.5f)
                                        .build()

                                holisticLandmarker =
                                    HolisticLandmarker.createFromOptions(
                                        this,
                                        options
                                    )
                            }

                            mainHandler.post {
                                result.success(
                                    "MediaPipe berhasil diinisialisasi"
                                )
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "MEDIAPIPE_INIT_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }
                    }
                }

                // =========================================
                // PROCESS CAMERA FRAME
                // =========================================
                "processFrame" -> {

                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")

                    val yBytes = call.argument<ByteArray>("y")
                    val uBytes = call.argument<ByteArray>("u")
                    val vBytes = call.argument<ByteArray>("v")

                    val yRowStride = call.argument<Int>("yRowStride")
                    val uRowStride = call.argument<Int>("uRowStride")
                    val vRowStride = call.argument<Int>("vRowStride")

                    val yPixelStride = call.argument<Int>("yPixelStride")
                    val uPixelStride = call.argument<Int>("uPixelStride")
                    val vPixelStride = call.argument<Int>("vPixelStride")

                    val rotationFromCamera =
                        call.argument<Int>("rotation") ?: 0

                    if (
                        width == null || height == null ||
                        yBytes == null || uBytes == null || vBytes == null ||
                        yRowStride == null || uRowStride == null ||
                        vRowStride == null || yPixelStride == null ||
                        uPixelStride == null || vPixelStride == null
                    ) {
                        result.error(
                            "INVALID_FRAME",
                            "Data frame kamera tidak lengkap",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    inferenceExecutor.execute {

                        var bitmap: Bitmap? = null

                        try {
                            val landmarker = holisticLandmarker
                                ?: throw IllegalStateException(
                                    "MediaPipe belum diinisialisasi"
                                )

                            // =================================
                            // 1. CONVERT YUV TO NV21
                            // =================================
                            val nv21 = yuv420ToNv21(
                                width,
                                height,
                                yBytes,
                                uBytes,
                                vBytes,
                                yRowStride,
                                uRowStride,
                                vRowStride,
                                yPixelStride,
                                uPixelStride,
                                vPixelStride
                            )

                            // =================================
                            // 2. CONVERT NV21 TO JPEG
                            // =================================
                            val output = ByteArrayOutputStream()

                            val yuvImage = YuvImage(
                                nv21,
                                ImageFormat.NV21,
                                width,
                                height,
                                null
                            )

                            val compressed = yuvImage.compressToJpeg(
                                Rect(0, 0, width, height),
                                85,
                                output
                            )

                            if (!compressed) {
                                throw IllegalStateException(
                                    "Gagal mengubah frame menjadi JPEG"
                                )
                            }

                            // =================================
                            // 3. DECODE JPEG TO BITMAP
                            // =================================
                            val decodedBitmap =
                                BitmapFactory.decodeByteArray(
                                    output.toByteArray(),
                                    0,
                                    output.size()
                                ) ?: throw IllegalStateException(
                                    "Gagal membaca gambar kamera"
                                )

                            Log.d(
                                TAG,
                                "Bitmap sebelum resize: " +
                                    "${decodedBitmap.width} x ${decodedBitmap.height}"
                            )

                            bitmap = decodedBitmap

                            // =================================
                            // 4. SAVE DEBUG IMAGE BEFORE RESIZE
                            // =================================
                            val picturesDir =
                                getExternalFilesDir(
                                    Environment.DIRECTORY_PICTURES
                                ) ?: throw IllegalStateException(
                                    "Folder penyimpanan tidak tersedia"
                                )

                            val debugDir = File(
                                picturesDir,
                                "bisindo_debug"
                            )

                            if (!debugDir.exists() && !debugDir.mkdirs()) {
                                throw IllegalStateException(
                                    "Gagal membuat folder debug"
                                )
                            }

                            if (!debugFrameSaved) {
                                val debugFile = File(
                                    debugDir,
                                    "frame_before_resize.jpg"
                                )

                                FileOutputStream(debugFile).use { stream ->
                                    val saved = decodedBitmap.compress(
                                        Bitmap.CompressFormat.JPEG,
                                        95,
                                        stream
                                    )

                                    if (!saved) {
                                        throw IllegalStateException(
                                            "Gagal menyimpan gambar debug"
                                        )
                                    }
                                }

                                debugFrameSaved = true

                                Log.d(
                                    TAG,
                                    "DEBUG IMAGE: ${debugFile.absolutePath}"
                                )
                            }

                            // =================================
                            // 5. RESIZE TO 640 x 360
                            // =================================
                            val resizedBitmap = Bitmap.createScaledBitmap(
                                decodedBitmap,
                                TARGET_WIDTH,
                                TARGET_HEIGHT,
                                true
                            )

                            if (resizedBitmap !== decodedBitmap) {
                                decodedBitmap.recycle()
                            }

                            bitmap = resizedBitmap

                            Log.d(
                                TAG,
                                "Input MediaPipe: " +
                                    "${resizedBitmap.width} x ${resizedBitmap.height}"
                            )

                            // =================================
                            // 6. SAVE DEBUG IMAGE AFTER RESIZE
                            // =================================
                            val resizedDebugFile = File(
                                debugDir,
                                "frame_after_resize.jpg"
                            )

                            if (!resizedDebugFile.exists()) {
                                FileOutputStream(resizedDebugFile).use { stream ->
                                    val saved = resizedBitmap.compress(
                                        Bitmap.CompressFormat.JPEG,
                                        95,
                                        stream
                                    )

                                    if (!saved) {
                                        throw IllegalStateException(
                                            "Gagal menyimpan gambar setelah resize"
                                        )
                                    }
                                }

                                Log.d(
                                    TAG,
                                    "DEBUG AFTER RESIZE: ${resizedDebugFile.absolutePath}"
                                )
                            }

                            // =================================
                            // 7. MEDIAPIPE IMAGE
                            // =================================
                            val mpImage =
                                BitmapImageBuilder(resizedBitmap).build()

                            val imageOptions =
                                ImageProcessingOptions.builder()
                                    .setRotationDegrees(TEST_ROTATION)
                                    .build()

                            Log.d(
                                TAG,
                                "Rotation dari Flutter: $rotationFromCamera"
                            )

                            Log.d(
                                TAG,
                                "Rotation MediaPipe yang dipakai: $TEST_ROTATION"
                            )

                            // =================================
                            // 8. MEDIAPIPE DETECTION
                            // =================================
                            val detection = landmarker.detect(
                                mpImage,
                                imageOptions
                            )

                            val pose = detection.poseLandmarks()

                            Log.d(
                                TAG,
                                "Jumlah Pose Landmarks: ${pose.size}"
                            )

                            // =================================
                            // 9. DEBUG POSISI LANDMARK
                            // =================================
                            if (pose.size >= 25) {

                                val debugPoints = listOf(
                                    "Nose" to 0,
                                    "Right Shoulder" to 11,
                                    "Left Shoulder" to 12,
                                    "Right Hip" to 23,
                                    "Left Hip" to 24
                                )

                                Log.d(
                                    TAG,
                                    "========== DEBUG LANDMARK =========="
                                )

                                for ((name, index) in debugPoints) {
                                    val point = pose[index]

                                    Log.d(
                                        TAG,
                                        "$name: X=${point.x()}, Y=${point.y()}"
                                    )
                                }

                                val shoulderCenterX =
                                    (pose[11].x() + pose[12].x()) / 2f

                                val shoulderCenterY =
                                    (pose[11].y() + pose[12].y()) / 2f

                                val hipCenterX =
                                    (pose[23].x() + pose[24].x()) / 2f

                                val hipCenterY =
                                    (pose[23].y() + pose[24].y()) / 2f

                                Log.d(
                                    TAG,
                                    "========== BODY ORIENTATION =========="
                                )

                                Log.d(
                                    TAG,
                                    "Shoulder Center: X=$shoulderCenterX, Y=$shoulderCenterY"
                                )

                                Log.d(
                                    TAG,
                                    "Hip Center: X=$hipCenterX, Y=$hipCenterY"
                                )

                                Log.d(
                                    TAG,
                                    "Head-to-Hip Delta X: ${pose[0].x() - hipCenterX}"
                                )

                                Log.d(
                                    TAG,
                                    "Head-to-Hip Delta Y: ${pose[0].y() - hipCenterY}"
                                )

                                Log.d(
                                    TAG,
                                    "======================================"
                                )
                            } else {
                                Log.w(
                                    TAG,
                                    "Pose landmarks tidak lengkap: ${pose.size}"
                                )
                            }

                            val leftHand = detection.leftHandLandmarks()
                            val rightHand = detection.rightHandLandmarks()

                            // =================================
                            // 10. EXTRACT COORDINATES
                            // =================================
                            val bodyCoordinates =
                                extractBodyCoordinates(pose)

                            val leftHandDetected = leftHand.size >= 21
                            val rightHandDetected = rightHand.size >= 21

                            val leftHandCoordinates =
                                extractHandCoordinates(leftHand)

                            val rightHandCoordinates =
                                extractHandCoordinates(rightHand)

                            // =================================
                            // 11. SELECT BODY + RIGHT HAND (66D)
                            // =================================
                            val bodyRightCoordinates =
                                bodyCoordinates + rightHandCoordinates

                            // Validasi jumlah fitur Body-Right.
                            if (
                                bodyCoordinates.size != BODY_FEATURES ||
                                rightHandCoordinates.size != HAND_FEATURES ||
                                bodyRightCoordinates.size != BODY_RIGHT_FEATURES
                            ) {
                                throw IllegalStateException(
                                    "Jumlah fitur tidak sesuai. " +
                                        "Body=${bodyCoordinates.size}, " +
                                        "RightHand=${rightHandCoordinates.size}, " +
                                        "BodyRight=${bodyRightCoordinates.size}"
                                )
                            }

                            Log.d(
                                TAG,
                                "Body-Right Feature Count: ${bodyRightCoordinates.size}"
                            )

                            // =================================
                            // 12. RESPONSE TO FLUTTER
                            // =================================
                            val response = mapOf(
                                "pose" to pose.size,
                                "leftHand" to leftHand.size,
                                "rightHand" to rightHand.size,

                                "leftHandDetected" to leftHandDetected,
                                "rightHandDetected" to rightHandDetected,

                                "bodyCoordinates" to bodyCoordinates,
                                "leftHandCoordinates" to leftHandCoordinates,
                                "rightHandCoordinates" to rightHandCoordinates,

                                // Fitur utama untuk model BISINDO.
                                "bodyRightCoordinates" to bodyRightCoordinates,
                                "featureCount" to bodyRightCoordinates.size
                            )

                            mainHandler.post {
                                result.success(response)
                            }

                        } catch (e: Exception) {
                            Log.e(
                                TAG,
                                "ERROR PROCESS FRAME",
                                e
                            )

                            mainHandler.post {
                                result.error(
                                    "FRAME_PROCESSING_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        } finally {
                            bitmap?.recycle()
                        }
                    }
                }

                // =========================================
                // CLOSE MEDIAPIPE
                // =========================================
                "closeHolistic" -> {
                    inferenceExecutor.execute {
                        try {
                            holisticLandmarker?.close()
                            holisticLandmarker = null

                            mainHandler.post {
                                result.success("MediaPipe ditutup")
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "MEDIAPIPE_CLOSE_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // =============================================
    // BODY LANDMARKS (24D)
    // =============================================
    private fun extractBodyCoordinates(
        pose: List<NormalizedLandmark>
    ): List<Float> {

        val coordinates = mutableListOf<Float>()

        fun addBodyPoint(index: Int) {
            if (index < pose.size) {
                coordinates.add(pose[index].x())
                coordinates.add(pose[index].y())
            } else {
                coordinates.add(0f)
                coordinates.add(0f)
            }
        }

        // Nose
        addBodyPoint(0)

        // Neck
        if (pose.size > 12) {
            val neckX = (pose[12].x() + pose[11].x()) / 2f
            val neckY = (pose[12].y() + pose[11].y()) / 2f

            coordinates.add(neckX)
            coordinates.add(neckY)
        } else {
            coordinates.add(0f)
            coordinates.add(0f)
        }

        // Body map
        listOf(
            5, 2, 8, 7, 12, 11, 14, 13, 16, 15
        ).forEach { index ->
            addBodyPoint(index)
        }

        return coordinates
    }

    // =============================================
    // HAND LANDMARKS (42D)
    // =============================================
    private fun extractHandCoordinates(
        landmarks: List<NormalizedLandmark>
    ): List<Float> {

        if (landmarks.size < 21) {
            return List(42) { 0f }
        }

        val handMap = listOf(
            0, 8, 7, 6, 5,
            12, 11, 10, 9,
            16, 15, 14, 13,
            20, 19, 18, 17,
            4, 3, 2, 1
        )

        return handMap.flatMap { index ->
            listOf(
                landmarks[index].x(),
                landmarks[index].y()
            )
        }
    }

    // =============================================
    // CONVERT YUV420 TO NV21
    // =============================================
    private fun yuv420ToNv21(
        width: Int,
        height: Int,
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        yPixelStride: Int,
        uPixelStride: Int,
        vPixelStride: Int
    ): ByteArray {

        require(width % 2 == 0 && height % 2 == 0) {
            "Ukuran frame harus genap"
        }

        val frameSize = width * height
        val nv21 = ByteArray(frameSize + frameSize / 2)

        // Y CHANNEL
        for (row in 0 until height) {
            for (col in 0 until width) {
                val index =
                    row * yRowStride + col * yPixelStride

                require(index < yBytes.size) {
                    "Data Y tidak lengkap"
                }

                nv21[row * width + col] = yBytes[index]
            }
        }

        // UV CHANNEL
        var outputIndex = frameSize

        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {

                val uIndex =
                    row * uRowStride + col * uPixelStride

                val vIndex =
                    row * vRowStride + col * vPixelStride

                require(
                    uIndex < uBytes.size &&
                    vIndex < vBytes.size
                ) {
                    "Data UV tidak lengkap"
                }

                nv21[outputIndex++] = vBytes[vIndex]
                nv21[outputIndex++] = uBytes[uIndex]
            }
        }

        return nv21
    }

    // =============================================
    // DESTROY
    // =============================================
    override fun onDestroy() {

        inferenceExecutor.execute {
            holisticLandmarker?.close()
            holisticLandmarker = null
        }

        inferenceExecutor.shutdown()

        super.onDestroy()
    }
}
