import 'package:flutter/material.dart';

enum QueueWidgetMode { preArrival, postArrival }

class QueueStatusWidget extends StatefulWidget {
  // ── Pre-arrival props ─────────────────────────────────────────────────────
  final String roomNumber;

  // ── Post-arrival props (all required when mode=postArrival) ───────────────
  // These are passed in from the parent's realtime-computed values.
  final QueueWidgetMode mode;
  final int? myPosition; // 1-indexed arrival-order rank
  final int? totalInRoom; // total patients currently with status='reached'
  final int? estimatedWaitMinutes;

  // ── Pre-arrival props ─────────────────────────────────────────────────────
  // Passed in from parent's realtime count — no separate fetch needed.
  final int? preArrivalCount;

  const QueueStatusWidget({
    Key? key,
    required this.roomNumber,
    this.mode = QueueWidgetMode.preArrival,
    // post-arrival
    this.myPosition,
    this.totalInRoom,
    this.estimatedWaitMinutes,
    // pre-arrival
    this.preArrivalCount,
  }) : super(key: key);

  @override
  State<QueueStatusWidget> createState() => _QueueStatusWidgetState();
}

class _QueueStatusWidgetState extends State<QueueStatusWidget>
    with SingleTickerProviderStateMixin {
  // Pulse animation fires when position improves (number drops)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  int? _prevPosition;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.elasticOut));
    _prevPosition = widget.myPosition;
  }

  @override
  void didUpdateWidget(QueueStatusWidget old) {
    super.didUpdateWidget(old);
    // Trigger scale-bounce when position improves
    final newPos = widget.myPosition;
    if (_prevPosition != null && newPos != null && newPos < _prevPosition!) {
      _pulseCtrl.forward(from: 0);
    }
    _prevPosition = newPos;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Color helpers ─────────────────────────────────────────────────────────
  Color _positionColor(int position) {
    if (position == 1) return const Color(0xFF16A34A); // green  — you're next
    if (position <= 3) return const Color(0xFF2563EB); // blue   — short wait
    if (position <= 5) return const Color(0xFFF97316); // orange — medium wait
    return const Color(0xFFDC2626); // red    — long wait
  }

  Color _preArrivalColor(int count) {
    if (count == 0) return const Color(0xFF16A34A);
    if (count <= 2) return const Color(0xFF2563EB);
    if (count <= 4) return const Color(0xFFF97316);
    return const Color(0xFFDC2626);
  }

  @override
  Widget build(BuildContext context) {
    return widget.mode == QueueWidgetMode.preArrival
        ? _buildPreArrival()
        : _buildPostArrival();
  }

  // ── PRE-ARRIVAL ───────────────────────────────────────────────────────────
  Widget _buildPreArrival() {
    final count = widget.preArrivalCount ?? 0;
    final c = _preArrivalColor(count);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.09), c.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.28), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, color: c, size: 18),
              const SizedBox(width: 8),
              Text(
                'Room Status',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              _LiveDot(color: c),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  'Waiting now',
                  '$count',
                  count == 1 ? 'person' : 'people',
                  c,
                  Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Est. wait',
                  '~${count * 8}',
                  'min',
                  const Color(0xFF2563EB),
                  Icons.schedule_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  count == 0
                      ? 'Room is free — great time to head over'
                      : count <= 2
                      ? 'Short queue — head over soon'
                      : count <= 4
                      ? 'Moderate wait — expect some delay'
                      : 'Busy — longer wait expected',
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── POST-ARRIVAL ──────────────────────────────────────────────────────────
  Widget _buildPostArrival() {
    final position = widget.myPosition ?? 1;
    final total = widget.totalInRoom ?? 1;
    final mins = widget.estimatedWaitMinutes ?? 0;
    final isNext = position == 1;
    final c = _positionColor(position);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.10), c.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: c.withValues(alpha: 0.30), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header bar ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                _LiveDot(color: c),
                const SizedBox(width: 8),
                Text(
                  'Live Queue',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c,
                  ),
                ),
                const Spacer(),
                Text(
                  'updates in real-time',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Position circle — bounces when your number improves
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.withValues(alpha: 0.13),
                      border: Border.all(
                        color: c.withValues(alpha: 0.45),
                        width: 2.5,
                      ),
                    ),
                    child: isNext
                        ? Icon(
                            Icons.notifications_active_rounded,
                            color: c,
                            size: 34,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Text(
                                  '$position',
                                  key: ValueKey(position),
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: c,
                                    height: 1,
                                  ),
                                ),
                              ),
                              Text(
                                'of $total',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: c.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 16),

                // Text block
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: Text(
                          isNext ? 'You are next!' : 'In queue',
                          key: ValueKey(isNext),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // The key line — different for every patient
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: Text(
                          _waitingText(position - 1),
                          key: ValueKey(position),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Est. wait
                      if (!isNext)
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              mins == 0 ? 'Very soon' : 'Est. ~$mins min',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 13,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$total ${total == 1 ? 'patient' : 'patients'} in room',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Progress bar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your position',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        '$position / $total',
                        key: ValueKey('$position/$total'),
                        style: TextStyle(
                          fontSize: 12,
                          color: c,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: total > 0 ? position / total : 1.0,
                    ),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(c),
                      minHeight: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _waitingText(int ahead) {
    if (ahead == 0) return '0 patients waiting before you';
    if (ahead == 1) return '1 patient waiting before you';
    return '$ahead patients waiting before you';
  }

  Widget _statTile(
    String label,
    String value,
    String unit,
    Color c,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 16),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
                TextSpan(
                  text: '  $unit',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing live dot ──────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.3, end: 1.0).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
