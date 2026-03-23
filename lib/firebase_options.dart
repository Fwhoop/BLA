import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyArGVCHREYDGhSgc2ZVGbyv4N-BHb7bzXw',
    appId: '1:1083830572751:web:20d6bf873f795219fcc9ba',
    messagingSenderId: '1083830572751',
    projectId: 'bla-verification',
    authDomain: 'bla-verification.firebaseapp.com',
    storageBucket: 'bla-verification.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyArGVCHREYDGhSgc2ZVGbyv4N-BHb7bzXw',
    appId: '1:1083830572751:android:20d6bf873f795219fcc9ba',
    messagingSenderId: '1083830572751',
    projectId: 'bla-verification',
    storageBucket: 'bla-verification.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyArGVCHREYDGhSgc2ZVGbyv4N-BHb7bzXw',
    appId: '1:1083830572751:ios:20d6bf873f795219fcc9ba',
    messagingSenderId: '1083830572751',
    projectId: 'bla-verification',
    storageBucket: 'bla-verification.appspot.com',
    iosBundleId: 'com.example.barangayLegalAid',
  );
}
