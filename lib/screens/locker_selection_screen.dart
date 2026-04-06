import 'package:flutter/material.dart';
import 'dart:async';

import '../core/auth_controller.dart';
import '../core/design_tokens.dart';

class LockerSelectionScreen extends StatefulWidget {
  const LockerSelectionScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<LockerSelectionScreen> createState() => _LockerSelectionScreenState();
}

class _LockerSelectionScreenState extends State<LockerSelectionScreen> {
  static const _floors = ['Ground Floor', '2nd Floor'];

  int? _selectedBuilding;
  String? _selectedFloor;
  bool _isAssigning = false;
  bool _isLoadingBuildings = true;
  bool _isLoadingFloors = false;
  bool _isLoadingLockers = false;

  List<LockerBuildingAvailability> _buildings = const [];
  Map<String, int> _floorCounts = const {'Ground Floor': 0, '2nd Floor': 0};
  List<LockerSlot> _lockers = const [];

  StreamSubscription<List<LockerBuildingAvailability>>? _buildingsSub;
  StreamSubscription<Map<String, int>>? _floorsSub;
  StreamSubscription<List<LockerSlot>>? _lockersSub;

  @override
  void initState() {
    super.initState();
    _subscribeBuildings();
  }

  @override
  void dispose() {
    _buildingsSub?.cancel();
    _floorsSub?.cancel();
    _lockersSub?.cancel();
    super.dispose();
  }

