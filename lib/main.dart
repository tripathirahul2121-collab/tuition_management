import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'core/firebase/tuition_firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    runApp(
      const ProviderScope(
        child: TuitionApp(),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to start Tuition',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Firebase initialization failed.\n\n$error',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}