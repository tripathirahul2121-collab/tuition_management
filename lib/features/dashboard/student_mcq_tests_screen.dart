import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';
import 'mcq_result_utils.dart';

String _formatMcqNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

String _formatMcqRuleNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r"0+$"), "")
      .replaceFirst(RegExp(r"\.$"), "");
}

String _formatMcqDuration(int seconds) {
  if (seconds >= (1 << 30)) return "Time not recorded";
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final minutes = safeSeconds ~/ 60;
  final secs = safeSeconds % 60;
  return "${minutes}m ${secs.toString().padLeft(2, "0")}s";
}

DateTime? _timestampToDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class StudentMCQTestsScreen extends StatefulWidget {
  const StudentMCQTestsScreen({super.key});

  @override
  State<StudentMCQTestsScreen> createState() => _StudentMCQTestsScreenState();
}

class _StudentMCQTestsScreenState extends State<StudentMCQTestsScreen> {
  Map<String, dynamic>? _activeTest;
  String? _activeTestId;
  DateTime? _activePrivateAttemptUntil;
  bool _activePracticeMode = false;
  final Map<String, Map<String, dynamic>> _practiceResults = {};

  void _startTest(
    String id,
    Map<String, dynamic> data, {
    bool practiceMode = false,
    DateTime? privateAttemptUntil,
  }) {
    setState(() {
      _activeTestId = id;
      _activeTest = data;
      _activePrivateAttemptUntil = privateAttemptUntil;
      _activePracticeMode = practiceMode;
    });
  }

