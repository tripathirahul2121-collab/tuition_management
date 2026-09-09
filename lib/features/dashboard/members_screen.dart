import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/academic_catalog.dart';
import '../../core/constants/query_limits.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _usersStream() {
    return FirebaseFirestore.instance
        .collection("users")
        .orderBy("name")
        .limit(QueryLimits.members)
        .snapshots();
  }

  Stream<QuerySnapshot> _pendingStream() {
    return FirebaseFirestore.instance
        .collection("pending_users")
        .orderBy("name")
        .limit(QueryLimits.members)
        .snapshots();
  }

  Stream<QuerySnapshot> _junkStream() {
    return FirebaseFirestore.instance
        .collection("junk_users")
        .orderBy("name")
        .limit(QueryLimits.members)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Members",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Students"),
            Tab(text: "Teachers"),
            Tab(text: "Pending"),
            Tab(text: "Junk"),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          _MembersList(stream: _usersStream(), roleFilter: "student"),
          _MembersList(stream: _usersStream(), roleFilter: "teacher"),
          _MembersList(stream: _pendingStream(), isPending: true),
          _MembersList(stream: _junkStream(), isJunk: true),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// MEMBERS LIST (UPDATED UI)
////////////////////////////////////////////////////////////

class _MembersList extends StatefulWidget {
  final Stream<QuerySnapshot> stream;
  final String? roleFilter;
  final bool isPending;
  final bool isJunk;

  const _MembersList({
    required this.stream,
    this.roleFilter,
    this.isPending = false,
    this.isJunk = false,
  });

  @override
  State<_MembersList> createState() => _MembersListState();
}

