import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_branding.dart';
import '../../core/widgets/branded_logo.dart';
import '../../core/widgets/coaching_qr_dialog.dart';
import 'admin_dashboard_screen.dart';
import '../auth/presentation/auth_controller.dart';

class TeacherDashboard extends ConsumerWidget {
  const TeacherDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = WhiteLabelConfig.current;
    final userType = ref.watch(userTypeProvider);
    if (userType == 'admin') return const AdminDashboardScreen();

    final actions = _teacherDashboardActions(userType);

    return Scaffold(
      backgroundColor: branding.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DashboardHeaderDelegate(branding: branding),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WelcomePanel(branding: branding, userType: userType),
                        const SizedBox(height: 18),
                        _MetricsGrid(branding: branding),
                        const SizedBox(height: 24),
                        _SectionHeader(
                          title: 'Quick Actions',
                          subtitle: 'Open the core tools you use every day.',
                          action: _CompactLinkButton(
                            icon: Icons.qr_code_2_rounded,
                            label: 'QR & App Link',
                            onPressed: () => showCoachingQrDialog(
                              context: context,
                              branding: branding,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveActionsGrid(
                          actions: actions,
                          branding: branding,
                        ),
                        const SizedBox(height: 24),
                        _ShareCoachingPanel(branding: branding),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<_DashboardAction> _teacherDashboardActions(String userType) {
  return [
    const _DashboardAction(
      title: 'Attendance',
      description: "Mark or review today's attendance",
      icon: Icons.fact_check_rounded,
      route: '/attendance',
    ),
    const _DashboardAction(
      title: 'Check Members',
      description: 'Manage active, pending, and junk members',
      icon: Icons.groups_2_rounded,
      route: '/members',
    ),
    const _DashboardAction(
      title: 'Progress Reports',
      description: 'Update student academic performance',
      icon: Icons.trending_up_rounded,
      route: '/progress',
    ),
    if (userType == 'admin')
      const _DashboardAction(
        title: 'Fees Tracking',
        description: 'Review and update fee records',
        icon: Icons.account_balance_wallet_rounded,
        route: '/fees',
      ),
    const _DashboardAction(
      title: 'Generate Password',
      description: 'Invite students and teachers securely',
      icon: Icons.password_rounded,
      route: '/generate-password',
    ),
    const _DashboardAction(
      title: 'Stars of ME',
      description: 'Celebrate high performers and achievements',
      icon: Icons.workspace_premium_rounded,
      route: '/feedback',
    ),
    const _DashboardAction(
      title: 'Updates',
      description: 'Publish notices and class announcements',
      icon: Icons.campaign_rounded,
      route: '/updates',
    ),
    const _DashboardAction(
      title: 'Performance Analysis',
      description: 'Analyze results, ranks, and trends',
      icon: Icons.analytics_rounded,
      route: '/performance',
    ),
    const _DashboardAction(
      title: 'MCQ Tests',
      description: 'Create, release, and review MCQ tests',
      icon: Icons.quiz_rounded,
      route: '/mcq-tests',
    ),
    if (userType == 'admin')
      const _DashboardAction(
        title: 'Settings',
        description: 'Maintain app data and academic settings',
        icon: Icons.admin_panel_settings_rounded,
        route: '/settings',
      ),
  ];
}

class _DashboardHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DashboardHeaderDelegate({required this.branding});

  final AppBranding branding;

  @override
  double get minExtent => 76;

  @override
  double get maxExtent => 76;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: branding.surfaceColor.withValues(alpha: 0.96),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: overlapsContent || shrinkOffset > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                BrandedLogo(branding: branding, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branding.instituteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: branding.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (branding.branchName.isNotEmpty)
                        Text(
                          branding.branchName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Notifications',
                  child: IconButton(
                    onPressed: () => _showSnack(
                      context,
                      'Notifications are not configured yet.',
                    ),
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: branding.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _ProfileChip(branding: branding),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DashboardHeaderDelegate oldDelegate) {
    return oldDelegate.branding != branding;
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    return PopupMenuButton<String>(
      tooltip: 'Profile menu',
      onSelected: (value) {
        if (value == 'logout') {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.logout_rounded),
            title: Text('Logout'),
          ),
        ),
      ],
      child: Container(
        height: 42,
        padding: EdgeInsets.only(left: compact ? 0 : 10, right: 8),
        decoration: BoxDecoration(
          color: branding.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: branding.primaryColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: branding.primaryColor,
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(
                'Teacher',
                style: TextStyle(
                  color: branding.textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.grey.shade700,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.branding, required this.userType});

  final AppBranding branding;
  final String userType;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 12 => 'Good Morning',
      < 17 => 'Good Afternoon',
      _ => 'Good Evening',
    };
    final date = DateFormat('EEEE, d MMMM').format(now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: branding.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 14,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${_roleLabel(userType)}',
                  style: TextStyle(
                    color: branding.textColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Here's what's happening at your coaching centre today.",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          _DatePill(date: date, branding: branding),
        ],
      ),
    );
  }
}

String _roleLabel(String userType) {
  if (userType == 'admin') return 'Admin';
  return 'Teacher';
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.date, required this.branding});

  final String date;
  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: branding.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 17,
            color: branding.primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            date,
            style: TextStyle(
              color: branding.primaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _DashboardMetric(
        label: 'Students',
        helper: 'Active students',
        icon: Icons.school_rounded,
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        includeDocument: (data) {
          return data['role'] == 'student' && data['active'] != false;
        },
      ),
      _DashboardMetric(
        label: 'Pending',
        helper: 'Waiting for signup',
        icon: Icons.person_add_alt_1_rounded,
        stream: FirebaseFirestore.instance
            .collection('pending_users')
            .snapshots(),
      ),
      _DashboardMetric(
        label: 'MCQ Tests',
        helper: 'Released tests',
        icon: Icons.assignment_turned_in_rounded,
        stream: FirebaseFirestore.instance.collection('mcq_tests').snapshots(),
        includeDocument: (data) => data['status'] == 'released',
      ),
      _DashboardMetric(
        label: 'Updates',
        helper: 'Recent notices',
        icon: Icons.notifications_active_rounded,
        stream: FirebaseFirestore.instance.collection('updates').snapshots(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsForWidth(constraints.maxWidth);
        return GridView.builder(
          itemCount: metrics.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth < 380 ? 1.55 : 2.25,
          ),
          itemBuilder: (context, index) {
            return _MetricCard(metric: metrics[index], branding: branding);
          },
        );
      },
    );
  }
}

int _columnsForWidth(double width) {
  if (width >= 1040) return 4;
  if (width >= 760) return 3;
  if (width >= 420) return 2;
  return 1;
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.helper,
    required this.icon,
    required this.stream,
    this.includeDocument,
  });