  void _finishTest(Map<String, dynamic>? practiceResult) {
    setState(() {
      if (practiceResult != null && _activeTestId != null) {
        _practiceResults[_activeTestId!] = practiceResult;
      }
      _activeTestId = null;
      _activeTest = null;
      _activePrivateAttemptUntil = null;
      _activePracticeMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    if (_activeTestId != null && _activeTest != null) {
      return _TestRunner(
        testId: _activeTestId!,
        testData: _activeTest!,
        userData: userData,
        privateAttemptUntil: _activePrivateAttemptUntil,
        practiceMode: _activePracticeMode,
        onFinished: _finishTest,
      );
    }

    final className = userData["class"]?.toString() ?? "";
    final batchName = AcademicCatalog.normalizeBatch(
      userData["batch"]?.toString(),
    );
    final mobile = userData["mobile"]?.toString() ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("MCQ Tests"),
        backgroundColor: const Color(0xFFF5F7FB),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("mcq_tests")
            .where("class", isEqualTo: className)
            .where("status", isEqualTo: "released")
            .orderBy("scheduledAt", descending: true)
            .limit(QueryLimits.studentMcqTests)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Could not fetch MCQ tests. Please try again shortly.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("mcq_tests")
                .where("privateReopenMobiles", arrayContains: mobile)
                .snapshots(),
            builder: (context, privateSnapshot) {
              final docsById = <String, QueryDocumentSnapshot>{};

              for (final doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                if (AcademicCatalog.mcqBatchMatches(data, batchName)) {
                  docsById[doc.id] = doc;
                }
              }

              if (privateSnapshot.hasData) {
                for (final doc in privateSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data["status"]?.toString() == "released" &&
                      AcademicCatalog.mcqTargetClass(data) == className &&
                      AcademicCatalog.mcqBatchMatches(data, batchName)) {
                    docsById[doc.id] = doc;
                  }
                }
              }

              final docs = docsById.values.toList()
                ..sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  return mcqScheduledAt(bData).compareTo(mcqScheduledAt(aData));
                });

              if (docs.isEmpty) {
                return const Center(child: Text("No MCQ tests assigned yet"));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _StudentTestCard(
                    testId: doc.id,
                    data: data,
                    userData: userData,
                    practiceResult: _practiceResults[doc.id],
                    onStart: (privateAttemptUntil) => _startTest(
                      doc.id,
                      data,
                      privateAttemptUntil: privateAttemptUntil,
                    ),
                    onPractice: () =>
                        _startTest(doc.id, data, practiceMode: true),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StudentTestCard extends StatefulWidget {
  const _StudentTestCard({
    required this.testId,
    required this.data,
    required this.userData,
    required this.practiceResult,
    required this.onStart,
    required this.onPractice,
  });

  final String testId;
  final Map<String, dynamic> data;
  final Map<String, dynamic> userData;
  final Map<String, dynamic>? practiceResult;
  final ValueChanged<DateTime?> onStart;
  final VoidCallback onPractice;

  @override
  State<_StudentTestCard> createState() => _StudentTestCardState();
}

class _StudentTestCardState extends State<_StudentTestCard> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  bool _expanded = false;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _reopenRequestStream;

  @override
  void initState() {
    super.initState();
    _reopenRequestStream = _buildReopenRequestStream();
    _startClockIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _StudentTestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.testId != widget.testId ||
        oldWidget.userData["mobile"] != widget.userData["mobile"]) {
      _reopenRequestStream = _buildReopenRequestStream();
    }
    _startClockIfNeeded();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startClockIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _buildReopenRequestStream() {
    final mobile = widget.userData["mobile"]?.toString() ?? "";
    return FirebaseFirestore.instance
        .collection("mcq_tests")
        .doc(widget.testId)
        .collection("reopenRequests")
        .doc(mobile)
        .snapshots(includeMetadataChanges: true);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = widget.userData["mobile"]?.toString() ?? "";
    final scheduledAt = mcqScheduledAt(widget.data);
    final joinedAt = _timestampToDate(widget.userData["createdAt"]);
    final isHomeTest = widget.data["testLocation"]?.toString() == "home";
    final canStart = !_now.isBefore(scheduledAt);
    final isEnded = isMcqTestEnded(widget.data, _now);
    final endedBeforeAdmission =
        joinedAt != null && !joinedAt.isBefore(mcqEndsAt(widget.data));
    final questions = widget.data["questions"];
    final questionCount = questions is List ? questions.length : 0;
    final totalMarks =
        double.tryParse(widget.data["totalMarks"]?.toString() ?? "") ??
        questionCount *
            (double.tryParse(
                  widget.data["marksPerQuestion"]?.toString() ?? "",
                ) ??
                1);
    final totalTimeMinutes =
        int.tryParse(widget.data["totalTimeMinutes"]?.toString() ?? "") ?? 0;
    final negativeMarks = widget.data["negativeMarkingEnabled"] == true
        ? (double.tryParse(
                widget.data["negativeMarksPerQuestion"]?.toString() ?? "",
              ) ??
              0.0)
        : 0.0;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("mcq_tests")
          .doc(widget.testId)
          .collection("results")
          .doc(mobile)
          .snapshots(includeMetadataChanges: true),
      builder: (context, resultSnapshot) {
        if (resultSnapshot.hasError && !resultSnapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Could not fetch this result. Saved data will appear when network improves.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final result = resultSnapshot.data?.data();
        final submitted = result != null;
        final practiceOnlyForNewAdmission = !submitted && endedBeforeAdmission;
        final syncing =
            submitted &&
            (resultSnapshot.data?.metadata.hasPendingWrites ?? false);

        if (isHomeTest &&
            resultSnapshot.hasData &&
            !submitted &&
            canStart &&
            !isEnded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onStart(null);
          });
        }

        final computed = result == null
            ? null
            : computeMcqResult(widget.data, result);
        final showDetails = !submitted || _expanded;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _reopenRequestStream,
          builder: (context, reopenSnapshot) {
            final reopenData = reopenSnapshot.data?.data();
            final privateAttemptUntil = reopenData?["availableUntil"];
            final privateAttemptEndsAt = privateAttemptUntil is Timestamp
                ? privateAttemptUntil.toDate()
                : null;
            final privateAttemptActive =
                reopenData?["active"] == true &&
                privateAttemptEndsAt != null &&
                privateAttemptEndsAt.isAfter(_now) &&
                !submitted;
            final canStartNow = privateAttemptActive || (canStart && !isEnded);
            final canPracticeAfterEnd = isEnded && !privateAttemptActive;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFD),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _expanded
                      ? const Color(0xFF94A3B8)
                      : Colors.black.withValues(alpha: 0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.quiz,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.data["chapterName"]?.toString() ??
                                    "MCQ Test",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                "$questionCount questions • ${DateFormat("dd MMM, hh:mm a").format(scheduledAt)}",
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        if (submitted)
                          IconButton(
                            tooltip: _expanded ? "Collapse" : "Expand",
                            onPressed: () {
                              setState(() => _expanded = !_expanded);
                            },
                            icon: AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TestInfoPill(
                          icon: isHomeTest ? Icons.home_work : Icons.school,
                          label: isHomeTest ? "Home test" : "Tuition test",
                        ),
                        _TestInfoPill(
                          icon: Icons.grade,
                          label: "${_formatMcqNumber(totalMarks)} marks",
                        ),
                        if (totalTimeMinutes > 0)
                          _TestInfoPill(
                            icon: Icons.timer,
                            label: "$totalTimeMinutes min",
                          ),
                        _TestInfoPill(
                          icon: Icons.remove_circle_outline,
                          label:
                              "Negative ${_formatMcqRuleNumber(negativeMarks)}",
                        ),
                        _TestInfoPill(
                          icon: submitted
                              ? Icons.check_circle
                              : privateAttemptActive
                              ? Icons.lock_open
                              : canStart && !isEnded
                              ? Icons.play_circle
                              : Icons.schedule,
                          label: submitted
                              ? syncing
                                    ? "Submitted • Syncing"
                                    : "Submitted"
                              : privateAttemptActive
                              ? "Private attempt"
                              : isEnded
                              ? "Closed"
                              : canStart
                              ? "Open now"
                              : _formatStartCountdown(
                                  scheduledAt.difference(_now),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (result != null && computed != null) ...[
                      _SubmittedSummaryBar(
                        score: _formatMcqNumber(computed.score),
                        percentage: _formatMcqNumber(computed.percentage),
                        syncing: syncing,
                        expanded: _expanded,
                        onToggle: () => setState(() => _expanded = !_expanded),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: showDetails
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _ResultSummary(
                                  result: result,
                                  testData: widget.data,
                                  testId: widget.testId,
                                  currentMobile: mobile,
                                  now: _now,
                                  practiceResult: widget.practiceResult,
                                  onPractice: widget.onPractice,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ] else if (practiceOnlyForNewAdmission) ...[
                      if (widget.practiceResult != null) ...[
                        _PracticeResultBanner(
                          result: computeMcqResult(
                            widget.data,
                            widget.practiceResult!,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onPractice,
                          icon: const Icon(Icons.replay),
                          label: const Text("Practice Test"),
                        ),
                      ),
                    ] else if (isHomeTest)
                      privateAttemptActive || isEnded || canStart
                          ? SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: privateAttemptActive
                                    ? () => widget.onStart(privateAttemptEndsAt)
                                    : canPracticeAfterEnd
                                    ? widget.onPractice
                                    : null,
                                icon: Icon(
                                  privateAttemptActive
                                      ? Icons.play_arrow
                                      : isEnded
                                      ? Icons.replay
                                      : Icons.timer,
                                ),
                                label: Text(
                                  privateAttemptActive
                                      ? "Start Special Attempt"
                                      : isEnded
                                      ? "Practice Test"
                                      : "Starting now...",
                                ),
                              ),
                            )
                          : _LaunchCountdownPanel(
                              remaining: scheduledAt.difference(_now),
                              homeTest: true,
                            )
                    else
                      canStartNow || isEnded
                          ? SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: canStartNow
                                    ? () => widget.onStart(privateAttemptEndsAt)
                                    : canPracticeAfterEnd
                                    ? widget.onPractice
                                    : null,
                                icon: Icon(
                                  isEnded && !privateAttemptActive
                                      ? Icons.replay
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  privateAttemptActive
                                      ? "Start Special Attempt"
                                      : isEnded
                                      ? "Practice Test"
                                      : "Start Test",
                                ),
                              ),
                            )
                          : _LaunchCountdownPanel(
                              remaining: scheduledAt.difference(_now),
                            ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _formatStartCountdown(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    if (safe.inSeconds <= 10) {
      final label = safe.inSeconds == 1 ? "second" : "seconds";
      return "${safe.inSeconds} $label left";
    }
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
    }
    return "$minutes:${seconds.toString().padLeft(2, "0")}";
  }
}

class _LaunchCountdownPanel extends StatelessWidget {
  const _LaunchCountdownPanel({required this.remaining, this.homeTest = false});

  final Duration remaining;
  final bool homeTest;

  @override
  Widget build(BuildContext context) {
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final secondsLeft = safe.inSeconds;
    final urgent = secondsLeft <= 10;
    final progress = secondsLeft <= 60
        ? (60 - secondsLeft).clamp(0, 60) / 60
        : 0.0;
    final accent = urgent ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
    final bg = urgent ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF);
    final border = urgent ? const Color(0xFFFCA5A5) : const Color(0xFFBFDBFE);
    final title = _StudentTestCardState._formatStartCountdown(safe);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              urgent ? Icons.timer_10_select : Icons.hourglass_top,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    title,
                    key: ValueKey(title),
                    style: TextStyle(
                      color: urgent
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF1E3A8A),
                      fontSize: urgent ? 18 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  homeTest
                      ? "The test will open automatically."
                      : "Start button unlocks when the countdown ends.",
                  style: TextStyle(
                    color: urgent
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress == 0 ? null : progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
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

class _TestInfoPill extends StatelessWidget {
  const _TestInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TestRunner extends StatefulWidget {
  const _TestRunner({
    required this.testId,
    required this.testData,
    required this.userData,
    required this.privateAttemptUntil,
    required this.practiceMode,
    required this.onFinished,
  });

  final String testId;
  final Map<String, dynamic> testData;
  final Map<String, dynamic> userData;
  final DateTime? privateAttemptUntil;
  final bool practiceMode;
  final ValueChanged<Map<String, dynamic>?> onFinished;

  @override
  State<_TestRunner> createState() => _TestRunnerState();
}

class _TestRunnerState extends State<_TestRunner> with WidgetsBindingObserver {
  late final List<Map<String, dynamic>> _questions;
  late final int _secondsPerQuestion;
  late final int _totalAllowedSeconds;
  late final String _timingMode;
  late final String _testLocation;
  late final DateTime _testStartedAt;
  late final DateTime _testEndsAt;
  late DateTime _questionStartedAt;
  late int _remainingSeconds;
  late int _totalRemainingSeconds;
  Timer? _timer;
  int _currentIndex = 0;
  int _screenSwitchCount = 0;
  bool _submitting = false;
  bool _screenSwitchPenaltyActive = false;
  bool _showSkippedBlock = false;
  Map<String, dynamic>? _practiceFinalResult;
  final Map<int, int> _answers = {};
  final Set<int> _skippedQuestionIndexes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rawQuestions = widget.testData["questions"];
    final mobile = widget.userData["mobile"]?.toString() ?? "";
    final attemptSeed = widget.practiceMode
        ? "${widget.testId}-$mobile-practice-${DateTime.now().millisecondsSinceEpoch}"
        : "${widget.testId}-$mobile";
    _questions = _questionsForStudent(
      rawQuestions,
      attemptSeed,
      shuffleOptions: widget.practiceMode,
    );
    _secondsPerQuestion =
        int.tryParse(widget.testData["secondsPerQuestion"]?.toString() ?? "") ??
        10;
    _timingMode = widget.testData["timingMode"]?.toString() == "totalOnly"
        ? "totalOnly"
        : "perQuestion";
    _testLocation = widget.testData["testLocation"]?.toString() == "home"
        ? "home"
        : "tuition";
    final totalTimeMinutes =
        int.tryParse(widget.testData["totalTimeMinutes"]?.toString() ?? "") ??
        0;
    _totalAllowedSeconds = totalTimeMinutes > 0
        ? totalTimeMinutes * 60
        : _questions.length * _secondsPerQuestion;
    _remainingSeconds = _secondsPerQuestion;
    final scheduledAt = mcqScheduledAt(widget.testData);
    _testEndsAt = widget.practiceMode
        ? DateTime.now().add(Duration(seconds: _totalAllowedSeconds))
        : widget.privateAttemptUntil ?? mcqEndsAt(widget.testData);
    _totalRemainingSeconds = max(
      0,
      _testEndsAt.difference(DateTime.now()).inSeconds,
    );
    _testStartedAt = widget.practiceMode
        ? DateTime.now()
        : widget.privateAttemptUntil != null
        ? DateTime.now()
        : _testLocation == "home"
        ? scheduledAt
        : DateTime.now();
    _questionStartedAt = _testStartedAt;
    _startTimer();
  }

  List<Map<String, dynamic>> _questionsForStudent(
    dynamic rawQuestions,
    String seedKey, {
    required bool shuffleOptions,
  }) {
    if (rawQuestions is! List) return [];

    final questions = <Map<String, dynamic>>[];
    for (var i = 0; i < rawQuestions.length; i++) {
      final rawQuestion = rawQuestions[i];
      if (rawQuestion is! Map) continue;

      final question = {
        ...Map<String, dynamic>.from(rawQuestion),
        "_originalIndex": i,
      };
      if (shuffleOptions) {
        _shufflePracticeOptions(question, "$seedKey-options-$i");
      }
      questions.add(question);
    }

    questions.shuffle(Random(_stableSeed(seedKey)));
    return questions;
  }

  void _shufflePracticeOptions(Map<String, dynamic> question, String seedKey) {
    final rawOptions = question["options"];
    if (rawOptions is! List || rawOptions.length < 2) return;

    final options = rawOptions.toList();
    final optionOrder = List.generate(options.length, (index) => index);
    optionOrder.shuffle(Random(_stableSeed(seedKey)));

    final originalCorrectIndex =
        int.tryParse(question["correctIndex"]?.toString() ?? "") ?? 0;
    if (originalCorrectIndex < 0 ||
        originalCorrectIndex >= optionOrder.length) {
      return;
    }

    var displayedCorrectIndex = optionOrder.indexOf(originalCorrectIndex);
    if (displayedCorrectIndex == originalCorrectIndex) {
      final swapIndex = (displayedCorrectIndex + 1) % optionOrder.length;
      final temp = optionOrder[displayedCorrectIndex];
      optionOrder[displayedCorrectIndex] = optionOrder[swapIndex];
      optionOrder[swapIndex] = temp;
      displayedCorrectIndex = optionOrder.indexOf(originalCorrectIndex);
    }

    question["options"] = optionOrder.map((index) => options[index]).toList();
    question["correctIndex"] = displayedCorrectIndex;
    question["_optionOrder"] = optionOrder;
  }

  int _stableSeed(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_practiceFinalResult != null) return;
    if (_submitting) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _markCurrentQuestionUnattemptedForScreenSwitch();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _screenSwitchPenaltyActive = false;
      _syncTimers();
    }
  }

  void _markCurrentQuestionUnattemptedForScreenSwitch() {
    if (!mounted || _questions.isEmpty || _screenSwitchPenaltyActive) return;

    _screenSwitchPenaltyActive = true;
    _screenSwitchCount++;
    _answers.remove(_currentIndex);

    if (_timingMode == "totalOnly") {
      setState(() {
        _skippedQuestionIndexes.add(_currentIndex);
      });
      return;
    }

    if (_currentIndex >= _questions.length - 1) {
      _submit();
      return;
    }

    setState(() {
      _currentIndex++;
      _questionStartedAt = DateTime.now();
      _remainingSeconds = _secondsPerQuestion;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncTimers();
    });
  }

  void _syncTimers() {
    if (!mounted || _submitting) return;

    final now = DateTime.now();
    final totalRemaining = _testEndsAt.difference(now).inSeconds;

    if (totalRemaining <= 0) {
      _submit();
      return;
    }

    if (_timingMode == "perQuestion") {
      while (_currentIndex < _questions.length - 1 &&
          !now.isBefore(
            _questionStartedAt.add(Duration(seconds: _secondsPerQuestion)),
          )) {
        _currentIndex++;
        _questionStartedAt = _questionStartedAt.add(
          Duration(seconds: _secondsPerQuestion),
        );
      }

      final questionRemaining = _questionStartedAt
          .add(Duration(seconds: _secondsPerQuestion))
          .difference(now)
          .inSeconds;

      if (_currentIndex == _questions.length - 1 && questionRemaining <= 0) {
        _submit();
        return;
      }

      setState(() {
        _remainingSeconds = questionRemaining
            .clamp(0, _secondsPerQuestion)
            .toInt();
        _totalRemainingSeconds = totalRemaining;
      });
    } else {
      setState(() {
        _remainingSeconds = 0;
        _totalRemainingSeconds = totalRemaining;
      });
    }
  }

  void _goNext() {
    if (_timingMode == "totalOnly") {
      _goNextInTotalTimeMode();
      return;
    }

    if (_currentIndex >= _questions.length - 1) {
      _submit();
      return;
    }

    setState(() {
      _currentIndex++;
      _questionStartedAt = DateTime.now();
      _remainingSeconds = _secondsPerQuestion;
    });
  }

  void _goNextInTotalTimeMode() {
    final unanswered = !_answers.containsKey(_currentIndex);

    setState(() {
      if (unanswered) {
        _skippedQuestionIndexes.add(_currentIndex);
      } else {
        _skippedQuestionIndexes.remove(_currentIndex);
      }

      _showSkippedBlock = false;

      if (_currentIndex >= _questions.length - 1) {
        return;
      }

      _currentIndex++;
      _questionStartedAt = DateTime.now();
    });
  }

  void _selectAnswer(int questionIndex, int optionIndex) {
    setState(() {
      _answers[questionIndex] = optionIndex;
      _skippedQuestionIndexes.remove(questionIndex);
    });
  }

  void _openSkippedBlock() {
    if (_skippedQuestionIndexes.isEmpty) return;
    setState(() => _showSkippedBlock = true);
  }

  void _closeSkippedBlock() {
    setState(() => _showSkippedBlock = false);
  }

  Future<void> _exitAttempt() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(widget.practiceMode ? "Exit Practice?" : "Exit Test?"),
          content: Text(
            widget.practiceMode
                ? "Your current practice answers will be discarded."
                : "Your current answers will not be submitted.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Stay"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Exit"),
            ),
          ],
        );
      },
    );

    if (shouldLeave != true || !mounted) return;
    _timer?.cancel();
    widget.onFinished(_practiceFinalResult);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _timer?.cancel();

    setState(() => _submitting = true);

    final marksPerQuestion =
        double.tryParse(
          widget.testData["marksPerQuestion"]?.toString() ?? "",
        ) ??
        1;
    final negativeMarks =
        double.tryParse(
          widget.testData["negativeMarksPerQuestion"]?.toString() ?? "",
        ) ??
        0;

    var correctCount = 0;
    var wrongCount = 0;

    for (var i = 0; i < _questions.length; i++) {
      final selected = _answers[i];
      if (selected == null) continue;

      final correctIndex =
          int.tryParse(_questions[i]["correctIndex"]?.toString() ?? "") ?? 0;

      if (selected == correctIndex) {
        correctCount++;
      } else {
        wrongCount++;
      }
    }

    final score =
        (correctCount * marksPerQuestion) - (wrongCount * negativeMarks);
    final mobile = widget.userData["mobile"]?.toString() ?? "";

    final resultRef = FirebaseFirestore.instance
        .collection("mcq_tests")
        .doc(widget.testId)
        .collection("results")
        .doc(mobile);
    final testRef = FirebaseFirestore.instance
        .collection("mcq_tests")
        .doc(widget.testId);
    final timeTakenSeconds = DateTime.now()
        .difference(_testStartedAt)
        .inSeconds
        .clamp(0, _totalAllowedSeconds)
        .toInt();
    final answersForResult = _answers.map((key, value) {
      final optionOrder = key >= 0 && key < _questions.length
          ? _questions[key]["_optionOrder"]
          : null;
      final originalOptionIndex =
          optionOrder is List && value >= 0 && value < optionOrder.length
          ? int.tryParse(optionOrder[value].toString()) ?? value
          : value;
      return MapEntry(key.toString(), originalOptionIndex);
    });
    final resultData = {
      "studentName": widget.userData["name"]?.toString() ?? "Student",
      "mobile": mobile,
      "class": widget.userData["class"]?.toString() ?? "",
      "batch": AcademicCatalog.normalizeBatch(
        widget.userData["batch"]?.toString(),
      ),
      "score": score,
      "correctCount": correctCount,
      "wrongCount": wrongCount,
      "unansweredCount": _questions.length - correctCount - wrongCount,
      "totalQuestions": _questions.length,
      "totalMarks": widget.testData["totalMarks"] ?? 0,
      "chapterName": widget.testData["chapterName"]?.toString() ?? "",
      "scheduledAt": widget.testData["scheduledAt"],
      "answers": answersForResult,
      "questionOrder": _questions.asMap().entries.map((entry) {
        return int.tryParse(entry.value["_originalIndex"]?.toString() ?? "") ??
            entry.key;
      }).toList(),
      "timeTakenSeconds": timeTakenSeconds,
      "screenSwitchCount": _screenSwitchCount,
      "submittedAtLocal": Timestamp.now(),
      "submittedAt": widget.practiceMode
          ? Timestamp.now()
          : FieldValue.serverTimestamp(),
      "practiceOnly": widget.practiceMode,
      "countsForMerit": !widget.practiceMode,
      "attemptType": widget.practiceMode ? "practice" : "official",
    };

    if (widget.practiceMode) {
      unawaited(() async {
        try {
          await testRef.collection("practice_results").add({
            ...resultData,
            "sourceResultDoc": mobile,
            "createdAt": FieldValue.serverTimestamp(),
          });
        } catch (error) {
          debugPrint("MCQ practice result sync failed: $error");
        }
      }());
      if (!mounted) return;
      setState(() {
        _practiceFinalResult = resultData;
        _submitting = false;
      });
      return;
    }

    try {
      unawaited(
        resultRef.set(resultData, SetOptions(merge: true)).catchError((error) {
          debugPrint("MCQ result sync failed: $error");
        }),
      );
      unawaited(_updateSubmissionStats(testRef, score));
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not save submission. Please try again."),
        ),
      );
      _startTimer();
      return;
    }

    if (!mounted) return;
    widget.onFinished(null);
  }

