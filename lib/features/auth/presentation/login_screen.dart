import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final mobileController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool hidePassword = true;

  static const String ownerMobile = "9999410046";
  static const String ownerPassword = "A143143";

  void showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  //////////////////////////////////////////////////////
  /// 🔐 CONTROLLED LOGIN SYSTEM
  //////////////////////////////////////////////////////

  Future<void> login() async {
    final userType = ref.read(userTypeProvider);
    final mobile = mobileController.text.trim();
    final password = passwordController.text.trim();

    if (mobile.length != 10) {
      showSnack("Enter valid mobile number");
      return;
    }

    if (password.isEmpty) {
      showSnack("Enter password");
      return;
    }

    setState(() => loading = true);

    try {
      //////////////////////////////////////////////////////
      /// 👑 OWNER LOGIN (NO FIRESTORE NEEDED)
      //////////////////////////////////////////////////////

      if ((userType == "teacher" || userType == "admin") &&
          mobile == ownerMobile &&
          password == ownerPassword) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, "/teacher");
        return;
      }

      //////////////////////////////////////////////////////
      /// 🔥 LOGIN WITH GENERATED FIRESTORE PASSWORD
      //////////////////////////////////////////////////////

      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(mobile)
          .get();

      if (!doc.exists) {
        showSnack("Account data not found. Please create account first.");
        setState(() => loading = false);
        return;
      }

      final data = doc.data() ?? {};
      data["mobile"] = data["mobile"] ?? mobile;

      if (data["active"] == false || data["role"] == "junk") {
        showSnack(
          data["blockedMessage"]?.toString() ??
              "You are not the authorized student of ME classes.",
        );
        setState(() => loading = false);
        return;
      }

      if (data["password"] != password) {
        showSnack("Wrong password");
        setState(() => loading = false);
        return;
      }

      if (data["role"] != userType) {
        showSnack("Wrong account type selected.");
        setState(() => loading = false);
        return;
      }

      //////////////////////////////////////////////////////
      /// 🚀 STEP 3: NAVIGATE
      //////////////////////////////////////////////////////

      if (!mounted) return;

      if (userType == "teacher" || userType == "admin") {
        Navigator.pushReplacementNamed(context, "/teacher");
      } else {
        Navigator.pushReplacementNamed(
          context,
          "/student",
          arguments: data, // ✅ pass student data
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == "permission-denied") {
        showSnack("Firestore permission denied. Publish the Firestore rules.");
      } else {
        showSnack(e.message ?? "Firebase error");
      }
    } catch (e) {
      showSnack("Error: $e");
    }

    setState(() => loading = false);
  }

  //////////////////////////////////////////////////////
  /// UI
  //////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    final userType = ref.watch(userTypeProvider);

    return Scaffold(
      backgroundColor: const Color(0xffF6F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.school,
                    size: 70,
                    color: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "ME Classes",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 6),
                  const Text("Login to continue"),
                  const SizedBox(height: 36),

                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 20,
                          color: Colors.black.withValues(alpha: .05),
                        ),
                      ],
                    ),

                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _roleButton("teacher", userType)),
                            const SizedBox(width: 8),
                            Expanded(child: _roleButton("student", userType)),
                            const SizedBox(width: 8),
                            Expanded(child: _roleButton("admin", userType)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        TextField(
                          controller: mobileController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: "Mobile Number",
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextField(
                          controller: passwordController,
                          obscureText: hidePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                hidePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  hidePassword = !hidePassword;
                                });
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 26),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: loading ? null : login,
                            child: loading
                                ? const CircularProgressIndicator()
                                : const Text("Login"),
                          ),
                        ),

                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, "/signup");
                          },
                          child: const Text("Create new account"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  //////////////////////////////////////////////////////
  /// ROLE BUTTON
  //////////////////////////////////////////////////////

  Widget _roleButton(String role, String userType) {
    return GestureDetector(
      onTap: () {
        ref.read(userTypeProvider.notifier).state = role;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: userType == role ? Colors.deepPurple : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            role == "teacher"
                ? "Teacher"
                : role == "admin"
                ? "Admin"
                : "Student",
            style: TextStyle(
              color: userType == role ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
