package dev.bilisail.bilisail

import android.content.Intent
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var deviceOrientation: DeviceOrientationHandler? = null
    private var downloadStorage: DownloadStorageHandler? = null
    private var imageExport: ImageExportHandler? = null
    private var windowBrightness: WindowBrightnessHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceOrientation = DeviceOrientationHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        downloadStorage = DownloadStorageHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        imageExport = ImageExportHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        windowBrightness = WindowBrightnessHandler(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        deviceOrientation?.setResumed(true)
    }

    override fun onPause() {
        deviceOrientation?.setResumed(false)
        super.onPause()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        deviceOrientation?.configurationChanged()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        downloadStorage?.onActivityResult(requestCode)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        imageExport?.onPermissionResult(requestCode, grantResults)
        downloadStorage?.onPermissionResult(requestCode)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceOrientation?.close()
        deviceOrientation = null
        windowBrightness?.close()
        windowBrightness = null
        downloadStorage?.close()
        downloadStorage = null
        imageExport?.close()
        imageExport = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
