// Antarmuka printer internal handheld (service sistem SRPrinter,
// paket `recieptservice.com.recieptservice`, printer duduk di /dev/ttyS1).
//
// PENTING - susunan method di berkas ini menentukan nomor transaksi binder,
// jadi urutannya harus SAMA PERSIS dengan milik pabrikan. APK service-nya
// sudah di-obfuscate sehingga urutan aslinya tidak bisa dibaca kembali; satu
// -satunya yang bisa diverifikasi dari APK adalah `setTextSize(int, float)`.
//
// Karena itu lapisan Dart memperlakukan jalur ini sebagai "coba dulu":
// setiap kegagalan binder membuat aplikasi kembali memakai jalur Bluetooth
// (InnerPrinter) yang sudah terbukti jalan. Bila pabrikan mengirim berkas
// AIDL resminya, timpa berkas ini apa adanya - sisa kodenya tidak perlu
// diubah.
package recieptservice.com.recieptservice;

interface PrinterInterface {
    void printText(String text);

    void printBarCode(String data, int symbology, int height, int width,
            int textPosition);

    void printQRCode(String data, int moduleSize, int errorCorrectionLevel);

    void printBitmap(in byte[] bitmap);

    void printRawData(in byte[] data);

    void setAlignment(int alignment);

    // Satu-satunya tanda tangan yang terbaca di APK: (I, F)V.
    void setTextSize(int type, float size);

    void setTextBold(boolean bold);

    void nextLine(int line);

    int getStatus();
}
