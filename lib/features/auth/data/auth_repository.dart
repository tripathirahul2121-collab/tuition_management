import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/academic_catalog.dart';

class AuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String ownerMobile = "9999410046";
  final String ownerPassword = "A143143";

  Future<void> _addStudentToExistingTests({
    required String mobile,
    required String name,
    required String userClass,
    required String userBatch,
  }) async {
    final subjectNames = await AcademicCatalog.loadSubjectsForClass(userClass);
    final progressDocId = AcademicCatalog.batchDocId(userClass, userBatch);

    for (final subject in subjectNames) {
      final tests = await _firestore
          .collection("progress")
          .doc(progressDocId)
          .collection(subject)
          .get();

      var batch = _firestore.batch();
      var pendingWrites = 0;

      for (final test in tests.docs) {
        final data = test.data();
        final students = data["students"];
        if (students is Map && students.containsKey(mobile)) continue;

        batch.update(test.reference, {
          "students.$mobile": {
            "name": name,
            "marks": "",
            "absent": true,
            "feedback": "",
            "type": "",
            "feedbackRead": true,
          },
        });
        pendingWrites++;

        if (pendingWrites == 450) {
          await batch.commit();
          batch = _firestore.batch();
          pendingWrites = 0;
        }
      }

      if (pendingWrites > 0) {
        await batch.commit();
      }
    }

    final normalizedBatch = AcademicCatalog.normalizeBatch(userBatch);
    final mcqTests = await _firestore
        .collection("mcq_tests")
        .where("status", isEqualTo: "released")
        .get();

    var mcqBatch = _firestore.batch();
    var mcqPendingWrites = 0;

    for (final test in mcqTests.docs) {
      final data = test.data();
      if (AcademicCatalog.mcqTargetClass(data) != userClass ||
          !AcademicCatalog.mcqBatchMatches(data, normalizedBatch)) {
        continue;
      }

      final students = data["students"];
      if (students is Map && students.containsKey(mobile)) continue;

      mcqBatch.set(test.reference, {
        "students.$mobile": {
          "name": name,
          "mobile": mobile,
          "class": userClass,
          "batch": normalizedBatch,
          "assignedAt": FieldValue.serverTimestamp(),
          "submitted": false,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      mcqPendingWrites++;

      if (mcqPendingWrites == 450) {
        await mcqBatch.commit();
        mcqBatch = _firestore.batch();
        mcqPendingWrites = 0;
      }
    }

    if (mcqPendingWrites > 0) {
      await mcqBatch.commit();
    }
  }

  ////////////////////////////////////////////////////////////
  /// LOGIN
  ////////////////////////////////////////////////////////////

  Future<bool> login(String mobile, String password, String role) async {
    try {
      if (mobile == ownerMobile && password == ownerPassword) {
        return role == "teacher" || role == "admin";
      }

      final doc = await _firestore.collection("users").doc(mobile).get();

      if (!doc.exists) return false;

      final data = doc.data();

      if (data?["password"] != password) return false;
      if (data?["role"] != role) return false;
      if (data?["active"] == false || data?["role"] == "junk") return false;

      return true;
    } catch (e) {
      debugPrint("LOGIN ERROR -> $e");
      return false;
    }
  }

  ////////////////////////////////////////////////////////////
  /// SIGNUP
  ////////////////////////////////////////////////////////////

  Future<bool> registerUser({
    required String mobile,
    required String name,
    required String role,
    required String password,
    String school = "",
    String userClass = "",
    String userBatch = "regular",
  }) async {
    try {
      ////////////////////////////////////////////////////////////
      /// CHECK IN PENDING USERS (MANDATORY)
      ////////////////////////////////////////////////////////////

      final pendingDoc = await _firestore
          .collection("pending_users")
          .doc(mobile)
          .get();

      if (!pendingDoc.exists) {
        debugPrint("User not authorized (no pending record)");
        return false;
      }

      final storedPassword = pendingDoc.data()?["password"] as String?;

      if (storedPassword != password) {
        debugPrint("Invalid password");
        return false;
      }

      final allowedRole = pendingDoc.data()?["role"]?.toString() ?? "student";
      if (allowedRole != role) {
        debugPrint("Role mismatch");
        return false;
      }

      ////////////////////////////////////////////////////////////
      /// CREATE USER (VALID CASE)
      ////////////////////////////////////////////////////////////

      await _firestore.collection("users").doc(mobile).set({
        "name": name,
        "mobile": mobile,
        "role": role,
        "password": password,
        "school": school,
        "class": role == "student" ? userClass : "",
        "batch": role == "student"
            ? AcademicCatalog.normalizeBatch(userBatch)
            : "",
        "active": true,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (role == "student") {
        await _addStudentToExistingTests(
          mobile: mobile,
          name: name,
          userClass: userClass,
          userBatch: userBatch,
        );
      }

      ////////////////////////////////////////////////////////////
      /// REMOVE FROM PENDING
      ////////////////////////////////////////////////////////////

      await pendingDoc.reference.delete();

      return true;
    } catch (e) {
      debugPrint("SIGNUP ERROR -> $e");
      return false;
    }
  }

  ////////////////////////////////////////////////////////////
  /// 🔥 GENERATE PASSWORD (FIXED - SINGLE SOURCE)
  ////////////////////////////////////////////////////////////

  Future<(String?, bool)> generatePasswordForUser(
    String mobile, {
    String name = "",
    String userClass = "",
    String userBatch = "regular",
    String role = "student",
    required String password, // ✅ COMES FROM UI
  }) async {
    try {
      debugPrint("START GENERATION");

      final userDoc = await _firestore.collection("users").doc(mobile).get();

      debugPrint("PASSWORD RECEIVED FROM UI");

      ////////////////////////////////////////////////////////////
      /// IF USER EXISTS → UPDATE PASSWORD
      ////////////////////////////////////////////////////////////

      if (userDoc.exists) {
        await _firestore.collection("users").doc(mobile).update({
          "password": password,
          "role": role,
          "class": role == "student" ? userClass : "",
          "batch": role == "student"
              ? AcademicCatalog.normalizeBatch(userBatch)
              : "",
          "active": true,
        });

        debugPrint("UPDATED EXISTING USER");

        return (password, true);
      }

      ////////////////////////////////////////////////////////////
      /// NEW USER → SAVE IN PENDING
      ////////////////////////////////////////////////////////////

      await _firestore.collection("pending_users").doc(mobile).set({
        "mobile": mobile,
        "name": name,
        "class": userClass,
        "batch": role == "student"
            ? AcademicCatalog.normalizeBatch(userBatch)
            : "",
        "role": role,
        "password": password, // ✅ SAME PASSWORD
        "createdAt": FieldValue.serverTimestamp(),
      });

      debugPrint("NEW USER CREATED");

      return (password, true);
    } catch (e) {
      debugPrint("PASSWORD ERROR -> $e");
      return (null, false);
    }
  }
}
