import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/auth_controller.dart';

class TeacherDashboard extends ConsumerStatefulWidget {
  const TeacherDashboard({super.key});

  @override
  ConsumerState<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends ConsumerState<TeacherDashboard> {
  final ScrollController _scrollController = ScrollController();
  double elevation = 0;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      if (_scrollController.offset > 5) {
        if (elevation == 0) {
          setState(() => elevation = 4);
        }
      } else {
        if (elevation != 0) {
          setState(() => elevation = 0);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ////////////////////////////////////////////////////////////////
  /// GET COLUMN COUNT (RESPONSIVE)
  ////////////////////////////////////////////////////////////////

  int getCrossAxisCount(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = getCrossAxisCount(width);
    final userType = ref.watch(userTypeProvider);

    final dashboardItems = [
      const _DashboardItem(
        title: "Generate Password",
        icon: Icons.password,
        route: "/generate-password",
        color: Color(0xFF4CAF50),
      ),
      const _DashboardItem(
        title: "Check Members",
        icon: Icons.people,
        route: "/members",
        color: Color(0xFF2196F3),
      ),
      const _DashboardItem(
        title: "Attendance",
        icon: Icons.check_circle,
        route: "/attendance",
        color: Color(0xFFFF9800),
      ),
      const _DashboardItem(
        title: "Update Progress Report",
        icon: Icons.bar_chart,
        route: "/progress",
        color: Color(0xFF9C27B0),
      ),
      const _DashboardItem(
        title: "Performance Analysis",
        icon: Icons.analytics,
        route: "/performance",
        color: Color(0xFFE91E63),
      ),
      const _DashboardItem(
        title: "Stars of ME",
        icon: Icons.emoji_events,
        route: "/feedback",
        color: Color(0xFF009688),
      ),
      const _DashboardItem(
        title: "Updates",
        icon: Icons.notifications_active,
        route: "/updates",
        color: Color(0xFF3F51B5),
      ),
      if (userType == "admin")
        const _DashboardItem(
          title: "Fees Tracking",
          icon: Icons.account_balance_wallet,
          route: "/fees",
          color: Color(0xFFC62828),
        ),
      const _DashboardItem(
        title: "MCQ Tests",
        icon: Icons.quiz,
        route: "/mcq-tests",
        color: Color(0xFF2563EB),
      ),
      if (userType == "admin")
        const _DashboardItem(
          title: "Settings",
          icon: Icons.settings,
          route: "/settings",
          color: Color(0xFF455A64),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: elevation,
        title: const Text(
          "Teacher Dashboard",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: GridView.builder(
          controller: _scrollController,

          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,

            crossAxisSpacing: 14,
            mainAxisSpacing: 14,

            // 🔥 AUTO HEIGHT CONTROL
            childAspectRatio: 1.1,
          ),

          itemCount: dashboardItems.length,

          itemBuilder: (context, index) {
            final item = dashboardItems[index];
            return _DashboardCard(
              title: item.title,
              icon: item.icon,
              color: item.color,
              onTap: () => Navigator.pushNamed(context, item.route),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardItem {
  final String title;
  final IconData icon;
  final String route;
  final Color color;

  const _DashboardItem({
    required this.title,
    required this.icon,
    required this.route,
    required this.color,
  });
}

////////////////////////////////////////////////////////////
/// CARD
////////////////////////////////////////////////////////////

class _DashboardCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> scaleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: scaleAnim.value,

          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,

            child: Container(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: widget.color.withValues(alpha: 0.3),
                    offset: const Offset(0, 6),
                  ),
                ],
              ),

              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 34, color: Colors.white),

                  const SizedBox(height: 10),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