class _MembersListState extends State<_MembersList> {
  final _searchController = TextEditingController();
  String _selectedClass = "all";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendMemberToJunk(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data["name"]?.toString() ?? "this member";
    final role = data["role"]?.toString() ?? "member";

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Move $role to junk?"),
        content: Text(
          "$name will be moved to Junk, their password will be changed, and they will no longer be able to login.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Move to Junk"),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;

    final blockedPassword =
        "JUNK_${DateTime.now().microsecondsSinceEpoch}_${doc.id}";
    final batch = FirebaseFirestore.instance.batch();
    final junkRef = FirebaseFirestore.instance
        .collection("junk_users")
        .doc(doc.id);

    batch.set(junkRef, {
      ...data,
      "mobile": data["mobile"] ?? doc.id,
      "previousRole": data["role"],
      "previousClass": data["class"],
      "removedAt": FieldValue.serverTimestamp(),
      "blockedReason": "Removed from active ME Classes members",
    }, SetOptions(merge: true));

    batch.update(doc.reference, {
      "active": false,
      "role": "junk",
      "class": "",
      "previousClass": data["class"] ?? "",
      "password": blockedPassword,
      "blockedAt": FieldValue.serverTimestamp(),
      "blockedMessage": "You are not authorized to access ME Classes.",
    });

    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      final message = error.message?.trim().isNotEmpty == true
          ? error.message!
          : "Firebase rejected the Junk update.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not move $name to Junk: $message")),
      );
      return;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not move $name to Junk. Try again.")),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$name moved to Junk")));
  }

  Future<void> _deletePermanently(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data["name"]?.toString() ?? "this member";
    final mobile = data["mobile"]?.toString() ?? doc.id;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete permanently?"),
        content: Text(
          "$name will be permanently deleted. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(doc.reference);

    if (widget.isJunk) {
      batch.delete(FirebaseFirestore.instance.collection("users").doc(mobile));
    }

    await batch.commit();

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$name deleted permanently")));
  }

  Future<void> _editMemberName(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final currentName = data["name"]?.toString() ?? "";
    final mobile = data["mobile"]?.toString() ?? doc.id;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _EditMemberNameDialog(currentName: currentName, mobile: mobile),
    );

    if (newName == null || newName == currentName.trim()) return;

    await doc.reference.update({
      "name": newName,
      "updatedAt": FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Name updated to $newName")));
  }

  String formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "";

    final date = timestamp.toDate();

    return "${date.day} ${_month(date.month)} • ${_formatTime(date)}";
  }

  String _month(int m) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return months[m - 1];
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final ampm = date.hour >= 12 ? "PM" : "AM";

    return "${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $ampm";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchEnabled =
        widget.roleFilter == "student" && !widget.isPending && !widget.isJunk;

    return StreamBuilder<QuerySnapshot>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data!.docs.where((doc) {
          if (widget.roleFilter == null) return true;
          final data = doc.data() as Map<String, dynamic>;
          return data["role"] == widget.roleFilter && data["active"] != false;
        }).toList();

        final query = _searchController.text.trim().toLowerCase();
        if (searchEnabled && query.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = data["name"]?.toString().toLowerCase() ?? "";
            final studentClass = data["class"]?.toString().toLowerCase() ?? "";
            return name.contains(query) || studentClass.contains(query);
          }).toList();
        }

        if (searchEnabled && _selectedClass != "all") {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data["class"]?.toString() == _selectedClass;
          }).toList();
        }

        ////////////////////////////////////////////////////////////
        /// SORT LATEST FIRST
        ////////////////////////////////////////////////////////////

        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTimestamp =
              (widget.isJunk ? aData["removedAt"] : aData["createdAt"])
                  as Timestamp?;
          final bTimestamp =
              (widget.isJunk ? bData["removedAt"] : bData["createdAt"])
                  as Timestamp?;
          final aTime = aTimestamp?.millisecondsSinceEpoch ?? 0;
          final bTime = bTimestamp?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });

        if (docs.isEmpty) {
          return Column(
            children: [
              if (searchEnabled) _studentFilters(),
              Expanded(
                child: _EmptyState(
                  message: query.isEmpty && _selectedClass == "all"
                      ? "No Members Found"
                      : "No student found for selected filter",
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            if (searchEnabled) _studentFilters(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;

                  final name = data["name"] ?? "Unnamed";
                  final mobile = data["mobile"] ?? docs[index].id;
                  final userClass = data["class"] ?? "";
                  final userBatch = AcademicCatalog.normalizeBatch(
                    data["batch"]?.toString(),
                  );
                  final password = data["password"] ?? "";
                  final createdAt = data["createdAt"] as Timestamp?;
                  final removedAt = data["removedAt"] as Timestamp?;

                  final avatarLetter = name.toString().isNotEmpty
                      ? name[0].toUpperCase()
                      : "?";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 12,
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ],
                    ),

                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ////////////////////////////////////////////////////////////
                        /// AVATAR
                        ////////////////////////////////////////////////////////////
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Text(
                            avatarLetter,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        ////////////////////////////////////////////////////////////
                        /// MAIN CONTENT
                        ////////////////////////////////////////////////////////////
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ////////////////////////////////////////////////////////
                              /// NAME + DATE
                              ////////////////////////////////////////////////////////
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),

                                  if (widget.roleFilter == "student" &&
                                      !widget.isPending &&
                                      !widget.isJunk)
                                    IconButton(
                                      tooltip: "Edit student name",
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minHeight: 30,
                                        minWidth: 30,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          _editMemberName(context, docs[index]),
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 18,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                ],
                              ),

                              Text(
                                formatDate(
                                  widget.isJunk ? removedAt : createdAt,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 5),

                              ////////////////////////////////////////////////////////
                              /// MOBILE
                              ////////////////////////////////////////////////////////
                              Text(
                                "📱 $mobile",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),

                              ////////////////////////////////////////////////////////
                              /// PASSWORD
                              ////////////////////////////////////////////////////////
                              if (password.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    "🔐 $password",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        ////////////////////////////////////////////////////////////
                        /// RIGHT SIDE (CLASS + PENDING)
                        ////////////////////////////////////////////////////////////
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (userClass.toString().isNotEmpty)
                              _Badge(
                                label: "Class $userClass",
                                color: Colors.orange,
                              ),

                            if (widget.roleFilter == "student" &&
                                userClass.toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: _Badge(
                                  label: AcademicCatalog.batchLabel(userBatch),
                                  color:
                                      userBatch ==
                                          AcademicCatalog.homeTuitionBatch
                                      ? Colors.deepPurple
                                      : Colors.blueGrey,
                                ),
                              ),

                            if (widget.isPending)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: _Badge(
                                  label: "Pending",
                                  color: Colors.red,
                                ),
                              ),

                            if ((widget.roleFilter == "student" ||
                                    widget.roleFilter == "teacher") &&
                                !widget.isPending &&
                                !widget.isJunk)
                              IconButton(
                                tooltip: "Move to Junk",
                                onPressed: () =>
                                    _sendMemberToJunk(context, docs[index]),
                                icon: const Icon(
                                  Icons.person_remove_alt_1,
                                  color: Colors.red,
                                ),
                              ),

                            if (widget.isPending || widget.isJunk)
                              IconButton(
                                tooltip: "Delete permanently",
                                onPressed: () =>
                                    _deletePermanently(context, docs[index]),
                                icon: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _studentFilters() {
    return Column(
      children: [
        _studentSearchField(),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            children: [
              _classFilterChip("all", "All"),
              ...AcademicCatalog.classValues
                  .where((className) => (int.tryParse(className) ?? 0) >= 5)
                  .map((className) {
                    return _classFilterChip(className, "Class $className");
                  }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classFilterChip(String value, String label) {
    final selected = _selectedClass == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _selectedClass = value),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF334155),
          fontWeight: FontWeight.w800,
        ),
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected
              ? const Color(0xFF2563EB)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _studentSearchField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: "Search student by name",
          border: InputBorder.none,
          icon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: "Clear search",
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }
}

class _EditMemberNameDialog extends StatefulWidget {
  const _EditMemberNameDialog({
    required this.currentName,
    required this.mobile,
  });

  final String currentName;
  final String mobile;

  @override
  State<_EditMemberNameDialog> createState() => _EditMemberNameDialogState();
}

class _EditMemberNameDialogState extends State<_EditMemberNameDialog> {
  late final TextEditingController _controller;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    _controller.addListener(_updateCanSave);
    _canSave =
        _controller.text.trim().isNotEmpty &&
        _controller.text.trim() != widget.currentName.trim();
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCanSave);
    _controller.dispose();
    super.dispose();
  }

  void _updateCanSave() {
    final value = _controller.text.trim();
    final canSave = value.isNotEmpty && value != widget.currentName.trim();
    if (canSave == _canSave) return;
    if (!mounted) return;
    setState(() => _canSave = canSave);
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit student name"),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: "Student name",
          helperText: "Login mobile stays unchanged: ${widget.mobile}",
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: const Icon(Icons.save),
          label: const Text("Save"),
        ),
      ],
    );
  }
}

////////////////////////////////////////////////////////////
/// BADGE
////////////////////////////////////////////////////////////

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// EMPTY STATE
////////////////////////////////////////////////////////////

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.message = "No Members Found"});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
