package com.example.logidocs

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, а не FlutterActivity: local_auth показывает
// системный BiometricPrompt, которому нужен FragmentActivity.
class MainActivity : FlutterFragmentActivity()
