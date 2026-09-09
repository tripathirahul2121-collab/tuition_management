import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/academic_catalog.dart';

final generatedPasswordProvider = StateProvider<String>((ref) => "");

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final nameController = TextEditingController();
  final mobileController = TextEditingController();
  final schoolController = TextEditingController();
  final passwordController = TextEditingController();

  String selectedClass = "";
  String selectedBatch = AcademicCatalog.regularBatch;

  //////////////////////////////////////////////////////
  /// SNACKBAR
  //////////////////////////////////////////////////////

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addStudentToExistingTests({
    required String mobile,
    required String name,
    required String userClass,
    required String userBatch,
  }) async {
    final subjectNames = await AcademicCatalog.loadSubjectsForClass(userClass);
    final progressDocId = AcademicCatalog.batchDocId(userClass, userBatch);

    for (final subject in subjectNames) {
      final tests = await FirebaseFirestore.instance
          .collection("progress")
          .doc(progressDocId)
          .collection(subject)
          .get();

      var batch = FirebaseFirestore.instance.batch();
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
          batch = FirebaseFirestore.instance.batch();
          pendingWrites = 0;
        }
      }

      if (pendingWrites > 0) {
        await batch.commit();
      }
    }

    final normalizedBatch = AcademicCatalog.normalizeBatch(userBatch);
    final mcqTests = await FirebaseFirestore.instance
        .collection("mcq_tests")
        .where("status", isEqualTo: "released")
        .get();

    var mcqBatch = FirebaseFirestore.instance.batch();
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
        mcqBatch = FirebaseFirestore.instance.batch();
        mcqPendingWrites = 0;
      }
    }

    if (mcqPendingWrites > 0) {
      await mcqBatch.commit();
    }
  }

  //////////////////////////////////////////////////////
  /// 🔥 FIXED CREATE ACCOUNT
  //////////////////////////////////////////////////////

  Future<void> _createAccount() async {
    final role = ref.read(userTypeProvider);

    final name = nameController.text.trim();
    final mobile = mobileController.text.trim();
    final password = passwordController.text.trim();
    final school = schoolController.text.trim();

    if (name.isEmpty) {
      _showSnack("Enter name");
      return;
    }

    if (mobile.length != 10) {
      _showSnack("Enter valid mobile number");
      return;
    }

    if (password.isEmpty) {
      _showSnack("Enter generated password");
      return;
    }

    if (role == "student" && selectedClass.isEmpty) {
      _showSnack("Select class");
      return;
    }

    try {
      //////////////////////////////////////////////////////
      /// CHECK PENDING USER
      //////////////////////////////////////////////////////

      final pendingDoc = await FirebaseFirestore.instance
          .collection("pending_users")
          .doc(mobile)
          .get();

      if (!pendingDoc.exists) {
        _showSnack("Password not generated for this number");
        return;
      }

      final storedPassword = pendingDoc.data()?["password"];
      final allowedRole = pendingDoc.data()?["role"]?.toString() ?? "student";
      final allowedClass = pendingDoc.data()?["class"]?.toString() ?? "";
      final allowedBatch = AcademicCatalog.normalizeBatch(
        pendingDoc.data()?["batch"]?.toString(),
      );

      if (storedPassword != password) {
        _showSnack("Wrong password ❌");
        return;
      }

      if (allowedRole != role) {
        _showSnack(
          "This password is generated for ${allowedRole.toUpperCase()} login only.",
        );
        return;
      }

      if (role == "student" &&
          allowedClass.isNotEmpty &&
          allowedClass != selectedClass) {
        _showSnack("Select the class assigned while generating password.");
        return;
      }

      if (role == "student" && allowedBatch != selectedBatch) {
        _showSnack("Select the batch assigned while generating password.");
        return;
      }

      //////////////////////////////////////////////////////
      /// SAVE USER DATA
      //////////////////////////////////////////////////////

      await FirebaseFirestore.instance.collection("users").doc(mobile).set({
        "name": name,
        "mobile": mobile,
        "school": school,
        "class": role == "student" ? selectedClass : "",
        "batch": role == "student" ? selectedBatch : "",
        "role": role,
        "password": password,
        "active": true,
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (role == "student") {
        await _addStudentToExistingTests(
          mobile: mobile,
          name: name,
          userClass: selectedClass,
          userBatch: selectedBatch,
        );
      }

      //////////////////////////////////////////////////////
      /// DELETE FROM PENDING
      //////////////////////////////////////////////////////

      await pendingDoc.reference.delete();

      if (!mounted) return;

      _showSnack("Account ready ✅");
      Navigator.pop(context);
    } catch (e) {
      _showSnack("Error: ${e.toString()}");
    }
  }

  //////////////////////////////////////////////////////
  /// UI
  //////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final type = ref.watch(userTypeProvider);

    return Scaffold(
      backgroundColor: const Color(0xffF6F7FB),
      appBar: AppBar(title: const Text("Create Account"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 2,
                color: Colors.black.withValues(alpha: .05),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ToggleButtons(
                  isSelected: [
                    type == "teacher",
                    type == "student",
                    type == "admin",
                  ],
                  onPressed: (index) {
                    ref.read(userTypeProvider.notifier).state = [
                      "teacher",
                      "student",
                      "admin",
                    ][index];
                  },
                  borderRadius: BorderRadius.circular(12),
                  fillColor: Theme.of(context).colorScheme.primary,
                  selectedColor: Colors.white,
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text("Teacher"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text("Student"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text("Admin"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _field("Full Name", nameController),

              if (type == "student") ...[
                const SizedBox(height: 16),
                _field("School Name", schoolController),
                const SizedBox(height: 16),
                _classDropdown(),
                const SizedBox(height: 16),
                _batchDropdown(),
              ],

              const SizedBox(height: 16),
              _field("Mobile Number", mobileController, isNumber: true),

              const SizedBox(height: 16),

              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  hintText: "Enter Generated Password",
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _createAccount,
                  child: const Text("Create Account"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  //////////////////////////////////////////////////////
  /// INPUT FIELD
  //////////////////////////////////////////////////////

  Widget _field(
    String hint,
    TextEditingController controller, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLength: isNumber ? 10 : null,
      decoration: InputDecoration(
        hintText: hint,
        counterText: "",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  //////////////////////////////////////////////////////
  /// CLASS DROPDOWN
  //////////////////////////////////////////////////////

  Widget _classDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        hintText: "Select Class",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: const [
        DropdownMenuItem(value: "5", child: Text("Class 5")),
        DropdownMenuItem(value: "6", child: Text("Class 6")),
        DropdownMenuItem(value: "7", child: Text("Class 7")),
        DropdownMenuItem(value: "8", child: Text("Class 8")),
        DropdownMenuItem(value: "9", child: Text("Class 9")),
        DropdownMenuItem(value: "10", child: Text("Class 10")),
        DropdownMenuItem(value: "11", child: Text("Class 11")),
        DropdownMenuItem(value: "12", child: Text("Class 12")),
      ],
      onChanged: (value) {
        selectedClass = value ?? "";
      },
    );
  }

  Widget _batchDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: selectedBatch,
      decoration: InputDecoration(
        hintText: "Select Batch",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: AcademicCatalog.batchValues.map((value) {
        return DropdownMenuItem(
          value: value,
          child: Text(AcademicCatalog.batchLabel(value)),
        );
      }).toList(),
      onChanged: (value) {
        selectedBatch = AcademicCatalog.normalizeBatch(value);
      },
    );
  }
}
