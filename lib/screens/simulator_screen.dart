import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/plating_models.dart';
import '../providers/plating_provider.dart';
import '../painters/scene_3d_painter.dart';
import '../widgets/settings_panels.dart';
import '../widgets/analysis_panel.dart';

class PlatingSimulatorScreen extends StatefulWidget {
  const PlatingSimulatorScreen({super.key});
  @override
  State<PlatingSimulatorScreen> createState() => _PlatingSimulatorScreenState();
}

class _PlatingSimulatorScreenState extends State<PlatingSimulatorScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  Offset? _lastDrag;
  // 마우스 휠 클릭(middle button) 팬 모드
  bool _isPanning = false;
  Offset? _lastPan;
  // 마스킹 오버레이 표시 여부
  bool _showMaskingOverlay = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlatingProvider>().runSimulation();
    });
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080E1C),
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(
            child: Consumer<PlatingProvider>(
              builder: (ctx, p, _) => Row(children: [
                // 3D 뷰
                Expanded(flex: 7, child: _build3DView(p)),
                // 우측 패널
                Container(
                  width: 310,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1120),
                    border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
                  ),
                  child: _buildRightPanel(p),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 상단 바 ──────────────────────────────────────────────
  Widget _buildTopBar() {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1120),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(children: [
            const Icon(Icons.science, color: Color(0xFF00E5FF), size: 20),
            const SizedBox(width: 7),
            const Text('전기도금 시뮬레이터', style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            _badge('3D'),
            const Spacer(),

            // 뷰 토글
            _toggleBtn('전기력선', Icons.timeline, p.showFieldLines,
                () => p.setShowFieldLines(!p.showFieldLines)),
            const SizedBox(width: 3),
            _toggleBtn('히트맵', Icons.gradient, p.showHeatmap,
                () => p.setShowHeatmap(!p.showHeatmap)),
            const SizedBox(width: 3),
            // 히트맵 모드 전환: 두께맵 ↔ 전기장맵
            if (p.showHeatmap) ...[
              _modeToggleBtn(
                p.heatmapMode == HeatmapMode.thickness ? '두께맵' : '전기장',
                p.heatmapMode == HeatmapMode.thickness ? Icons.layers : Icons.electric_bolt,
                p.heatmapMode,
                () => p.setHeatmapMode(
                  p.heatmapMode == HeatmapMode.thickness
                      ? HeatmapMode.fieldStrength
                      : HeatmapMode.thickness,
                ),
              ),
              const SizedBox(width: 3),
            ],
            _toggleBtn('탱크', Icons.view_in_ar, p.showTank,
                () => p.setShowTank(!p.showTank)),
            const SizedBox(width: 3),
            // 양극 숨김/표시
            _toggleBtn('양극', Icons.flash_on, p.showAnodes,
                () => p.setShowAnodes(!p.showAnodes)),
            const SizedBox(width: 3),
            _toggleBtn('마스킹', Icons.block, _showMaskingOverlay,
                () => setState(() => _showMaskingOverlay = !_showMaskingOverlay)),
            const SizedBox(width: 3),
            // 2D 전기력선 뷰 버튼
            _fieldLine2DBtn(p),
            const SizedBox(width: 8),

            // 줌 버튼
            _iconBtn(Icons.zoom_in, () => p.addZoom(1.0), '확대'),
            _iconBtn(Icons.zoom_out, () => p.addZoom(-0.5), '축소'),
            _iconBtn(Icons.center_focus_strong, p.resetView, '뷰 초기화'),
            const SizedBox(width: 6),

            // 시뮬레이션 실행
            AnimatedBuilder(
              animation: _pulse,
              builder: (ctx2, _) {
                final sc = p.isSimulating ? 0.96 + _pulse.value * 0.04 : 1.0;
                return Transform.scale(
                  scale: sc,
                  child: ElevatedButton.icon(
                    onPressed: p.isSimulating ? null : p.runSimulation,
                    icon: p.isSimulating
                        ? const SizedBox(width: 13, height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow, size: 16),
                    label: Text(p.isSimulating ? '계산중...' : '시뮬레이션',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.isSimulating
                          ? const Color(0xFF334455) : const Color(0xFF007A6E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );
              },
            ),
          ]),
        );
      },
    );
  }

  Widget _modeToggleBtn(String label, IconData icon, HeatmapMode mode, VoidCallback onTap) {
    final isThickness = mode == HeatmapMode.thickness;
    final activeColor = isThickness ? const Color(0xFFFF9800) : const Color(0xFFE040FB);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: activeColor.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: activeColor),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: activeColor)),
        ]),
      ),
    );
  }

  // 2D 전기력선 버튼 (위뷰 / 옆뷰 / 3D)
  Widget _fieldLine2DBtn(PlatingProvider p) {
    final mode = p.fieldLine2DMode;
    final isActive = mode != FieldLine2DMode.none;
    final label = mode == FieldLine2DMode.top
        ? '2D위뷰'
        : mode == FieldLine2DMode.side
            ? '2D옆뷰'
            : '2D';
    const activeColor = Color(0xFF00E5FF);

    return PopupMenuButton<FieldLine2DMode>(
      tooltip: '2D 전기력선 뷰',
      color: const Color(0xFF1A2035),
      onSelected: (m) => p.setFieldLine2DMode(m),
      itemBuilder: (_) => [
        const PopupMenuItem(value: FieldLine2DMode.none,
          child: Text('3D 뷰 (기본)', style: TextStyle(fontSize: 11, color: Colors.white70))),
        const PopupMenuItem(value: FieldLine2DMode.top,
          child: Text('위에서 내려본 2D', style: TextStyle(fontSize: 11, color: Colors.cyanAccent))),
        const PopupMenuItem(value: FieldLine2DMode.side,
          child: Text('옆에서 바라본 2D', style: TextStyle(fontSize: 11, color: Colors.cyanAccent))),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.6)
                : Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.view_in_ar_outlined, size: 12,
            color: isActive ? activeColor : Colors.white30),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(
            fontSize: 10, color: isActive ? activeColor : Colors.white30)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 12,
            color: isActive ? activeColor : Colors.white30),
        ]),
      ),
    );
  }

  Widget _badge(String t) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(t, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontWeight: FontWeight.bold)),
  );

  Widget _toggleBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active ? const Color(0xFF00E5FF).withValues(alpha: 0.4) : Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: active ? const Color(0xFF00E5FF) : Colors.white30),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(
            fontSize: 10, color: active ? const Color(0xFF00E5FF) : Colors.white30)),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.white54),
        ),
      ),
    );
  }

  // ── 3D 뷰 ────────────────────────────────────────────────
  Widget _build3DView(PlatingProvider p) {
    return Container(
      color: const Color(0xFF060C18),
      child: Stack(children: [
        // 배경 그리드
        CustomPaint(painter: GridBgPainter(), size: Size.infinite),

        // 2D 모드: 별도 전기력선 2D 뷰
        if (p.fieldLine2DMode != FieldLine2DMode.none)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (ctx, constraints) => CustomPaint(
                painter: FieldLine2DPainter(p: p, mode: p.fieldLine2DMode),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
          )
        else
          // 3D 씬 (마우스 이벤트)
          LayoutBuilder(builder: (ctx, constraints) {
            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  final delta = -event.scrollDelta.dy / 150.0;
                  p.addZoom(delta.clamp(-2.0, 2.0));
                }
              },
              onPointerDown: (event) {
                if (event.buttons == 4) {
                  setState(() {
                    _isPanning = true;
                    _lastPan = event.position;
                  });
                }
              },
              onPointerMove: (event) {
                if (_isPanning && _lastPan != null) {
                  final delta = event.position - _lastPan!;
                  p.pan(delta.dx, delta.dy);
                  setState(() => _lastPan = event.position);
                }
              },
              onPointerUp: (event) {
                if (event.buttons == 0 && _isPanning) {
                  setState(() {
                    _isPanning = false;
                    _lastPan = null;
                  });
                }
              },
              child: GestureDetector(
                onPanStart: (d) {
                  if (!_isPanning) _lastDrag = d.localPosition;
                },
                onPanUpdate: (d) {
                  if (!_isPanning && _lastDrag != null) {
                    final delta = d.localPosition - _lastDrag!;
                    p.rotate(delta.dx, delta.dy);
                    _lastDrag = d.localPosition;
                  }
                },
                onPanEnd: (_) => _lastDrag = null,
                child: CustomPaint(
                  painter: PlatingScene3DPainter(p: p),
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
            );
          }),

        // 마스킹 오버레이 패널 (3D 뷰 위에 오버레이)
        if (_showMaskingOverlay)
          Positioned(
            right: 10, top: 10,
            child: _buildMaskingOverlay(p),
          ),

        // 팬 모드 표시
        if (_isPanning)
          const Positioned(
            left: 0, right: 0, top: 0, bottom: 0,
            child: Center(
              child: Text('이동 중...',
                style: TextStyle(color: Colors.cyan, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),

        // 조작 안내 (3D 모드에서만)
        if (p.fieldLine2DMode == FieldLine2DMode.none)
          Positioned(
            left: 10, bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🖱 좌클릭 드래그: 회전', style: TextStyle(fontSize: 9, color: Colors.white54)),
                  Text('🖱 휠 클릭(중간버튼) 드래그: 이동', style: TextStyle(fontSize: 9, color: Colors.white54)),
                  Text('🔍 마우스 휠: 줌', style: TextStyle(fontSize: 9, color: Colors.white54)),
                  Text('± 버튼: 줌 조절', style: TextStyle(fontSize: 9, color: Colors.white54)),
                ],
              ),
            ),
          )
        else
          // 2D 모드 안내
          Positioned(
            left: 10, bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('⬆ 상단 [2D] 버튼으로 뷰 전환',
                style: TextStyle(fontSize: 9, color: Colors.cyanAccent)),
            ),
          ),

        // 정보 오버레이
        Positioned(left: 10, top: 10, child: _buildInfoOverlay(p)),
      ]),
    );
  }

  // ── 마스킹 3D 오버레이 패널 ─────────────────────────────
  Widget _buildMaskingOverlay(PlatingProvider p) {
    return Container(
      width: 240,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: const Color(0xEE0B1120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.purple.withValues(alpha: 0.2), blurRadius: 12,
        )],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10), topRight: Radius.circular(10)),
            ),
            child: Row(children: [
              const Icon(Icons.block, size: 13, color: Colors.purpleAccent),
              const SizedBox(width: 6),
              const Text('마스킹 편집 (3D 오버레이)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showMaskingOverlay = false),
                child: const Icon(Icons.close, size: 14, color: Colors.white38),
              ),
            ]),
          ),
          // 마스킹 목록 (스크롤 가능)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        '대상 제품: P${p.selectedProductIndex + 1}',
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ),
                    GestureDetector(
                      onTap: p.maskingZones.length < 8 ? p.addMaskingZone : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, size: 11, color: Colors.purpleAccent),
                          SizedBox(width: 3),
                          Text('추가', style: TextStyle(fontSize: 10, color: Colors.purpleAccent)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (p.maskingZones.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('마스킹 구역 없음\n위 추가 버튼으로 구역을 추가하세요',
                        style: TextStyle(fontSize: 10, color: Colors.white38)),
                    ),
                  ...p.maskingZones.map((zone) => _MaskingOverlayZone(
                    zone: zone,
                    provider: p,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoOverlay(PlatingProvider p) {
    final ar = p.analysisResult;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: p.elec.platingType.color, shape: BoxShape.circle)),
            Text(p.elec.platingType.label,
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 2),
          Text('탱크: ${p.tank.width.toStringAsFixed(0)}×${p.tank.depth.toStringAsFixed(0)}×${p.tank.length.toStringAsFixed(0)} cm',
            style: const TextStyle(fontSize: 9, color: Colors.white54)),
          Text('용액 수위: ${p.tank.solutionLevel.toStringAsFixed(0)} cm',
            style: const TextStyle(fontSize: 9, color: Colors.lightBlue)),
          Text('양극 수: ${p.anode.count}개 | 거리: ${p.anode.distFromProduct.toStringAsFixed(0)} cm',
            style: const TextStyle(fontSize: 9, color: Colors.orange)),
          Text('전류: ${p.elec.current.toStringAsFixed(1)} A | ${p.elec.platingTime.toStringAsFixed(0)} min',
            style: const TextStyle(fontSize: 9, color: Colors.white54)),
          // 표면적 및 이론 두께 표시
          Text('표면적: ${p.totalSurfaceAreaDm2.toStringAsFixed(3)} dm²',
            style: const TextStyle(fontSize: 9, color: Colors.tealAccent)),
          if (ar != null) ...[
            const SizedBox(height: 2),
            Text('평균 두께: ${ar.avgThickness.toStringAsFixed(2)} µm',
              style: const TextStyle(fontSize: 9, color: Color(0xFF00E5FF))),
            Text('균일도: ${(ar.uniformityIndex*100).toStringAsFixed(1)}% [${ar.overallGrade}]',
              style: TextStyle(fontSize: 9,
                color: ar.overallGrade == 'A' ? Colors.green
                     : ar.overallGrade == 'B' ? Colors.lightGreen
                     : ar.overallGrade == 'C' ? Colors.orange : Colors.red)),
          ],
        ],
      ),
    );
  }

  // ── 우측 패널 ────────────────────────────────────────────
  Widget _buildRightPanel(PlatingProvider p) {
    return Column(children: [
      // 탭
      Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Row(children: [
          _tabBtn('설정', 0, p),
          _tabBtn('분석', 1, p),
        ]),
      ),
      // 탭 내용
      Expanded(
        child: p.selectedTab == 0
            ? _buildSettings()
            : const AnalysisPanel(),
      ),
    ]);
  }

  Widget _tabBtn(String label, int idx, PlatingProvider p) {
    final active = p.selectedTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => p.setSelectedTab(idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: active ? const Color(0xFF00E5FF) : Colors.transparent,
              width: 2,
            )),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? const Color(0xFF00E5FF) : Colors.white38,
            )),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 전기/도금 설정 (최상단)
          ElectricalPanel(),
          // ② 탱크
          TankPanel(),
          // ③ 양극
          AnodePanel(),
          // ④ 제품
          ProductPanel(),
          // ⑤ 마스킹
          MaskingPanel(),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── 마스킹 오버레이 존 위젯 ───────────────────────────────
