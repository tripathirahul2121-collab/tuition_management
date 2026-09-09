import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> scaleAnim;
  late Animation<double> rotateAnim;
  late Animation<double> glowAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));

    rotateAnim = Tween<double>(
      begin: -0.05,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    glowAnim = Tween<double>(begin: 0.2, end: 1).animate(_controller);

    _controller.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),

            child: Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateX(rotateAnim.value)
                  ..scaleByDouble(
                    scaleAnim.value,
                    scaleAnim.value,
                    scaleAnim.value,
                    1,
                  ),

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Mind Evolution",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        foreground: Paint()
                          ..shader = LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: glowAnim.value),
                              Colors.blueAccent,
                            ],
                          ).createShader(const Rect.fromLTWH(0, 0, 300, 80)),
                        shadows: [
                          Shadow(
                            blurRadius: 40,
                            color: Colors.blueAccent.withValues(
                              alpha: glowAnim.value,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      "CLASSES",
                      style: TextStyle(
                        fontSize: 28,
                        letterSpacing: 6,
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
