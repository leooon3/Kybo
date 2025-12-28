// File: mydiet_admin/lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    // COPY THESE VALUES FROM FIREBASE CONSOLE -> PROJECT SETTINGS -> WEB APP
    apiKey: "AIzaSyBtwxj_sUpokGL-kChPJ9GM790nsK8Dd0E",
    appId: "1:673588124626:web:5f4ff372397e79eb3d460b",
    messagingSenderId: "673588124626",
    projectId: "mydiet-6d55b",
    authDomain: "mydiet-6d55b.firebaseapp.com", // Optional but recommended
    storageBucket:
        "mydiet-6d55b.firebasestorage.app", // Optional but recommended
  );
}