class _MaskingOverlayZone extends StatelessWidget {
  final MaskingZone zone;
  final PlatingProvider provider;

  const _MaskingOverlayZone({required this.zone, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.block, size: 11, color: Colors.purpleAccent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(zone.label,
                style: const TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
            ),
            GestureDetector(
              onTap: () => provider.removeMaskingZone(zone.id),
              child: const Icon(Icons.close, size: 13, color: Colors.red),
            ),
          ]),
          const SizedBox(height: 5),
          // X 범위
          _compactRangeRow('X', zone.xMin, zone.xMax,
            (s, e) => provider.updateMaskingZone(zone.id, zone.copyWith(xMin: s, xMax: e))),
          // Y 범위
          _compactRangeRow('Y', zone.yMin, zone.yMax,
            (s, e) => provider.updateMaskingZone(zone.id, zone.copyWith(yMin: s, yMax: e))),
          // Z 범위
          _compactRangeRow('Z', zone.zMin, zone.zMax,
            (s, e) => provider.updateMaskingZone(zone.id, zone.copyWith(zMin: s, zMax: e))),
          // 시각적 마스크 영역 표현
          const SizedBox(height: 4),
          _buildVisualMask(zone),
        ],
      ),
    );
  }

  Widget _compactRangeRow(String axis, double min, double max,
      void Function(double, double) onChanged) {
    return Row(children: [
      SizedBox(
        width: 18,
        child: Text(axis, style: const TextStyle(fontSize: 9, color: Colors.white54)),
      ),
      Expanded(
        child: RangeSlider(
          values: RangeValues(min, max),
          min: 0, max: 1,
          divisions: 20,
          activeColor: Colors.purple,
          inactiveColor: Colors.white12,
          onChanged: (v) => onChanged(v.start, v.end),
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '${(min*100).toStringAsFixed(0)}-${(max*100).toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 8, color: Colors.purple),
          textAlign: TextAlign.right,
        ),
      ),
    ]);
  }

  // 마스킹 영역 시각적 표현 (미니 3D 뷰)
  Widget _buildVisualMask(MaskingZone zone) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _axisMaskBar('X', zone.xMin, zone.xMax),
          Container(width: 0.5, height: 30, color: Colors.white12),
          _axisMaskBar('Y', zone.yMin, zone.yMax),
          Container(width: 0.5, height: 30, color: Colors.white12),
          _axisMaskBar('Z', zone.zMin, zone.zMax),
        ],
      ),
    );
  }

  Widget _axisMaskBar(String label, double min, double max) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38)),
        const SizedBox(height: 2),
        SizedBox(
          width: 50, height: 10,
          child: Stack(children: [
            Container(decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            Positioned(
              left: min * 50,
              width: (max - min) * 50,
              top: 0, bottom: 0,
              child: Container(decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              )),
            ),
          ]),
        ),
      ],
    );
  }
}