  void _subscribeBuildings() {
    _buildingsSub?.cancel();
    _buildingsSub = widget.controller.watchBuildingAvailability().listen((
      items,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {
        _buildings = items;
        _isLoadingBuildings = false;

        if (_selectedBuilding != null &&
            !_buildings.any((b) => b.buildingNumber == _selectedBuilding)) {
          _selectedBuilding = null;
          _selectedFloor = null;
          _floorCounts = const {'Ground Floor': 0, '2nd Floor': 0};
          _lockers = const [];
        }
      });
    });
  }

  Future<void> _goBack() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    await widget.controller.logout();
  }

  void _refreshAvailability() {
    setState(() {
      _isLoadingBuildings = true;
      _isLoadingFloors = _selectedBuilding != null;
      _isLoadingLockers = _selectedBuilding != null && _selectedFloor != null;
    });

    _subscribeBuildings();
    final building = _selectedBuilding;
    final floor = _selectedFloor;
    if (building != null) {
      _subscribeFloors(building);
      if (floor != null) {
        _subscribeLockers(building, floor);
      }
    }
  }

  void _onSelectBuilding(int buildingNumber) {
    if (_selectedBuilding == buildingNumber) {
      return;
    }

    setState(() {
      _selectedBuilding = buildingNumber;
      _selectedFloor = null;
      _floorCounts = const {'Ground Floor': 0, '2nd Floor': 0};
      _lockers = const [];
      _isLoadingFloors = true;
      _isLoadingLockers = false;
    });

    _subscribeFloors(buildingNumber);
  }

  void _subscribeFloors(int buildingNumber) {
    _floorsSub?.cancel();
    _floorsSub = widget.controller
        .watchFloorAvailability(buildingNumber: buildingNumber)
        .listen((counts) {
          if (!mounted || _selectedBuilding != buildingNumber) {
            return;
          }

          setState(() {
            _floorCounts = counts;
            _isLoadingFloors = false;

            if (_selectedFloor != null &&
                (_floorCounts[_selectedFloor] ?? 0) <= 0) {
              _selectedFloor = null;
              _lockers = const [];
              _isLoadingLockers = false;
            }
          });
        });
  }

  void _onSelectFloor(String floor) {
    if (_selectedBuilding == null || _selectedFloor == floor) {
      return;
    }

    setState(() {
      _selectedFloor = floor;
      _lockers = const [];
      _isLoadingLockers = true;
    });

    _subscribeLockers(_selectedBuilding!, floor);
  }

  void _subscribeLockers(int buildingNumber, String floor) {
    _lockersSub?.cancel();
    _lockersSub = widget.controller
        .watchAvailableLockers(buildingNumber: buildingNumber, floor: floor)
        .listen((items) {
          if (!mounted ||
              _selectedBuilding != buildingNumber ||
              _selectedFloor != floor) {
            return;
          }

          setState(() {
            _lockers = items;
            _isLoadingLockers = false;
          });
        });
  }

  Future<void> _assignLocker(LockerSlot slot) async {
    if (_isAssigning) {
      return;
    }

    setState(() => _isAssigning = true);
    final result = await widget.controller.assignLockerById(slot.lockerId);
    if (!mounted) {
      return;
    }

    setState(() => _isAssigning = false);
    if (result != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Locker ${slot.lockerId} assigned successfully.')),
    );
  }

  Future<void> _confirmAndAssignLocker(LockerSlot slot) async {
    if (_isAssigning) {
      return;
    }

    final shouldAssign = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: T.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(T.r12),
            side: const BorderSide(color: T.border, width: T.strokeSm),
          ),
          title: const Text(
            'Confirm Locker Assignment',
            style: TextStyle(
              color: T.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          content: Text(
            'Assign locker ${slot.lockerId} in Building ${slot.buildingNumber}, ${slot.floor}?\n\nThis action will reserve the locker for your account.',
            style: const TextStyle(
              color: T.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel', style: TextStyle(color: T.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: T.accent,
                foregroundColor: T.bg,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (shouldAssign == true) {
      await _assignLocker(slot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.currentUser;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_isLoadingBuildings && _buildings.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: T.accent),
              );
            }

            if (_buildings.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(T.r16),
                      border: Border.all(color: T.border, width: T.strokeSm),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: T.accentDim,
                            borderRadius: BorderRadius.circular(T.r16),
                            border: Border.all(
                              color: T.accent.withValues(alpha: 0.3),
                              width: T.strokeSm,
                            ),
                          ),
                          child: const Icon(
                            Icons.meeting_room_outlined,
                            color: T.accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No available lockers right now',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: T.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'All lockers are currently occupied. You can refresh to check again or go back.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: T.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _goBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _refreshAvailability,
                                style: FilledButton.styleFrom(
                                  backgroundColor: T.accent,
                                  foregroundColor: T.bg,
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Refresh'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final selectedBuilding = _selectedBuilding;
            final selectedFloor = _selectedFloor;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose Your Locker',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: T.textPrimary,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user == null
                        ? 'Select a building, floor, and locker to continue.'
                        : 'Hi ${user.firstName}, pick an available locker to finish setup.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: T.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('1. Select Building'),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _buildings.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.6,
                        ),
                    itemBuilder: (context, index) {
                      final item = _buildings[index];
                      final selected = selectedBuilding == item.buildingNumber;
                      return _SelectableCard(
                        title: 'Building ${item.buildingNumber}',
                        subtitle: '${item.availableCount} lockers available',
                        selected: selected,
                        onTap: () => _onSelectBuilding(item.buildingNumber),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  if (selectedBuilding != null) ...[
                    const _SectionTitle('2. Select Floor'),
                    const SizedBox(height: 10),
                    if (_isLoadingFloors)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: CircularProgressIndicator(color: T.accent),
                        ),
                      )
                    else
                      Row(
                        children: _floors
                            .map((floor) {
                              final available = _floorCounts[floor] ?? 0;
                              final disabled = available <= 0;
                              final selected = selectedFloor == floor;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: floor == _floors.first ? 8 : 0,
                                    left: floor == _floors.last ? 8 : 0,
                                  ),
                                  child: _SelectableCard(
                                    title: floor,
                                    subtitle: disabled
                                        ? 'Full'
                                        : '$available available',
                                    selected: selected,
                                    disabled: disabled,
                                    onTap: disabled
                                        ? null
                                        : () => _onSelectFloor(floor),
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (selectedBuilding != null && selectedFloor != null) ...[
                    const _SectionTitle('3. Select Locker'),
                    const SizedBox(height: 10),
                    if (_isLoadingLockers)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(color: T.accent),
                        ),
                      )
                    else if (_lockers.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: T.surface,
                          borderRadius: BorderRadius.circular(T.r12),
                          border: Border.all(
                            color: T.border,
                            width: T.strokeSm,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: T.textSecondary,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No available lockers on this floor.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: T.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try another floor or refresh availability.',
                              style: TextStyle(
                                fontSize: 12,
                                color: T.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedFloor = null;
                                      _lockers = const [];
                                    });
                                  },
                                  icon: const Icon(Icons.layers_outlined),
                                  label: const Text('Choose Floor'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _refreshAvailability,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _lockers.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.35,
                            ),
                        itemBuilder: (context, index) {
                          final locker = _lockers[index];
                          return _LockerButton(
                            lockerId: locker.lockerId,
                            isAssigning: _isAssigning,
                            onTap: () => _confirmAndAssignLocker(locker),
                          );
                        },
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: T.textMuted,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.disabled = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = disabled
        ? T.border
        : selected
        ? T.accent
        : T.border;

    return InkWell(
      borderRadius: BorderRadius.circular(T.r12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: disabled
              ? T.surfaceAlt.withValues(alpha: 0.4)
              : selected
              ? T.accentDim
              : T.surface,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: borderColor, width: T.strokeSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: disabled ? T.textMuted : T.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: disabled ? T.textMuted : T.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockerButton extends StatelessWidget {
  const _LockerButton({
    required this.lockerId,
    required this.isAssigning,
    required this.onTap,
  });

  final String lockerId;
  final bool isAssigning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(T.r12),
      onTap: isAssigning ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.r12),
          border: Border.all(color: T.border, width: T.strokeSm),
        ),
        child: Center(
          child: Text(
            lockerId,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: T.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
