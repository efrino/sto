package com.maj.sto_prep

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Identitas perangkat untuk pemasangan (pairing) NIK.
 *
 * Catatan penting: sejak Android 6 (Wi-Fi/Bluetooth) dan Android 10 (nomor
 * seri), aplikasi biasa tidak boleh membaca MAC address maupun serial number -
 * yang dikembalikan selalu 02:00:00:00:00:00. Karena itu identitas perangkat
 * memakai ANDROID_ID: tetap sama setelah restart maupun install ulang selama
 * APK ditandatangani kunci yang sama, dan berubah hanya saat factory reset.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "sto_prep/device"
    private val printerChannelName = "sto_prep/printer_vendor"

    private val vendorPrinter by lazy { VendorPrinter(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIdentity" -> result.success(identity())
                // Printer internal tersambung lewat Bluetooth; bila radionya
                // mati, operator tinggal diantar ke setelannya.
                "openBluetoothSettings" -> result.success(bukaSetelanBluetooth())
                else -> result.notImplemented()
            }
        }

        // Printer internal lewat service pabrikan. Semua method membalas
        // nilai biasa (bukan error) supaya sisi Dart bisa jatuh ke jalur
        // Bluetooth begitu ada yang tidak beres.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            printerChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "tersedia" -> result.success(vendorPrinter.tersedia())
                "sambung" -> result.success(vendorPrinter.sambung())
                "tersambung" -> result.success(vendorPrinter.tersambung())
                "putus" -> {
                    vendorPrinter.putus()
                    result.success(true)
                }
                "status" -> result.success(vendorPrinter.status())
                "cetakRaw" -> {
                    val data = call.argument<ByteArray>("data")
                    result.success(data != null && vendorPrinter.cetakRaw(data))
                }
                "cetakGambar" -> {
                    val data = call.argument<ByteArray>("data")
                    result.success(data != null && vendorPrinter.cetakGambar(data))
                }
                "majuBaris" -> {
                    val baris = call.argument<Int>("baris") ?: 1
                    result.success(vendorPrinter.majuBaris(baris))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        vendorPrinter.putus()
        super.onDestroy()
    }

    private fun bukaSetelanBluetooth(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        false
    }

    private fun identity(): Map<String, String> {
        val androidId = try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            null
        }

        val deviceName = try {
            Settings.Global.getString(contentResolver, "device_name")
                ?: Settings.Secure.getString(contentResolver, "bluetooth_name")
        } catch (e: Exception) {
            null
        }

        return mapOf(
            "device_id" to (androidId ?: ""),
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            "device_name" to (deviceName ?: Build.MODEL),
            "android" to Build.VERSION.RELEASE,
        )
    }
}