  Future<void> _updateSubmissionStats(
    DocumentReference<Map<String, dynamic>> testRef,
    double score,
  ) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final testSnapshot = await transaction.get(testRef);
        final currentTopScore = testSnapshot.exists
            ? double.tryParse(
                    testSnapshot.data()?["topScore"]?.toString() ?? "",
                  ) ??
                  score
            : score;

        transaction.set(testRef, {
          "submissionCount": FieldValue.increment(1),
          "totalSubmittedScore": FieldValue.increment(score),
          "topScore": score > currentTopScore ? score : currentTopScore,
          "lastResultAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (error) {
      debugPrint("MCQ submission stats sync failed: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("MCQ Test")),
        body: const Center(child: Text("No questions found")),
      );
    }

    final question = _questions[_currentIndex];
    final selectedIndex = _answers[_currentIndex];
    final showSkippedBlock = _timingMode == "totalOnly" && _showSkippedBlock;
    final isLastQuestion = _currentIndex >= _questions.length - 1;
    final showSubmitSlider =
        !_submitting &&
        (showSkippedBlock ||
            (_timingMode == "totalOnly" &&
                isLastQuestion &&
                _skippedQuestionIndexes.isEmpty) ||
            (_timingMode != "totalOnly" && isLastQuestion));

    if (widget.practiceMode && _practiceFinalResult != null) {
      return _PracticeCompleteScreen(
        result: computeMcqResult(widget.testData, _practiceFinalResult!),
        onBack: () => widget.onFinished(_practiceFinalResult),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        leading: IconButton(
          tooltip: "Back",
          onPressed: _submitting ? null : _exitAttempt,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          showSkippedBlock
              ? "Skipped Questions"
              : widget.practiceMode
              ? "Practice ${_currentIndex + 1}/${_questions.length}"
              : "Question ${_currentIndex + 1}/${_questions.length}",
        ),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF5F7FB),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (_currentIndex + 1) / _questions.length,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_timingMode == "perQuestion") ...[
                      Chip(
                        avatar: const Icon(Icons.timer, size: 18),
                        label: Text(
                          "Q ${_remainingSeconds}s",
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Chip(
                      avatar: const Icon(Icons.hourglass_bottom, size: 18),
                      label: Text(
                        _formatTotalTime(_totalRemainingSeconds),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                if (_timingMode == "totalOnly") ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _skippedQuestionIndexes.isEmpty
                              ? null
                              : _openSkippedBlock,
                          icon: const Icon(Icons.pending_actions),
                          label: Text(
                            "Skipped ${_skippedQuestionIndexes.length}",
                          ),
                        ),
                      ),
                      if (showSkippedBlock) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: "Back to current question",
                          onPressed: _closeSkippedBlock,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Expanded(
                  child: showSkippedBlock
                      ? _SkippedQuestionsBlock(
                          questions: _questions,
                          skippedQuestionIndexes: _skippedQuestionIndexes,
                          answers: _answers,
                          practiceMode: widget.practiceMode,
                          onSelectAnswer: _selectAnswer,
                        )
                      : _AttemptQuestionView(
                          question: question,
                          selectedIndex: selectedIndex,
                          practiceMode: widget.practiceMode,
                          onSelectAnswer: (optionIndex) =>
                              _selectAnswer(_currentIndex, optionIndex),
                        ),
                ),
                if (_timingMode == "totalOnly") ...[
                  if (showSubmitSlider)
                    _SlideSubmitControl(
                      submitting: _submitting,
                      onSubmit: _submit,
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _submitting || showSkippedBlock
                            ? null
                            : () {
                                if (isLastQuestion &&
                                    _skippedQuestionIndexes.isNotEmpty) {
                                  _openSkippedBlock();
                                  return;
                                }
                                _goNext();
                              },
                        icon: Icon(
                          isLastQuestion && _skippedQuestionIndexes.isNotEmpty
                              ? Icons.pending_actions
                              : Icons.arrow_forward,
                        ),
                        label: Text(
                          isLastQuestion && _skippedQuestionIndexes.isNotEmpty
                              ? "Review Skipped"
                              : "Next Question",
                        ),
                      ),
                    ),
                ] else ...[
                  if (showSubmitSlider)
                    _SlideSubmitControl(
                      submitting: _submitting,
                      onSubmit: _submit,
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _submitting ? null : _goNext,
                        child: const Text("Next Question"),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTotalTime(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final secs = safeSeconds % 60;
    return "$minutes:${secs.toString().padLeft(2, "0")}";
  }
}

class _AttemptQuestionView extends StatelessWidget {
  const _AttemptQuestionView({
    required this.question,
    required this.selectedIndex,
    required this.practiceMode,
    required this.onSelectAnswer,
  });

  final Map<String, dynamic> question;
  final int? selectedIndex;
  final bool practiceMode;
  final ValueChanged<int> onSelectAnswer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              question["question"]?.toString() ?? "",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 28),
            _QuestionOptions(
              question: question,
              selectedIndex: selectedIndex,
              practiceMode: practiceMode,
              onSelectAnswer: onSelectAnswer,
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideSubmitControl extends StatefulWidget {
  const _SlideSubmitControl({required this.submitting, required this.onSubmit});

  final bool submitting;
  final VoidCallback onSubmit;

  @override
  State<_SlideSubmitControl> createState() => _SlideSubmitControlState();
}

class _SlideSubmitControlState extends State<_SlideSubmitControl> {
  double _dragFraction = 0;
  bool _submitted = false;

  void _updateDrag(DragUpdateDetails details, double maxWidth) {
    if (widget.submitting || _submitted || maxWidth <= 0) return;
    setState(() {
      _dragFraction = (_dragFraction + details.primaryDelta! / maxWidth).clamp(
        0.0,
        1.0,
      );
    });
  }

  void _endDrag() {
    if (widget.submitting || _submitted) return;
    if (_dragFraction >= 0.82) {
      setState(() {
        _dragFraction = 1;
        _submitted = true;
      });
      widget.onSubmit();
      return;
    }

    setState(() => _dragFraction = 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 62.0;
        const knobSize = 54.0;
        final travel = (constraints.maxWidth - knobSize - 10).clamp(
          0.0,
          10000.0,
        );
        final knobLeft = 5 + (travel * _dragFraction);

        return Opacity(
          opacity: widget.submitting ? 0.72 : 1,
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF111827), Color(0xFF256D64)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF111827).withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _dragFraction,
                      color: const Color(0xFF10B981),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
                Text(
                  widget.submitting
                      ? "Submitting Test..."
                      : "Slide to Submit Test",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Positioned(
                  right: 18,
                  child: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                Positioned(
                  left: knobLeft,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) =>
                        _updateDrag(details, travel),
                    onHorizontalDragEnd: (_) => _endDrag(),
                    child: Container(
                      height: knobSize,
                      width: knobSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        _submitted ? Icons.check : Icons.arrow_forward,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkippedQuestionsBlock extends StatelessWidget {
  const _SkippedQuestionsBlock({
    required this.questions,
    required this.skippedQuestionIndexes,
    required this.answers,
    required this.practiceMode,
    required this.onSelectAnswer,
  });

  final List<Map<String, dynamic>> questions;
  final Set<int> skippedQuestionIndexes;
  final Map<int, int> answers;
  final bool practiceMode;
  final void Function(int questionIndex, int optionIndex) onSelectAnswer;

  @override
  Widget build(BuildContext context) {
    final skippedIndexes = skippedQuestionIndexes.toList()..sort();

    if (skippedIndexes.isEmpty) {
      return const Center(
        child: Text(
          "No skipped questions left",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    return ListView.separated(
      itemCount: skippedIndexes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final questionIndex = skippedIndexes[index];
        final question = questions[questionIndex];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Question ${questionIndex + 1}",
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                question["question"]?.toString() ?? "",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              _QuestionOptions(
                question: question,
                selectedIndex: answers[questionIndex],
                practiceMode: practiceMode,
                onSelectAnswer: (optionIndex) {
                  onSelectAnswer(questionIndex, optionIndex);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuestionOptions extends StatelessWidget {
  const _QuestionOptions({
    required this.question,
    required this.selectedIndex,
    required this.practiceMode,
    required this.onSelectAnswer,
  });

  final Map<String, dynamic> question;
  final int? selectedIndex;
  final bool practiceMode;
  final ValueChanged<int> onSelectAnswer;

  @override
  Widget build(BuildContext context) {
    final optionsRaw = question["options"];
    final options = optionsRaw is List
        ? optionsRaw.map((option) => option.toString()).toList()
        : <String>[];
    final correctIndex =
        int.tryParse(question["correctIndex"]?.toString() ?? "") ?? 0;

    return Column(
      children: options.asMap().entries.map((entry) {
        final selected = selectedIndex == entry.key;
        final showPracticeFeedback = practiceMode && selectedIndex != null;
        final isCorrectOption = entry.key == correctIndex;
        final isSelectedWrong =
            showPracticeFeedback && selected && !isCorrectOption;
        final optionColor = showPracticeFeedback
            ? isCorrectOption
                  ? const Color(0xFFECFDF5)
                  : isSelectedWrong
                  ? const Color(0xFFFEF2F2)
                  : Colors.white
            : selected
            ? const Color(0xFFDBEAFE)
            : Colors.white;
        final borderColor = showPracticeFeedback
            ? isCorrectOption
                  ? const Color(0xFF10B981)
                  : isSelectedWrong
                  ? const Color(0xFFEF4444)
                  : Colors.black.withValues(alpha: 0.08)
            : selected
            ? const Color(0xFF2563EB)
            : Colors.black.withValues(alpha: 0.08);
        final textColor = isSelectedWrong
            ? const Color(0xFF991B1B)
            : isCorrectOption && showPracticeFeedback
            ? const Color(0xFF047857)
            : const Color(0xFF111827);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: practiceMode && selectedIndex != null
                ? null
                : () => onSelectAnswer(entry.key),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: optionColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor,
                  width: selected || (showPracticeFeedback && isCorrectOption)
                      ? 2
                      : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (showPracticeFeedback && isCorrectOption)
                    const Icon(Icons.check_circle, color: Color(0xFF059669))
                  else if (isSelectedWrong)
                    const Icon(Icons.cancel, color: Color(0xFFDC2626)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PracticeCompleteScreen extends StatelessWidget {
  const _PracticeCompleteScreen({required this.result, required this.onBack});

  final McqComputedResult result;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final percent = result.totalMarks <= 0
        ? 0.0
        : (result.score / result.totalMarks).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text("Practice Result"),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF5F7FB),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF101820), Color(0xFF256D64)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 76,
                          width: 76,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFC857,
                            ).withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFFFFC857,
                              ).withValues(alpha: 0.34),
                            ),
                          ),
                          child: const Icon(
                            Icons.psychology_alt,
                            color: Color(0xFFFFC857),
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          "Practice Complete",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${_formatMcqNumber(result.score)} / ${_formatMcqNumber(result.totalMarks)}",
                          style: const TextStyle(
                            color: Color(0xFFFFD77A),
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 10,
                            color: const Color(0xFFFFC857),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _PracticeStat(
                              label: "Correct",
                              value: result.correctCount.toString(),
                              color: const Color(0xFF34D399),
                            ),
                            const SizedBox(width: 8),
                            _PracticeStat(
                              label: "Incorrect",
                              value: result.wrongCount.toString(),
                              color: const Color(0xFFF87171),
                            ),
                            const SizedBox(width: 8),
                            _PracticeStat(
                              label: "Skipped",
                              value: result.unansweredCount.toString(),
                              color: const Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Practice marks are only for self-check and are not added to the merit list.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFCFE0E4),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Back to Tests"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeStat extends StatelessWidget {
  const _PracticeStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCFE0E4),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmittedSummaryBar extends StatelessWidget {
  const _SubmittedSummaryBar({
    required this.score,
    required this.percentage,
    required this.syncing,
    required this.expanded,
    required this.onToggle,
  });

  final String score;
  final String percentage;
  final bool syncing;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onToggle,
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF10B981)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF059669)),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: syncing ? "Submitted • Syncing • " : "Submitted • ",
                    ),
                    const TextSpan(text: "Score "),
                    TextSpan(
                      text: score,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const TextSpan(text: " • "),
                    TextSpan(
                      text: "$percentage%",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              expanded ? "Hide" : "Details",
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.result,
    required this.testData,
    required this.testId,
    required this.currentMobile,
    required this.now,
    required this.practiceResult,
    required this.onPractice,
  });

  final Map<String, dynamic> result;
  final Map<String, dynamic> testData;
  final String testId;
  final String currentMobile;
  final DateTime now;
  final Map<String, dynamic>? practiceResult;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final computed = computeMcqResult(testData, result);
    final practiceComputed = practiceResult == null
        ? null
        : computeMcqResult(testData, practiceResult!);
    final negativeMarks =
        double.tryParse(
          testData["negativeMarksPerQuestion"]?.toString() ?? "",
        ) ??
        0.0;
    final negativeEnabled = testData["negativeMarkingEnabled"] == true;

    return Column(
      children: [
        _NegativeMarkingBanner(value: negativeEnabled ? negativeMarks : 0),
        const SizedBox(height: 10),
        _ResultBreakdownStrip(result: computed),
        if (practiceComputed != null) ...[
          const SizedBox(height: 10),
          _PracticeResultBanner(result: practiceComputed),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPractice,
            icon: const Icon(Icons.replay),
            label: const Text("Reappear for Practice"),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showAnswerReview(context),
            icon: const Icon(Icons.fact_check),
            label: const Text("Review Answers"),
          ),
        ),
        const SizedBox(height: 12),
        _MeritList(
          testId: testId,
          testData: testData,
          currentMobile: currentMobile,
        ),
      ],
    );
  }

  void _showAnswerReview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AnswerReviewSheet(
        result: result,
        testData: testData,
        showTeacherOrder: isMcqTestEnded(testData, now),
      ),
    );
  }
}

class _ResultBreakdownStrip extends StatelessWidget {
  const _ResultBreakdownStrip({required this.result});

  final McqComputedResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ReviewStat(
          icon: Icons.check_circle,
          label: "Correct",
          value: "${result.correctCount}",
          color: Colors.green,
        ),
        const SizedBox(width: 8),
        _ReviewStat(
          icon: Icons.cancel,
          label: "Incorrect",
          value: "${result.wrongCount}",
          color: Colors.red,
        ),
        const SizedBox(width: 8),
        _ReviewStat(
          icon: Icons.radio_button_unchecked,
          label: "Skipped",
          value: "${result.unansweredCount}",
          color: Colors.grey,
        ),
      ],
    );
  }
}

class _NegativeMarkingBanner extends StatelessWidget {
  const _NegativeMarkingBanner({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.remove_circle_outline, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  const TextSpan(text: "Negative marking: "),
                  TextSpan(
                    text: _formatMcqRuleNumber(value),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(text: " per wrong answer"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeResultBanner extends StatelessWidget {
  const _PracticeResultBanner({required this.result});

  final McqComputedResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_alt, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Practice score ${_formatMcqNumber(result.score)} • ${result.correctCount} correct • ${result.wrongCount} incorrect • ${result.unansweredCount} skipped",
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerReviewSheet extends StatelessWidget {
  const _AnswerReviewSheet({
    required this.result,
    required this.testData,
    required this.showTeacherOrder,
  });

  final Map<String, dynamic> result;
  final Map<String, dynamic> testData;
  final bool showTeacherOrder;

  @override
  Widget build(BuildContext context) {
    final computed = computeMcqResult(testData, result);
    final reviewQuestions = showTeacherOrder
        ? teacherOrderedReviewQuestions(testData, result)
        : _studentOrderedReviewQuestions(testData, result);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Answer Review",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: "Close",
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _ReviewStat(
                      icon: Icons.check_circle,
                      label: "Correct",
                      value: "${computed.correctCount}",
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _ReviewStat(
                      icon: Icons.cancel,
                      label: "Wrong",
                      value: "${computed.wrongCount}",
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    _ReviewStat(
                      icon: Icons.radio_button_unchecked,
                      label: "Blank",
                      value: "${computed.unansweredCount}",
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: reviewQuestions.isEmpty
                    ? const Center(child: Text("No questions found"))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        itemCount: reviewQuestions.length,
                        itemBuilder: (context, index) {
                          final reviewQuestion = reviewQuestions[index];
                          return _AnswerReviewCard(
                            questionNumber: index + 1,
                            question: reviewQuestion.question,
                            selectedIndex: reviewQuestion.selectedIndex,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<McqReviewQuestion> _studentOrderedReviewQuestions(
    Map<String, dynamic> testData,
    Map<String, dynamic> resultData,
  ) {
    final questions = mcqQuestionsFrom(testData);
    final questionOrder = mcqQuestionOrderFrom(
      resultData["questionOrder"],
      questions.length,
    );
    final answers = mcqAnswersFrom(resultData["answers"]);

    return questionOrder.asMap().entries.map((entry) {
      final displayIndex = entry.key;
      final originalIndex = entry.value;
      return McqReviewQuestion(
        question: questions[originalIndex],
        selectedIndex: answers[displayIndex],
      );
    }).toList();
  }
}

class _ReviewStat extends StatelessWidget {
  const _ReviewStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.shade100),
        ),
        child: Row(
          children: [
            Icon(icon, color: color.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color.shade900,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: color.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerReviewCard extends StatelessWidget {
  const _AnswerReviewCard({
    required this.questionNumber,
    required this.question,
    required this.selectedIndex,
  });

  final int questionNumber;
  final Map<String, dynamic> question;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final optionsRaw = question["options"];
    final options = optionsRaw is List
        ? optionsRaw.map((option) => option.toString()).toList()
        : <String>[];
    final correctIndex =
        int.tryParse(question["correctIndex"]?.toString() ?? "") ?? 0;
    final isCorrect = selectedIndex == correctIndex;
    final isUnanswered = selectedIndex == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isCorrect
                    ? Colors.green.shade100
                    : isUnanswered
                    ? Colors.grey.shade200
                    : Colors.red.shade100,
                child: Text(
                  "$questionNumber",
                  style: TextStyle(
                    color: isCorrect
                        ? Colors.green.shade800
                        : isUnanswered
                        ? Colors.grey.shade800
                        : Colors.red.shade800,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCorrect
                      ? "Correct"
                      : isUnanswered
                      ? "Not answered"
                      : "Incorrect",
                  style: TextStyle(
                    color: isCorrect
                        ? Colors.green.shade800
                        : isUnanswered
                        ? Colors.grey.shade700
                        : Colors.red.shade800,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question["question"]?.toString() ?? "",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ...options.asMap().entries.map((entry) {
            return _AnswerOptionTile(
              option: entry.value,
              isCorrectAnswer: entry.key == correctIndex,
              isSelectedWrong:
                  selectedIndex == entry.key && selectedIndex != correctIndex,
              isSelectedCorrect:
                  selectedIndex == entry.key && selectedIndex == correctIndex,
            );
          }),
        ],
      ),
    );
  }
}

class _AnswerOptionTile extends StatelessWidget {
  const _AnswerOptionTile({
    required this.option,
    required this.isCorrectAnswer,
    required this.isSelectedWrong,
    required this.isSelectedCorrect,
  });

  final String option;
  final bool isCorrectAnswer;
  final bool isSelectedWrong;
  final bool isSelectedCorrect;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color borderColor;
    final Color iconColor;
    final IconData? icon;

    if (isCorrectAnswer) {
      backgroundColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFF10B981);
      iconColor = const Color(0xFF059669);
      icon = Icons.check_circle;
    } else if (isSelectedWrong) {
      backgroundColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFEF4444);
      iconColor = const Color(0xFFDC2626);
      icon = Icons.cancel;
    } else {
      backgroundColor = const Color(0xFFF8FAFC);
      borderColor = Colors.black.withValues(alpha: 0.06);
      iconColor = Colors.grey;
      icon = null;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isCorrectAnswer || isSelectedWrong ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              option,
              style: TextStyle(
                color: isSelectedWrong
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF0F172A),
                fontWeight: isCorrectAnswer || isSelectedWrong
                    ? FontWeight.w900
                    : FontWeight.w600,
                decoration: isSelectedWrong
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: const Color(0xFFDC2626),
                decorationThickness: 2,
              ),
            ),
          ),
          if (isSelectedCorrect)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                "Your answer",
                style: TextStyle(
                  color: Color(0xFF047857),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (icon != null) Icon(icon, color: iconColor, size: 20),
        ],
      ),
    );
  }
}

class _MeritList extends StatelessWidget {
  const _MeritList({
    required this.testId,
    required this.testData,
    required this.currentMobile,
  });

  final String testId;
  final Map<String, dynamic> testData;
  final String currentMobile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("mcq_tests")
          .doc(testId)
          .collection("results")
          .orderBy("score", descending: true)
          .orderBy("timeTakenSeconds")
          .orderBy("submittedAt")
          .limit(QueryLimits.mcqMeritRealtime)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) return const LinearProgressIndicator();

        final results =
            snapshot.data!.docs
                .where((doc) => isMeritMcqResult(doc.data()))
                .map((doc) {
                  final resultData = doc.data();
                  return computeMcqResult(testData, resultData);
                })
                .toList()
              ..sort(compareMcqComputedResults);

        if (results.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Merit List",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            ...results
                .asMap()
                .entries
                .where((entry) {
                  return entry.key < 3 || entry.value.mobile == currentMobile;
                })
                .map((entry) {
                  final result = entry.value;
                  final isTopper = entry.key == 0;
                  final isCurrentStudent = result.mobile == currentMobile;
                  return Container(
                    margin: EdgeInsets.only(bottom: isTopper ? 10 : 6),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTopper ? 12 : 8,
                      vertical: isTopper ? 12 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: isTopper
                          ? const Color(0xFFFFFBEB)
                          : isCurrentStudent
                          ? const Color(0xFFEFF6FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(isTopper ? 16 : 12),
                      border: Border.all(
                        color: isTopper
                            ? const Color(0xFFF59E0B)
                            : isCurrentStudent
                            ? const Color(0xFF93C5FD)
                            : Colors.transparent,
                        width: isTopper ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: isTopper ? 18 : 15,
                          backgroundColor: isTopper
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFE2E8F0),
                          child: isTopper
                              ? const Icon(
                                  Icons.emoji_events,
                                  color: Colors.white,
                                  size: 19,
                                )
                              : Text("${entry.key + 1}"),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.studentName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isTopper
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF0F172A),
                                  fontSize: isTopper ? 16 : 14,
                                  fontWeight: isTopper || isCurrentStudent
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                ),
                              ),
                              Text(
                                "${isTopper ? (isCurrentStudent ? "You are the topper" : "Topper") : "Rank #${entry.key + 1}"} • ${result.correctCount} correct • ${result.wrongCount} incorrect • ${result.unansweredCount} skipped • ${_formatMcqDuration(result.timeTakenSeconds)}",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isTopper
                                      ? const Color(0xFFB45309)
                                      : Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          "${_formatMcqNumber(result.percentage)}%",
                          style: TextStyle(
                            color: isTopper
                                ? const Color(0xFF92400E)
                                : const Color(0xFF0F172A),
                            fontSize: isTopper ? 16 : 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
          ],
        );
      },
    );
  }
}
