import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_branding.dart';
import '../../core/constants/academic_catalog.dart';
import '../../core/widgets/branded_logo.dart';
import '../../core/widgets/coaching_qr_dialog.dart';
import 'admin_dashboard_data.dart';
import 'admin_dashboard_preferences.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _sidebarExpanded = true;
  late Future<AdminDashboardSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = AdminDashboardDataService().loadSummary();
  }

  void _refreshSummary() {
    setState(() {
      _summaryFuture = AdminDashboardDataService().loadSummary();
    });
  }

  void _toggleNavigation() {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 760) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    setState(() => _sidebarExpanded = !_sidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final branding = WhiteLabelConfig.current;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: branding.backgroundColor,
      drawer: _AdminMobileDrawer(branding: branding),
      body: Builder(
        builder: (context) {
          final width = MediaQuery.sizeOf(context).width;
          final showSidebar = width >= 760;

          return Column(
            children: [
              _AdminTopBar(
                branding: branding,
                onMenuPressed: _toggleNavigation,
                onRefresh: _refreshSummary,
              ),
              Expanded(
                child: Row(
                  children: [
                    if (showSidebar)
                      _AdminSidebar(
                        branding: branding,
                        expanded: _sidebarExpanded,
                      ),
                    Expanded(
                      child: StreamBuilder<AdminDashboardPreferences>(
                        stream: AdminDashboardPreferences.stream(),
                        initialData: AdminDashboardPreferences.defaults,
                        builder: (context, preferenceSnapshot) {
                          final preferences =
                              preferenceSnapshot.data ??
                              AdminDashboardPreferences.defaults;
                          return FutureBuilder<AdminDashboardSummary>(
                            future: _summaryFuture,
                            builder: (context, summarySnapshot) {
                              return _AdminDashboardHome(
                                branding: branding,
                                preferences: preferences,
                                summary: summarySnapshot.data,
                                loading:
                                    summarySnapshot.connectionState !=
                                    ConnectionState.done,
                                error: summarySnapshot.error,
                                onRefresh: _refreshSummary,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.branding,
    required this.onMenuPressed,
    required this.onRefresh,
  });

  final AppBranding branding;
  final VoidCallback onMenuPressed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    return SafeArea(
      bottom: false,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: branding.surfaceColor,
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            Tooltip(
              message: 'Navigation menu',
              child: IconButton(
                onPressed: onMenuPressed,
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
            const SizedBox(width: 8),
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
                      fontSize: compact ? 17 : 20,
                      fontWeight: FontWeight.w900,
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
              message: 'Refresh dashboard',
              child: IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
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
            _AdminProfileMenu(branding: branding, compact: compact),
          ],
        ),
      ),
    );
  }
}

class _AdminProfileMenu extends StatelessWidget {
  const _AdminProfileMenu({required this.branding, required this.compact});

  final AppBranding branding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Admin profile',
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
        height: 44,
        padding: EdgeInsets.only(left: compact ? 4 : 10, right: 8),
        decoration: BoxDecoration(
          color: branding.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: branding.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: branding.primaryColor,
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(
                'Admin',
                style: TextStyle(
                  color: branding.textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.branding, required this.expanded});

  final AppBranding branding;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOut,
      width: expanded ? 248 : 82,
      decoration: BoxDecoration(
        color: branding.surfaceColor,
        border: Border(
          right: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
          children: _navigationGroups
              .map(
                (group) => _NavigationGroup(
                  group: group,
                  branding: branding,
                  expanded: expanded,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _AdminMobileDrawer extends StatelessWidget {
  const _AdminMobileDrawer({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: branding.surfaceColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
          children: [
            Row(
              children: [
                BrandedLogo(branding: branding, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    branding.instituteName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ..._navigationGroups.map(
              (group) => _NavigationGroup(
                group: group,
                branding: branding,
                expanded: true,
                closeDrawerOnTap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationGroup extends StatelessWidget {
  const _NavigationGroup({
    required this.group,
    required this.branding,
    required this.expanded,
    this.closeDrawerOnTap = false,
  });

  final _AdminNavigationGroup group;
  final AppBranding branding;
  final bool expanded;
  final bool closeDrawerOnTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                group.label,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ...group.items.map(
            (item) => _NavigationTile(
              item: item,
              branding: branding,
              expanded: expanded,
              closeDrawerOnTap: closeDrawerOnTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatefulWidget {
  const _NavigationTile({
    required this.item,
    required this.branding,
    required this.expanded,
    required this.closeDrawerOnTap,
  });

  final _AdminNavigationItem item;
  final AppBranding branding;
  final bool expanded;
  final bool closeDrawerOnTap;

  @override
  State<_NavigationTile> createState() => _NavigationTileState();
}

class _NavigationTileState extends State<_NavigationTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final active =
        currentRoute == widget.item.route ||
        (currentRoute == '/teacher' && widget.item.route == '/teacher');
    final color = widget.branding.primaryColor;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: EdgeInsets.symmetric(
          horizontal: widget.expanded ? 12 : 0,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.11)
              : _hovering
              ? Colors.black.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final navigator = Navigator.of(context);
            if (widget.closeDrawerOnTap) navigator.pop();
            if (currentRoute == widget.item.route) return;
            navigator.pushNamed(widget.item.route);
          },
          child: Row(
            mainAxisAlignment: widget.expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                color: active ? color : Colors.grey.shade700,
                size: 22,
              ),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? color : const Color(0xFF374151),
                      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return widget.expanded
        ? tile
        : Tooltip(message: widget.item.label, child: tile);
  }
}

class _AdminDashboardHome extends StatelessWidget {
  const _AdminDashboardHome({
    required this.branding,
    required this.preferences,
    required this.summary,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final AppBranding branding;
  final AdminDashboardPreferences preferences;
  final AdminDashboardSummary? summary;
  final bool loading;
  final Object? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              _pageSidePadding(context),
              16,
              _pageSidePadding(context),
              24,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                _GreetingPanel(branding: branding),
                const SizedBox(height: 14),
                if (error != null)
                  _DashboardErrorCard(error: error!, onRetry: onRefresh),
                if (_showMetrics)
                  _OverviewMetrics(
                    branding: branding,
                    preferences: preferences,
                    summary: summary,
                    loading: loading,
                  ),
                if (_showMetrics) const SizedBox(height: 16),
                if (preferences.showConsecutiveAbsenceAlert ||
                    preferences.showPendingFees)
                  _NeedsAttentionSection(
                    branding: branding,
                    preferences: preferences,
                    summary: summary,
                    loading: loading,
                  ),
                if (preferences.showConsecutiveAbsenceAlert ||
                    preferences.showPendingFees)
                  const SizedBox(height: 16),
                if (preferences.showQrAndAppLink)
                  _PublicAppLinkSection(branding: branding),
                if (preferences.showQrAndAppLink) const SizedBox(height: 16),
                if (preferences.showQuickActions)
                  _QuickActionsSection(branding: branding),
                if (preferences.showQuickActions) const SizedBox(height: 16),
                if (preferences.showUpdates)
                  _RecentUpdatesCard(branding: branding, loading: loading),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  bool get _showMetrics {
    return preferences.showStudentOverview ||
        preferences.showAttendanceOverview ||
        preferences.showPendingFees ||
        preferences.showTeacherOverview;
  }
}

class _GreetingPanel extends StatelessWidget {
  const _GreetingPanel({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 12 => 'Good Morning',
      < 17 => 'Good Afternoon',
      _ => 'Good Evening',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: branding.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, Admin',
                  style: TextStyle(
                    color: branding.textColor,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Here's what needs your attention today.",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: branding.primaryColor.withValues(alpha: 0.09),
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
                  DateFormat('EEEE, d MMM').format(now),
                  style: TextStyle(
                    color: branding.primaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({
    required this.branding,
    required this.preferences,
    required this.summary,
    required this.loading,
  });

  final AppBranding branding;
  final AdminDashboardPreferences preferences;
  final AdminDashboardSummary? summary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricData>[
      if (preferences.showStudentOverview)
        _MetricData(
          label: 'Total Students',
          value: summary == null || summary!.peopleError != null
              ? null
              : '${summary!.totalStudents}',
          helper: summary?.peopleError != null
              ? 'Unable to load student overview'
              : '${summary?.activeStudents ?? 0} active enrolments',
          icon: Icons.groups_2_rounded,
          hasError: summary?.peopleError != null,
        ),
      if (preferences.showAttendanceOverview)
        _MetricData(
          label: 'Attendance Today',
          value: summary == null || summary!.attendanceError != null
              ? null
              : '${summary!.todayAttendance.present}',
          helper: summary?.attendanceError != null
              ? 'Unable to load attendance'
              : summary == null
              ? 'Marked present'
              : '${summary!.todayAttendance.absent} absent of ${summary!.todayAttendance.totalMarked}',
          icon: Icons.fact_check_rounded,
          hasError: summary?.attendanceError != null,
        ),
      if (preferences.showPendingFees)
        _MetricData(
          label: 'Pending Fees',
          value: summary == null || summary!.pendingFeesError != null
              ? null
              : '${summary!.pendingFees.pendingStudents}',
          helper: summary?.pendingFeesError != null
              ? 'Unable to load pending fees'
              : summary == null
              ? 'Outstanding this month'
              : '${_money(summary!.pendingFees.outstandingAmount)} outstanding',
          icon: Icons.account_balance_wallet_rounded,
          hasError: summary?.pendingFeesError != null,
        ),
      if (preferences.showTeacherOverview)
        _MetricData(
          label: 'Teachers',
          value: summary == null || summary!.peopleError != null
              ? null
              : '${summary!.teacherCount}',
          helper: summary?.peopleError != null
              ? 'Unable to load teacher overview'
              : summary?.pendingSignupError != null
              ? 'Unable to load pending signups'
              : '${summary?.pendingSignupCount ?? 0} pending signups',
          icon: Icons.co_present_rounded,
          hasError:
              summary?.peopleError != null ||
              summary?.pendingSignupError != null,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Overview Metrics', branding: branding),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: _cardDecoration(branding),
              child: GridView.builder(
                itemCount: metrics.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columnsForWidth(constraints.maxWidth),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: _metricAspectRatio(constraints.maxWidth),
                ),
                itemBuilder: (context, index) {
                  return _MetricCard(
                    data: metrics[index],
                    branding: branding,
                    loading: loading,
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.data,
    required this.branding,
    required this.loading,
  });

  final _MetricData data;
  final AppBranding branding;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: branding.primaryColor.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: branding.primaryColor.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, color: branding.primaryColor, size: 17),
              ),
              const Spacer(),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: loading || data.value == null
                      ? _LoadingLine(
                          width: 36,
                          height: 18,
                          color: data.hasError
                              ? Colors.red
                              : branding.primaryColor,
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            data.value!,
                            maxLines: 1,
                            style: TextStyle(
                              color: branding.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: data.hasError
                      ? Colors.red.shade700
                      : Colors.grey.shade600,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NeedsAttentionSection extends StatelessWidget {
  const _NeedsAttentionSection({
    required this.branding,
    required this.preferences,
    required this.summary,
    required this.loading,
  });

  final AppBranding branding;
  final AdminDashboardPreferences preferences;
  final AdminDashboardSummary? summary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (preferences.showConsecutiveAbsenceAlert)
        _AttentionCard(
          branding: branding,
          icon: Icons.warning_amber_rounded,
          title: 'Consecutive Absence',
          loading: loading,
          value: summary == null || summary!.absenceError != null
              ? null
              : '${summary!.absenceAlerts.length}',
          body: summary?.absenceError != null
              ? 'Unable to load consecutive absence alerts.'
              : summary == null
              ? 'Checking recorded attendance days.'
              : summary!.absenceAlerts.isEmpty
              ? 'No students have been absent for 3 consecutive attendance days.'
              : '${summary!.absenceAlerts.length} students have been absent for 3+ recorded attendance days.',
          actionLabel: 'View Students',
          onTap: summary == null || summary!.absenceError != null
              ? null
              : () => _showAbsenceDetails(
                  context,
                  branding,
                  summary!.absenceAlerts,
                ),
        ),
      if (preferences.showPendingFees)
        _AttentionCard(
          branding: branding,
          icon: Icons.currency_rupee_rounded,
          title: 'Pending Fees',
          loading: loading,
          value: summary == null || summary!.pendingFeesError != null
              ? null
              : _money(summary!.pendingFees.outstandingAmount),
          body: summary?.pendingFeesError != null
              ? 'Unable to load pending fee details.'
              : summary == null
              ? 'Checking active student fee records.'
              : summary!.pendingFees.pendingStudents == 0
              ? 'All fees are up to date for this month.'
              : '${summary!.pendingFees.pendingStudents} students have pending fee payments.',
          actionLabel: 'View Fees',
          onTap: () => Navigator.pushNamed(context, '/fees'),
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Needs Attention', branding: branding),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 760 && cards.length > 1;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: cardWidth, child: card),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.branding,
    required this.icon,
    required this.title,
    required this.loading,
    required this.value,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final AppBranding branding;
  final IconData icon;
  final String title;
  final bool loading;
  final String? value;
  final String body;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (loading || value == null)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 420),
                child: Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: Text(actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final actions = _quickActions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Quick Actions', branding: branding),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              itemCount: actions.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _quickActionColumns(constraints.maxWidth),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: constraints.maxWidth < 390 ? 1.32 : 3.2,
              ),
              itemBuilder: (context, index) {
                final action = actions[index];
                return _QuickActionButton(
                  action: action,
                  branding: branding,
                  onTap: () => Navigator.pushNamed(context, action.route),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.action,
    required this.branding,
    required this.onTap,
  });

  final _AdminNavigationItem action;
  final AppBranding branding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: branding.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: _cardDecoration(branding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(action.icon, color: branding.primaryColor, size: 24),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.grey.shade500,
                    size: 25,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: _QuickActionLabel(action.label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionLabel extends StatelessWidget {
  const _QuickActionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final words = label.split(' ');

    return FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final word in words)
            Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 15,
                height: 1.06,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicAppLinkSection extends StatelessWidget {
  const _PublicAppLinkSection({required this.branding});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final uri = branding.publicAppUri;
    final url = uri?.toString() ?? 'Public app link is not configured';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: branding.primaryColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: branding.primaryColor.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
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
                        'QR & App Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
              _LightAdminButton(
                icon: Icons.qr_code_rounded,
                label: 'View QR',
                onPressed: () =>
                    showCoachingQrDialog(context: context, branding: branding),
              ),
              _LightAdminButton(
                icon: Icons.copy_rounded,
                label: 'Copy Link',
                onPressed: () => copyPublicAppLink(context, branding),
              ),
              _LightAdminButton(
                icon: Icons.open_in_new_rounded,
                label: 'Open',
                onPressed: () => openPublicAppLink(context, branding),
              ),
              _LightAdminButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onPressed: () => sharePublicAppLink(context, branding),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightAdminButton extends StatelessWidget {
  const _LightAdminButton({
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
        minimumSize: const Size(112, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }
}

class _RecentUpdatesCard extends StatelessWidget {
  const _RecentUpdatesCard({required this.branding, required this.loading});

  final AppBranding branding;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(branding),
      child: Row(
        children: [
          Icon(Icons.campaign_rounded, color: branding.primaryColor),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Updates',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text('Open notices and class announcements.'),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/updates'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: const Text('Manage'),
          ),
        ],
      ),
    );
  }
}

class _DashboardErrorCard extends StatelessWidget {
  const _DashboardErrorCard({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Could not load admin dashboard: $error',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.branding});

  final String title;
  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: branding.textColor,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    this.hasError = false,
  });

  final String label;
  final String? value;
  final String helper;
  final IconData icon;
  final bool hasError;
}

class _AdminNavigationGroup {
  const _AdminNavigationGroup({required this.label, required this.items});

  final String label;
  final List<_AdminNavigationItem> items;
}

class _AdminNavigationItem {
  const _AdminNavigationItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

const _navigationGroups = [
  _AdminNavigationGroup(
    label: 'MANAGEMENT',
    items: [
      _AdminNavigationItem(
        label: 'Dashboard',
        icon: Icons.dashboard_rounded,
        route: '/teacher',
      ),
      _AdminNavigationItem(
        label: 'Students & Members',
        icon: Icons.groups_2_rounded,
        route: '/members',
      ),
      _AdminNavigationItem(
        label: 'Generate Password',
        icon: Icons.password_rounded,
        route: '/generate-password',
      ),
      _AdminNavigationItem(
        label: 'Attendance',
        icon: Icons.fact_check_rounded,
        route: '/attendance',
      ),
      _AdminNavigationItem(
        label: 'Fees',
        icon: Icons.account_balance_wallet_rounded,
        route: '/fees',
      ),
    ],
  ),
  _AdminNavigationGroup(
    label: 'ACADEMICS',
    items: [
      _AdminNavigationItem(
        label: 'Progress Reports',
        icon: Icons.trending_up_rounded,
        route: '/progress',
      ),
      _AdminNavigationItem(
        label: 'Performance',
        icon: Icons.analytics_rounded,
        route: '/performance',
      ),
      _AdminNavigationItem(
        label: 'Stars',
        icon: Icons.workspace_premium_rounded,
        route: '/feedback',
      ),
      _AdminNavigationItem(
        label: 'MCQ Tests',
        icon: Icons.quiz_rounded,
        route: '/mcq-tests',
      ),
    ],
  ),
  _AdminNavigationGroup(
    label: 'SYSTEM',
    items: [
      _AdminNavigationItem(
        label: 'Updates',
        icon: Icons.campaign_rounded,
        route: '/updates',
      ),
      _AdminNavigationItem(
        label: 'Settings',
        icon: Icons.admin_panel_settings_rounded,
        route: '/settings',
      ),
    ],
  ),
];

const _quickActions = [
  _AdminNavigationItem(
    label: 'Add Student',
    icon: Icons.person_add_alt_1_rounded,
    route: '/generate-password',
  ),
  _AdminNavigationItem(
    label: 'Mark Attendance',
    icon: Icons.fact_check_rounded,
    route: '/attendance',
  ),
  _AdminNavigationItem(
    label: 'Manage Fees',
    icon: Icons.account_balance_wallet_rounded,
    route: '/fees',
  ),
  _AdminNavigationItem(
    label: 'Create Update',
    icon: Icons.campaign_rounded,
    route: '/updates',
  ),
  _AdminNavigationItem(
    label: 'Progress Report',
    icon: Icons.trending_up_rounded,
    route: '/progress',
  ),
  _AdminNavigationItem(
    label: 'MCQ Tests',
    icon: Icons.quiz_rounded,
    route: '/mcq-tests',
  ),
];

void _showAbsenceDetails(
  BuildContext context,
  AppBranding branding,
  List<ConsecutiveAbsenceAlert> alerts,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height - 32,
            ),
            child: Material(
              color: branding.surfaceColor,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '3-Day Absence Students',
                            style: TextStyle(
                              color: branding.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (alerts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'No students have been absent for 3 consecutive attendance days.',
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: alerts.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final alert = alerts[index];
                            final student = alert.student;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFFFBEB),
                                foregroundColor: const Color(0xFFB45309),
                                child: Text('${alert.consecutiveDays}'),
                              ),
                              title: Text(
                                student.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  AcademicCatalog.classLabel(student.className),
                                  AcademicCatalog.batchLabel(student.batch),
                                  'Guardian: ${student.guardianContact}',
                                  if (alert.lastPresentDateKey != null)
                                    'Last present: ${alert.lastPresentDateKey}',
                                ].join(' • '),
                              ),
                              trailing: TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(context, '/attendance');
                                },
                                child: const Text('Attendance'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

BoxDecoration _cardDecoration(AppBranding branding) {
  return BoxDecoration(
    color: branding.surfaceColor,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

int _columnsForWidth(double width) {
  if (width >= 1040) return 4;
  if (width >= 760) return 4;
  if (width >= 560) return 4;
  if (width >= 300) return 2;
  return 1;
}

double _metricAspectRatio(double width) {
  if (width >= 760) return 2.75;
  if (width >= 560) return 2.35;
  if (width >= 300) return 2.25;
  return 1.9;
}

int _quickActionColumns(double width) {
  if (width >= 1080) return 4;
  if (width >= 760) return 3;
  if (width >= 360) return 2;
  return 1;
}

double _pageSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1200) return 28;
  if (width >= 760) return 22;
  return 14;
}

String _money(num value) {
  final formatted = NumberFormat.decimalPattern('en_IN').format(value.round());
  return 'Rs $formatted';
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