  final String label;
  final String helper;
  final IconData icon;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final bool Function(Map<String, dynamic> data)? includeDocument;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.branding});

  final _DashboardMetric metric;
  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: metric.stream,
      builder: (context, snapshot) {
        final value = snapshot.hasError
            ? '!'
            : snapshot.hasData
            ? snapshot.data!.docs
                  .where((doc) {
                    final filter = metric.includeDocument;
                    return filter == null || filter(doc.data());
                  })
                  .length
                  .toString()
            : '--';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: branding.surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: branding.primaryColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(metric.icon, color: branding.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: branding.textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      snapshot.hasError ? 'Check rules' : metric.helper,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
        ?action,
      ],
    );
  }
}

class _ResponsiveActionsGrid extends StatelessWidget {
  const _ResponsiveActionsGrid({required this.actions, required this.branding});

  final List<_DashboardAction> actions;
  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsForWidth(constraints.maxWidth);
        return GridView.builder(
          itemCount: actions.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth < 380 ? 1.42 : 1.72,
          ),
          itemBuilder: (context, index) {
            return _DashboardActionCard(
              action: actions[index],
              branding: branding,
            );
          },
        );
      },
    );
  }
}

class _DashboardAction {
  const _DashboardAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
  });

  final String title;
  final String description;
  final IconData icon;
  final String route;
}

class _DashboardActionCard extends StatefulWidget {
  const _DashboardActionCard({required this.action, required this.branding});

  final _DashboardAction action;
  final AppBranding branding;

  @override
  State<_DashboardActionCard> createState() => _DashboardActionCardState();
}

class _DashboardActionCardState extends State<_DashboardActionCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.branding.primaryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: _hovering ? const Offset(0, -0.015) : Offset.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.branding.surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovering
                  ? color.withValues(alpha: 0.28)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovering ? 0.08 : 0.035),
                blurRadius: _hovering ? 24 : 14,
                offset: Offset(0, _hovering ? 12 : 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.pushNamed(context, widget.action.route),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(widget.action.icon, color: color),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.grey.shade500,
                          size: 20,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      widget.action.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.branding.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.action.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareCoachingPanel extends StatelessWidget {
  const _ShareCoachingPanel({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: branding.primaryColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: branding.primaryColor.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 14,
        spacing: 18,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Share Your Coaching',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Let students and parents quickly access your coaching portal.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LightButton(
                icon: Icons.qr_code_rounded,
                label: 'View QR',
                onPressed: () =>
                    showCoachingQrDialog(context: context, branding: branding),
              ),
              _LightButton(
                icon: Icons.copy_rounded,
                label: 'Copy Link',
                onPressed: () => copyPublicAppLink(context, branding),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightButton extends StatelessWidget {
  const _LightButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        minimumSize: const Size(116, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }
}

class _CompactLinkButton extends StatelessWidget {
  const _CompactLinkButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
