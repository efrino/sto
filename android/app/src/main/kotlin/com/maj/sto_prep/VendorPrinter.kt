package com.maj.sto_prep

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import recieptservice.com.recieptservice.PrinterInterface

/**
 * Printer internal handheld lewat service pabrikan (SRPrinter).
 *
 * Printernya bukan perangkat Bluetooth: dia duduk di /dev/ttyS1 dan dibungkus
 * service sistem `recieptservice.com.recieptservice`. Jalur Bluetooth
 * "InnerPrinter" yang selama ini dipakai hanyalah jembatan SPP buatan
 * pabrikan - lewat jembatan itu aplikasi tidak pernah bisa tahu kertasnya
 * habis, dan itulah asal antrean cetak yang tertahan.
 *
 * Kelas ini sengaja tidak melempar keluar: setiap kegagalan dikembalikan
 * sebagai `false` / `null` supaya lapisan Dart bisa jatuh kembali ke jalur
 * Bluetooth tanpa mengorbankan pencetakan yang sedang berjalan.
 */
class VendorPrinter(private val context: Context) {

    companion object {
        const val PAKET = "recieptservice.com.recieptservice"
        private const val ACTION = "recieptservice.com.recieptservice.PRINTER_SERVICE"

        /** Balasan getStatus() dari service pabrikan. */
        const val STATUS_SIAP = 0
    }

    private var printer: PrinterInterface? = null
    private var mengikat = false

    private val koneksi = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            printer = PrinterInterface.Stub.asInterface(service)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            printer = null
            mengikat = false
        }
    }

    /** true bila service printer pabrikan memang terpasang di perangkat ini. */
    fun tersedia(): Boolean = try {
        context.packageManager.getPackageInfo(PAKET, 0)
        true
    } catch (e: Exception) {
        false
    }

    fun sambung(): Boolean {
        if (printer != null) return true
        if (!tersedia()) return false
        if (mengikat) return false

        return try {
            val intent = Intent().apply {
                `package` = PAKET
                action = ACTION
            }
            mengikat = context.bindService(intent, koneksi, Context.BIND_AUTO_CREATE)
            mengikat
        } catch (e: Exception) {
            mengikat = false
            false
        }
    }

    fun putus() {
        if (!mengikat) return
        try {
            context.unbindService(koneksi)
        } catch (e: Exception) {
            // service sudah lepas duluan - tidak ada yang perlu dibereskan
        }
        mengikat = false
        printer = null
    }

    fun tersambung(): Boolean = printer != null

    /**
     * Keadaan printer menurut driver pabrikan.
     *
     * Inilah alasan utama memakai jalur ini: statusnya datang dari driver,
     * bukan tebakan `DLE EOT` yang sering tidak dijawab lewat jembatan SPP.
     * null = tidak bisa ditanya.
     */
    fun status(): Int? = try {
        printer?.status
    } catch (e: Exception) {
        null
    }

    /** Mengirim byte ESC/POS apa adanya - dokumen tag dibentuk di sisi Dart. */
    fun cetakRaw(data: ByteArray): Boolean = try {
        printer?.printRawData(data)
        true
    } catch (e: Exception) {
        false
    }

    fun cetakGambar(png: ByteArray): Boolean = try {
        printer?.printBitmap(png)
        true
    } catch (e: Exception) {
        false
    }

    fun majuBaris(baris: Int): Boolean = try {
        printer?.nextLine(baris)
        true
    } catch (e: Exception) {
        false
    }
}
