import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final studentsByClassProvider = StreamProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, className) {
      ref.keepAlive();

      final firestore = FirebaseFirestore.instance;

      return firestore
          .collection("users")
          .where("role", isEqualTo: "student")
          .where("class", isEqualTo: className)
          .orderBy("name")
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .where((doc) => doc.data()["active"] != false)
                .map((doc) => {"mobile": doc.id, ...doc.data()})
                .toList(growable: false);
          });
    });
