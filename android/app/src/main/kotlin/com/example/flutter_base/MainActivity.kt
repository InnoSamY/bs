package com.example.flutter_base

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        init {
            System.loadLibrary("flutter_base")
        }
    }
}
