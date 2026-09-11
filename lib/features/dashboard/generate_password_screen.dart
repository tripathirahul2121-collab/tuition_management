import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/auth_controller.dart';
import '../auth/presentation/signup_screen.dart'; // ✅ USE SAME PROVIDER
import '../../core/constants/academic_catalog.dart';

class GeneratePasswordScreen extends ConsumerStatefulWidget {
  const GeneratePasswordScreen({super.key});

  @override
  ConsumerState<GeneratePasswordScreen> createState() =>
      _GeneratePasswordScreenState();
}

class _GeneratePasswordScreenState
    extends ConsumerState<GeneratePasswordScreen> {
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController nameController = TextEditingController();

  String selectedClass = "";
  String selectedBatch = AcademicCatalog.regularBatch;
  String selectedRole = "student";
  String generatedPassword = "";

  //////////////////////////////////////////////////////
  /// UI DECORATION
  //////////////////////////////////////////////////////

  InputDecoration fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  //////////////////////////////////////////////////////
  /// 🔥 PASSWORD LOGIC (SINGLE SOURCE)
  //////////////////////////////////////////////////////

  String _generatePasswordPattern() {
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    final random = Random();

    final firstTwo =
        "${letters[random.nextInt(letters.length)]}${letters[random.nextInt(letters.length)]}";
    final numbers = "${random.nextInt(10)}${random.nextInt(10)}";

    return "$firstTwo${numbers}ME";
  }

  //////////////////////////////////////////////////////
  /// GENERATE PASSWORD (FIXED)
  //////////////////////////////////////////////////////
  void _generatePassword() async {
    final mobile = mobileController.text.trim();
    final name = nameController.text.trim();
    final role = selectedRole;

    if (mobile.isEmpty) {
      _showSnack("Enter mobile number first");
      return;
    }

    if (mobile.length != 10) {
      _showSnack("Enter valid 10-digit mobile number");
      return;
    }

    //////////////////////////////////////////////////////
    /// 🔥 GENERATE ONCE
    //////////////////////////////////////////////////////
    final password = _generatePasswordPattern();

    //////////////////////////////////////////////////////
    /// 🔥 SAVE TO GLOBAL PROVIDER (SAME ONE)
    //////////////////////////////////////////////////////
    ref.read(generatedPasswordProvider.notifier).state = password;

    //////////////////////////////////////////////////////
    /// 🔥 SEND SAME PASSWORD TO BACKEND
    //////////////////////////////////////////////////////
    final (_, saved) = await ref
        .read(authControllerProvider.notifier)
        .generatePassword(
          mobile,
          name: name,
          userClass: role == "student" ? selectedClass : "",
          userBatch: role == "student" ? selectedBatch : "",
          role: role,
          password: password, // ✅ VERY IMPORTANT
        );

    if (!mounted) return;

    if (!saved) {
      _showSnack(
        "Password was generated, but Firebase did not save this student to Pending.",
      );
      return;
    }

    //////////////////////////////////////////////////////
    /// UPDATE UI
    //////////////////////////////////////////////////////
    setState(() => generatedPassword = password);

    //////////////////////////////////////////////////////
    /// DIALOG
    //////////////////////////////////////////////////////

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 50, color: Colors.blue),

              const SizedBox(height: 12),

              const Text(
                "Password Generated",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              const Text("Your generated password is:"),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  password,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: password));
                  Navigator.pop(context);
                  _showSnack("Copied to clipboard");
                },
                icon: const Icon(Icons.copy),
                label: const Text("Copy Password"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  //////////////////////////////////////////////////////
  /// UI
  //////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Generate Password"), centerTitle: true),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            TextField(
              controller: mobileController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: fieldDecoration("Mobile Number", Icons.phone),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: nameController,
              decoration: fieldDecoration("Name (Optional)", Icons.person),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: fieldDecoration("Member Role", Icons.verified_user),
              items: const [
                DropdownMenuItem(value: "student", child: Text("Student")),
                DropdownMenuItem(value: "teacher", child: Text("Teacher")),
                DropdownMenuItem(value: "admin", child: Text("Admin")),
              ],
              onChanged: (value) {
                setState(() {
                  selectedRole = value ?? "student";
                  if (selectedRole != "student") {
                    selectedClass = "";
                    selectedBatch = AcademicCatalog.regularBatch;
                  }
                });
              },
            ),

            const SizedBox(height: 16),

            if (selectedRole == "student") ...[
              DropdownButtonFormField<String>(
                decoration: fieldDecoration("Class (Optional)", Icons.school),
                items: AcademicCatalog.classValues.map((value) {
                  return DropdownMenuItem(
                    value: value,
                    child: Text(AcademicCatalog.classLabel(value)),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedClass = value ?? "";
                  selectedBatch = AcademicCatalog.regularBatch;
                },
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _generatePassword,
                child: const Text("Generate Password"),
              ),
            ),

            const SizedBox(height: 30),

            if (generatedPassword.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Text(
                        "Your generated password is:",
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        generatedPassword,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
