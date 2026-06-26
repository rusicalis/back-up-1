import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/plating_models.dart';
import '../providers/plating_provider.dart';
import 'cad_file_picker.dart';

// ============================================================
// 직접 입력 + 슬라이더 복합 위젯
// ============================================================
class NumericField extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final int decimals;
  final Color color;
  final ValueChanged<double> onChanged;

  const NumericField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.decimals = 0,
    this.color = Colors.cyan,
  });

  @override
  State<NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<NumericField> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(NumericField old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  String _fmt(double v) =>
    widget.decimals > 0 ? v.toStringAsFixed(widget.decimals) : v.toStringAsFixed(0);

  void _submit(String raw) {
    final v = double.tryParse(raw);
    if (v != null) {
      final clamped = v.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _ctrl.text = _fmt(clamped);
    } else {
      _ctrl.text = _fmt(widget.value);
    }
    setState(() => _editing = false);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 85,
            child: Text(widget.label,
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ),
          SizedBox(
            width: 66,
            height: 28,
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
              style: TextStyle(fontSize: 11, color: widget.color, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: widget.color.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: widget.color.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: widget.color),
                ),
                filled: true,
                fillColor: widget.color.withValues(alpha: 0.05),
                suffixText: widget.unit,
                suffixStyle: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
              onTap: () => setState(() => _editing = true),
              onSubmitted: _submit,
              onEditingComplete: () => _submit(_ctrl.text),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: widget.color,
                thumbColor: widget.color,
                inactiveTrackColor: Colors.white10,
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: widget.value.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                onChanged: (v) {
                  widget.onChanged(v);
                  _ctrl.text = _fmt(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 섹션 헤더
// ============================================================
class SectionHdr extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const SectionHdr({super.key, required this.title, required this.icon, this.color = Colors.cyan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 3),
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 6),
        Expanded(child: Divider(color: color.withValues(alpha: 0.25), height: 1)),
      ]),
    );
  }
}

// ============================================================
// ① 전기/도금 설정 패널 (최상단)
// ============================================================
class ElectricalPanel extends StatelessWidget {
  const ElectricalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        final e = p.elec;
        final cdRange = e.platingType.currentDensityRange;
        final areaDm2 = p.totalSurfaceAreaDm2;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHdr(title: '전기 / 도금 설정', icon: Icons.power, color: Color(0xFF00E5FF)),

          // 도금 종류
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('도금 종류', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 3),
              DropdownButtonFormField<PlatingType>(
                initialValue: e.platingType,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: Colors.white24)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: Colors.white24)),
                  filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
                ),
                dropdownColor: const Color(0xFF1A2035),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                items: PlatingType.values.map((t) => DropdownMenuItem(
                  value: t,
                  child: Row(children: [
                    Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Text(t.label, style: const TextStyle(fontSize: 11)),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) p.updateElec(e.copyWith(platingType: v)); },
              ),
            ]),
          ),

          // 표면적 표시 + 적정 전류 자동 산출 버튼
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.area_chart, size: 11, color: Colors.tealAccent),
                const SizedBox(width: 4),
                const Text('제품 총 표면적',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                const Spacer(),
                Text('${areaDm2.toStringAsFixed(3)} dm²',
                    style: const TextStyle(fontSize: 12, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 2),
              Text(
                '권장 전류: ${(cdRange.$1 * areaDm2).toStringAsFixed(1)}~${(cdRange.$2 * areaDm2).toStringAsFixed(1)} A',
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 28,
                child: ElevatedButton.icon(
                  onPressed: () => p.applyRecommendedElecFromArea(),
                  icon: const Icon(Icons.auto_fix_high, size: 13),
                  label: const Text('표면적 기준 적정 전류/전압 자동 산출',
                      style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
            ]),
          ),

          // 자동 전압 토글
          Row(children: [
            const Text('전압 자동계산', style: TextStyle(fontSize: 11, color: Colors.white60)),
            const Spacer(),
            Switch(
              value: e.autoVoltage,
              onChanged: (v) => p.updateElec(e.copyWith(autoVoltage: v)),
              activeThumbColor: const Color(0xFF00E5FF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),

          _CurrentField(
            value: e.current,
            onChanged: (v) {
              final rounded = v.roundToDouble().clamp(0.0, 2000.0);
              final newE = e.copyWith(current: rounded);
              if (newE.autoVoltage) {
                p.updateElec(newE.copyWith(
                  voltage: newE.computeVoltage(
                    p.anode.distFromProduct,
                    p.totalSurfaceAreaDm2 * 100.0,
                  ),
                ));
              } else {
                p.updateElec(newE);
              }
            },
          ),

          NumericField(
            label: '전압 (V)', value: e.voltage, min: 0.0, max: 20.0, unit: 'V',
            decimals: 1, color: Colors.lime,
            onChanged: e.autoVoltage
                ? (_) {}
                : (v) => p.updateElec(e.copyWith(voltage: (v * 10).round() / 10.0)),
          ),
          _PlatingTimeField(
            totalMinutes: e.platingTime,
            onChanged: (minutes) => p.updateElec(e.copyWith(platingTime: minutes)),
          ),

          // 도금 특성 카드
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: e.platingType.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: e.platingType.color.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.platingType.label, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: e.platingType.color)),
              const SizedBox(height: 4),
              _kv('전류효율', '${e.platingType.currentEfficiency}%'),
              _kv('밀도', '${e.platingType.density} g/cm³'),
              _kv('권장 전류밀도', '${cdRange.$1}~${cdRange.$2} A/dm²'),
              _kv('원자가', '${e.platingType.valence}'),
              const Divider(color: Colors.white12, height: 8),
              _kv('전압(계산값)', '${e.voltage.toStringAsFixed(2)} V', valColor: Colors.lime),
              _kv('실효 전류밀도', '${(areaDm2 > 0 ? e.current / areaDm2 : 0).toStringAsFixed(2)} A/dm²',
                  valColor: Colors.greenAccent),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _kv(String k, String v, {Color valColor = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        Text(v, style: TextStyle(fontSize: 10, color: valColor, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// 전류 입력 위젯 (1A 단위)
class _CurrentField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _CurrentField({required this.value, required this.onChanged});

  @override
  State<_CurrentField> createState() => _CurrentFieldState();
}

class _CurrentFieldState extends State<_CurrentField> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(_CurrentField old) {
    super.didUpdateWidget(old);
    if (!_editing && (old.value - widget.value).abs() > 0.001) {
      _ctrl.text = widget.value.toStringAsFixed(0);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit(String raw) {
    final v = double.tryParse(raw);
    if (v != null) {
      final clamped = v.clamp(0.0, 2000.0).roundToDouble();
      widget.onChanged(clamped);
      _ctrl.text = clamped.toStringAsFixed(0);
    } else {
      _ctrl.text = widget.value.toStringAsFixed(0);
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    // 슬라이더 범위: 0~2000A, 1A 단위 조절 + 텍스트 직접 입력
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(
            width: 85,
            child: Text('전류 (A)', style: TextStyle(fontSize: 11, color: Colors.white60)),
          ),
          SizedBox(
            width: 66, height: 28,
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.5))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.greenAccent)),
                filled: true,
                fillColor: Colors.greenAccent.withValues(alpha: 0.05),
                suffixText: 'A',
                suffixStyle: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
              onTap: () => setState(() => _editing = true),
              onSubmitted: _submit,
              onEditingComplete: () => _submit(_ctrl.text),
            ),
          ),
          // +/- 버튼 (1A 단위)
          const SizedBox(width: 4),
          _stepBtn(Icons.remove, () {
            final newVal = (widget.value - 1).clamp(0.0, 2000.0);
            widget.onChanged(newVal.roundToDouble());
          }),
          const SizedBox(width: 2),
          _stepBtn(Icons.add, () {
            final newVal = (widget.value + 1).clamp(0.0, 2000.0);
            widget.onChanged(newVal.roundToDouble());
          }),
        ]),
        // 슬라이더 (0~2000A, 1A step)
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.greenAccent,
            thumbColor: Colors.greenAccent,
            inactiveTrackColor: Colors.white10,
            trackHeight: 2.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            value: widget.value.clamp(0.0, 2000.0),
            min: 0.0, max: 2000.0, divisions: 2000,
            onChanged: (v) {
              final rounded = v.roundToDouble();
              widget.onChanged(rounded);
              if (!_editing) _ctrl.text = rounded.toStringAsFixed(0);
            },
          ),
        ),
        Text('1A 단위 조절 | 현재: ${widget.value.toStringAsFixed(0)} A',
          style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 13, color: Colors.greenAccent),
      ),
    );
  }
}

class _PlatingTimeField extends StatelessWidget {
  final double totalMinutes;
  final ValueChanged<double> onChanged;

  const _PlatingTimeField({required this.totalMinutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final clampedMinutes = totalMinutes.clamp(1.0, 600.0);
    final hours = (clampedMinutes ~/ 60).clamp(0, 10);
    final minutes = (clampedMinutes.round() % 60).clamp(0, 59);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumericField(
          label: '도금 시간(시)',
          value: hours.toDouble(),
          min: 0,
          max: 10,
          unit: 'h',
          color: Colors.tealAccent,
          onChanged: (v) {
            final next = ((v.round().clamp(0, 10)) * 60 + minutes).clamp(1, 600);
            onChanged(next.toDouble());
          },
        ),
        NumericField(
          label: '도금 시간(분)',
          value: minutes.toDouble(),
          min: 0,
          max: 59,
          unit: 'min',
          color: Colors.tealAccent,
          onChanged: (v) {
            final next = (hours * 60 + v.round().clamp(0, 59)).clamp(1, 600);
            onChanged(next.toDouble());
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            '총 도금 시간: $hours시간 $minutes분 (1분 단위, 최대 10시간)',
            style: const TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ② 탱크 설정 패널
// ============================================================
class TankPanel extends StatelessWidget {
  const TankPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        final t = p.tank;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHdr(title: '도금 탱크 (X=폭, Y=깊이, Z=길이)',
            icon: Icons.view_in_ar, color: Colors.blueAccent),
          NumericField(label: 'X 폭', value: t.width, min: 10, max: 7000, unit: 'cm',
            color: Colors.blue,
            onChanged: (v) => p.updateTank(t.copyWith(width: v))),
          NumericField(label: 'Y 깊이', value: t.depth, min: 10, max: 7000, unit: 'cm',
            color: Colors.blue,
            onChanged: (v) => p.updateTank(t.copyWith(depth: v))),
          NumericField(label: 'Z 길이', value: t.length, min: 10, max: 7000, unit: 'cm',
            color: Colors.blue,
            onChanged: (v) => p.updateTank(t.copyWith(length: v))),
          NumericField(label: '용액 수위', value: t.solutionLevel, min: 0, max: t.depth,
            unit: 'cm', color: Colors.lightBlue,
            onChanged: (v) => p.updateTank(t.copyWith(solutionLevel: v))),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '탱크 부피: ${(t.width*t.depth*t.length/1000000).toStringAsFixed(2)} m³  '
              '용액 부피: ${(t.width*t.solutionLevel*t.length/1000000).toStringAsFixed(2)} m³',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ),
        ]);
      },
    );
  }
}

// ============================================================
// ③ 양극 설정 패널
// ============================================================
class AnodePanel extends StatelessWidget {
  const AnodePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        final a = p.anode;
        final t = p.tank;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHdr(title: '양극 Anode (+)', icon: Icons.electric_bolt, color: Colors.orange),
          NumericField(label: 'X 두께', value: a.width, min: 1, max: t.width, unit: 'cm',
            color: Colors.orange,
            onChanged: (v) => p.updateAnode(a.copyWith(width: v))),
          NumericField(label: 'Y 높이', value: a.depth, min: 5, max: t.depth, unit: 'cm',
            color: Colors.orange,
            onChanged: (v) => p.updateAnode(a.copyWith(depth: v))),
          NumericField(label: 'Z 폭', value: a.length, min: 5, max: t.length, unit: 'cm',
            color: Colors.orange,
            onChanged: (v) => p.updateAnode(a.copyWith(length: v))),

          // 양극 수 (정수)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              const SizedBox(width: 85,
                child: Text('양극 수 (≤20)', style: TextStyle(fontSize: 11, color: Colors.white60))),
              SizedBox(
                width: 66, height: 28,
                child: _IntField(
                  value: a.count, min: 2, max: 20,
                  color: Colors.deepOrange,
                  onChanged: (v) => p.updateAnode(a.copyWith(count: v)),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.deepOrange,
                    thumbColor: Colors.deepOrange,
                    inactiveTrackColor: Colors.white10,
                    trackHeight: 2.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: a.count.toDouble().clamp(2, 20),
                    min: 2, max: 20, divisions: 18,
                    onChanged: (v) => p.updateAnode(a.copyWith(count: v.round())),
                  ),
                ),
              ),
            ]),
          ),

          NumericField(label: '제품과 거리', value: a.distFromProduct,
            min: 5, max: t.width/2,
            unit: 'cm', color: Colors.deepOrange,
            onChanged: (v) => p.updateAnode(a.copyWith(distFromProduct: v))),
          NumericField(label: 'Y 시작위치', value: a.yOffset,
            min: 0, max: t.solutionLevel,
            unit: 'cm', color: Colors.amber,
            onChanged: (v) => p.updateAnode(a.copyWith(yOffset: v))),

          // ── 양극 쌍 간 간격 (다수 양극 쌍) ─────────────────
          if (a.count > 2)
            NumericField(
              label: '양극쌍 간격(Z)',
              value: a.anodeSpacing > 0 ? a.anodeSpacing : a.length * 1.5,
              min: a.length * 0.5,
              max: t.length,
              unit: 'cm', color: Colors.orangeAccent, decimals: 1,
              onChanged: (v) => p.updateAnode(a.copyWith(anodeSpacing: v)),
            ),

          // ── 양극 독립 위치 조정 ──────────────────────────────
          const SectionHdr(title: '양극 위치 조정 (제품과 독립)', icon: Icons.open_with, color: Colors.deepOrange),

          // 양극 위치 고정 토글 (제품이 움직여도 양극은 제자리)
          Row(children: [
            const Icon(Icons.lock, size: 11, color: Colors.orangeAccent),
            const SizedBox(width: 5),
            const Expanded(child: Text('양극 위치 독립 고정\n(제품 이동 시 양극 유지)',
              style: TextStyle(fontSize: 10, color: Colors.white60))),
            Switch(
              value: a.absolutePosition,
              onChanged: (v) => p.updateAnode(a.copyWith(absolutePosition: v)),
              activeThumbColor: Colors.orangeAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            ),
            child: Text(
              a.absolutePosition
                ? '🔒 양극 고정됨 — 탱크 중심 기준 위치'
                : '🔗 양극 연동됨 — 제품 중심 기준 위치',
              style: TextStyle(fontSize: 9,
                color: a.absolutePosition ? Colors.orangeAccent : Colors.white38),
            ),
          ),
          const SizedBox(height: 4),

          NumericField(label: 'X 이동 (오프셋)', value: a.posXOffset,
            min: -(t.width/2 - a.distFromProduct - a.width).clamp(0.1, t.width),
            max: (t.width/2 - a.distFromProduct - a.width).clamp(0.1, t.width),
            unit: 'cm', color: Colors.deepOrange, decimals: 1,
            onChanged: (v) => p.updateAnode(a.copyWith(posXOffset: v))),
          NumericField(label: 'Z 이동 (오프셋)', value: a.posZOffset,
            min: -t.length/2,
            max: t.length/2,
            unit: 'cm', color: Colors.deepOrange, decimals: 1,
            onChanged: (v) => p.updateAnode(a.copyWith(posZOffset: v))),

          Text(
            '양극-제품-양극: ${a.distFromProduct.toStringAsFixed(0)}cm — 제품 — ${a.distFromProduct.toStringAsFixed(0)}cm',
            style: const TextStyle(fontSize: 10, color: Colors.orange),
          ),
        ]);
      },
    );
  }
}

// 정수 입력 필드
class _IntField extends StatefulWidget {
  final int value;
  final int min, max;
  final Color color;
  final ValueChanged<int> onChanged;
  const _IntField({required this.value, required this.min, required this.max,
    required this.color, required this.onChanged});

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late TextEditingController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: '${widget.value}'); }
  @override
  void didUpdateWidget(_IntField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ctrl.text = '${widget.value}';
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(fontSize: 11, color: widget.color, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: widget.color.withValues(alpha: 0.5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: widget.color.withValues(alpha: 0.3))),
        filled: true, fillColor: widget.color.withValues(alpha: 0.05),
      ),
      onSubmitted: (s) {
        final v = int.tryParse(s) ?? widget.value;
        widget.onChanged(v.clamp(widget.min, widget.max));
      },
    );
  }
}

// ============================================================
// ④ 제품 설정 패널 (다수 제품 지원)
// ============================================================
class ProductPanel extends StatelessWidget {
  const ProductPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 헤더 + 제품 추가/제거
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 3),
            child: Row(children: [
              const Icon(Icons.widgets, size: 13, color: Colors.lightBlue),
              const SizedBox(width: 5),
              const Text('제품 Cathode (−)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
              const SizedBox(width: 6),
              Expanded(child: Divider(
                  color: Colors.lightBlue.withValues(alpha: 0.25), height: 1)),
              const SizedBox(width: 4),
              // 제품 추가
              _smallBtn(
                icon: Icons.add,
                color: Colors.lightBlue,
                onTap: p.productCount < 10 ? () => p.addProduct() : null,
                tooltip: '제품 추가 (최대 10개)',
              ),
            ]),
          ),

          // 제품 탭 선택
          if (p.productCount > 1) _buildProductTabs(p),

          // 선택된 제품 설정
          _ProductSettingsCard(
            product: p.product,
            productIndex: p.selectedProductIndex,
            tank: p.tank,
            canRemove: p.productCount > 1,
          ),
        ]);
      },
    );
  }

  Widget _buildProductTabs(PlatingProvider p) {
    return SizedBox(
      height: 30,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: p.productCount,
        itemBuilder: (ctx, i) {
          final isSelected = i == p.selectedProductIndex;
          return GestureDetector(
            onTap: () => p.selectProduct(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.lightBlue.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected
                      ? Colors.lightBlueAccent
                      : Colors.white24,
                ),
              ),
              child: Text(
                '제품 ${i + 1}',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.lightBlueAccent : Colors.white54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _smallBtn({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: onTap != null ? 0.15 : 0.05),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: onTap != null ? 0.5 : 0.2)),
          ),
          child: Icon(icon, size: 13,
            color: color.withValues(alpha: onTap != null ? 1.0 : 0.3)),
        ),
      ),
    );
  }
}

Future<void> _pickCadFile(BuildContext context, PlatingProvider pp, int productIndex) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    debugPrint('CAD pick start: productIndex=$productIndex');

    final picked = kIsWeb
        ? await pickCadFileForWeb()
        : await _pickCadFileWithPlugin();
    if (picked == null) return;

    final fileName = picked.fileName;
    final ext = picked.fileType;
    final bytes = picked.bytes;
    final fileSize = bytes?.length ?? 0;
    final isMeshFormat = ext == 'STL';
    final unsupportedPreviewFormat = ext == 'STEP' || ext == 'STP' || ext == 'IGES' || ext == 'IGS';

    debugPrint(
      'CAD picked: name=$fileName, ext=$ext, path=${kIsWeb ? '<web-html-input>' : '<plugin-file>'}, '
      'bytes=${bytes?.length ?? 0}, size=$fileSize',
    );

    if (isMeshFormat && (bytes == null || bytes.isEmpty)) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('STL 파일 데이터를 읽지 못했습니다. 다른 STL 파일로 다시 시도해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (unsupportedPreviewFormat) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('$ext 형식은 메타데이터 첨부만 지원합니다. 미리보기는 STL에서만 표시됩니다.'),
          backgroundColor: Colors.indigo,
        ),
      );
    }

    debugPrint('CAD attach request: ext=$ext, hasBytes=${bytes != null && bytes.isNotEmpty}, size=${bytes?.length ?? 0}');
    final attachError = pp.attachCadFile(
      index: productIndex,
      fileName: fileName,
      fileType: ext,
      bytes: bytes,
    );

    if (attachError != null) {
      debugPrint('CAD attach error: $attachError');
      messenger?.showSnackBar(
        SnackBar(
          content: Text('CAD 파일 첨부 실패: $attachError'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debugPrint('CAD attach success: $fileName');
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$fileName 파일을 첨부했습니다.'),
        backgroundColor: Colors.indigo,
      ),
    );
  } catch (e, st) {
    debugPrint('CAD picker exception: $e');
    debugPrint('$st');
    final message = e.toString().replaceFirst('Exception: ', '');
    messenger?.showSnackBar(
      SnackBar(
        content: Text('CAD 파일 첨부 실패: $message'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<PickedCadFile?> _pickCadFileWithPlugin() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['stl', 'step', 'stp', 'iges', 'igs'],
    withData: true,
    withReadStream: false,
    allowMultiple: false,
    readSequential: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  final fileName = file.name;
  final dot = fileName.lastIndexOf('.');
  var ext = dot >= 0 ? fileName.substring(dot + 1).toUpperCase() : 'CAD';
  if (ext.isEmpty) ext = 'CAD';

  Uint8List? bytes = file.bytes;
  if ((bytes == null || bytes.isEmpty) && !kIsWeb) {
    String? localPath;
    try {
      localPath = file.path;
    } catch (pathError, pathStack) {
      debugPrint('CAD local path unavailable: $pathError');
      debugPrint('$pathStack');
      localPath = null;
    }
    if (localPath != null && localPath.isNotEmpty) {
      try {
        bytes = await File(localPath).readAsBytes();
      } catch (readError, readStack) {
        debugPrint('CAD readAsBytes fallback failed: $readError');
        debugPrint('$readStack');
      }
    }
  }

  return PickedCadFile(fileName: fileName, fileType: ext, bytes: bytes);
}

// 개별 제품 설정 카드
class _ProductSettingsCard extends StatelessWidget {
  final ProductSettings product;
  final int productIndex;
  final TankSettings tank;
  final bool canRemove;

  const _ProductSettingsCard({
    required this.product,
    required this.productIndex,
    required this.tank,
    required this.canRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.lightBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.25)),
      ),
      child: Consumer<PlatingProvider>(
        builder: (ctx, pp, _) {
          final prod = pp.products[productIndex];
          final areaDm2 = prod.surfaceAreaDm2;

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 헤더
            Row(children: [
              Text(
                '제품 ${productIndex + 1}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.lightBlue),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '표면적: ${areaDm2.toStringAsFixed(3)} dm²',
                  style: const TextStyle(fontSize: 9, color: Colors.tealAccent),
                ),
              ),
              const Spacer(),
              if (canRemove)
                GestureDetector(
                  onTap: () => pp.removeProduct(productIndex),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.red),
                  ),
                ),
            ]),
            const SizedBox(height: 6),

            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('기본 재질', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<BaseMaterial>(
                    initialValue: prod.material,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Colors.white24)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                    ),
                    dropdownColor: const Color(0xFF1A2035),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    items: BaseMaterial.values.map((m) => DropdownMenuItem(
                      value: m,
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: m.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Text(m.label, style: const TextStyle(fontSize: 11)),
                      ]),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        pp.updateProductMaterial(productIndex, v);
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: prod.material.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: prod.material.color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      prod.material.processNote,
                      style: TextStyle(fontSize: 10, color: prod.material.color),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.indigo.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.upload_file, size: 13, color: Colors.indigoAccent),
                        const SizedBox(width: 5),
                        const Text('3D CAD 파일',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _pickCadFile(context, pp, productIndex),
                          icon: const Icon(Icons.attach_file, size: 12),
                          label: Text(prod.cadImport.isImported ? '다시 첨부' : 'CAD 첨부',
                              style: const TextStyle(fontSize: 10)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigoAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      prod.cadImport.isImported
                          ? '${prod.cadImport.fileName} · ${prod.cadImport.fileType} · 형상 반영됨'
                          : 'STL / STEP / IGES 형식 CAD 첨부를 지원하며, 첨부 시 제품 형상 참조 상태로 반영됩니다.',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      prod.cadImport.summary,
                      style: const TextStyle(fontSize: 9, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),

            // 레고 모드 토글
            Row(children: [
              const Icon(Icons.extension, size: 11, color: Colors.purpleAccent),
              const SizedBox(width: 4),
              const Text('레고 복합 모델링', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const Spacer(),
              Switch(
                value: prod.useLegoMode,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(useLegoMode: v)),
                activeThumbColor: Colors.purpleAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),

            if (prod.useLegoMode) ...[
              // 레고 피스 관리
              _buildLegoSection(context, pp, prod),
            ] else ...[
              // 일반 제품 설정
              // 형태 선택
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('제품 형태', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(height: 3),
                  DropdownButtonFormField<ProductShape>(
                    initialValue: prod.shape,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Colors.white24)),
                      filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
                    ),
                    dropdownColor: const Color(0xFF1A2035),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    items: ProductShape.values.map((s) => DropdownMenuItem(
                      value: s, child: Text(s.label, style: const TextStyle(fontSize: 11)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) pp.updateProductAt(productIndex, prod.copyWith(shape: v));
                    },
                  ),
                ]),
              ),

              NumericField(label: 'X 폭', value: prod.width, min: 1, max: tank.width, unit: 'cm',
                color: Colors.lightBlue,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(width: v))),
              NumericField(label: 'Y 깊이', value: prod.depth, min: 1, max: tank.depth, unit: 'cm',
                color: Colors.lightBlue,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(depth: v))),
              NumericField(label: 'Z 길이', value: prod.length, min: 1, max: tank.length, unit: 'cm',
                color: Colors.lightBlue,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(length: v))),

              if (prod.shape == ProductShape.hollowBox || prod.shape == ProductShape.pipe)
                NumericField(label: '벽 두께', value: prod.wallThickness,
                  min: 0.5, max: prod.width / 2, unit: 'cm',
                  color: Colors.cyan,
                  onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(wallThickness: v))),

              NumericField(label: 'X 위치', value: prod.posX,
                min: -tank.width/2 + prod.width/2,
                max: tank.width/2 - prod.width/2,
                unit: 'cm', color: Colors.cyan, decimals: 1,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posX: v))),
              NumericField(label: 'Y 위치(바닥)', value: prod.posY, min: 0,
                max: (tank.solutionLevel - prod.depth).clamp(0, tank.depth),
                unit: 'cm', color: Colors.cyan, decimals: 1,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posY: v))),
              NumericField(label: 'Z 위치', value: prod.posZ,
                min: -tank.length/2 + prod.length/2,
                max: tank.length/2 - prod.length/2,
                unit: 'cm', color: Colors.cyan, decimals: 1,
                onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posZ: v))),

              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('초기 표시 기준', style: TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('• 제품은 불투명 재질로 렌더링됩니다.', style: TextStyle(fontSize: 10, color: Colors.white60)),
                    Text('• 시작 화면은 정면의 반대편이 아닌 가시 면 중심의 등각 시점으로 설정됩니다.', style: TextStyle(fontSize: 10, color: Colors.white60)),
                    Text('• 도금 두께와 전기장선은 보여지는 전면/모서리/굴곡부를 우선 강조합니다.', style: TextStyle(fontSize: 10, color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ]);
        },
      ),
    );
  }

  Widget _buildLegoSection(BuildContext context, PlatingProvider pp, ProductSettings prod) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 제품 기준 위치
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 2),
        child: Text('기준 위치', style: TextStyle(fontSize: 11, color: Colors.purpleAccent)),
      ),
      NumericField(label: 'X 위치', value: prod.posX,
        min: -tank.width/2 + prod.width/2,
        max: tank.width/2 - prod.width/2,
        unit: 'cm', color: Colors.purple, decimals: 1,
        onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posX: v))),
      NumericField(label: 'Y 위치(바닥)', value: prod.posY, min: 0,
        max: tank.solutionLevel.clamp(0, tank.depth),
        unit: 'cm', color: Colors.purple, decimals: 1,
        onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posY: v))),
      NumericField(label: 'Z 위치', value: prod.posZ,
        min: -tank.length/2, max: tank.length/2,
        unit: 'cm', color: Colors.purple, decimals: 1,
        onChanged: (v) => pp.updateProductAt(productIndex, prod.copyWith(posZ: v))),

      // 피스 목록
      Row(children: [
        const Text('레고 피스', style: TextStyle(fontSize: 11, color: Colors.purpleAccent)),
        const Spacer(),
        TextButton.icon(
          onPressed: prod.legoPieces.length < 12
              ? () => pp.addLegoPiece(productIndex)
              : null,
          icon: const Icon(Icons.add, size: 12),
          label: const Text('피스 추가', style: TextStyle(fontSize: 10)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.purpleAccent,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ]),

      if (prod.legoPieces.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('피스를 추가하세요 (최대 12개)',
              style: TextStyle(fontSize: 10, color: Colors.white38)),
        ),

      ...prod.legoPieces.map((piece) => _LegoPieceWidget(
        piece: piece,
        productIndex: productIndex,
      )),
    ]);
  }
}

// 레고 피스 편집 위젯
class _LegoPieceWidget extends StatelessWidget {
  final LegoPiece piece;
  final int productIndex;

  const _LegoPieceWidget({
    required this.piece,
    required this.productIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: piece.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: piece.color.withValues(alpha: 0.4)),
      ),
      child: Consumer<PlatingProvider>(
        builder: (ctx, pp, _) {
          final currentProduct = pp.products[productIndex];
          final currentPiece = currentProduct.legoPieces
              .firstWhere((pc) => pc.id == piece.id, orElse: () => piece);

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(color: currentPiece.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('피스 ${currentProduct.legoPieces.indexOf(currentPiece) + 1}',
                style: TextStyle(fontSize: 11, color: currentPiece.color, fontWeight: FontWeight.bold)),
              const Spacer(),
              // 형태 선택
              DropdownButton<LegoPieceShape>(
                value: currentPiece.shape,
                isDense: true,
                dropdownColor: const Color(0xFF1A2035),
                style: const TextStyle(fontSize: 10, color: Colors.white),
                underline: const SizedBox(),
                items: LegoPieceShape.values.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s == LegoPieceShape.box ? '육면체'
                      : s == LegoPieceShape.cylinder ? '원기둥' : '구',
                    style: const TextStyle(fontSize: 10),
                  ),
                )).toList(),
                onChanged: (v) {
                  if (v != null) {
                    pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(shape: v));
                  }
                },
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => pp.removeLegoPiece(productIndex, piece.id),
                child: const Icon(Icons.close, size: 13, color: Colors.red),
              ),
            ]),
            const SizedBox(height: 4),
            _pieceNum('X 크기', currentPiece.width, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(width: v))),
            _pieceNum('Y 크기', currentPiece.height, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(height: v))),
            _pieceNum('Z 크기', currentPiece.length, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(length: v))),
            _pieceNum('X 오프셋', currentPiece.offsetX, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(offsetX: v)),
              allowNeg: true),
            _pieceNum('Y 오프셋', currentPiece.offsetY, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(offsetY: v)),
              allowNeg: true),
            _pieceNum('Z 오프셋', currentPiece.offsetZ, (v) =>
              pp.updateLegoPiece(productIndex, piece.id, currentPiece.copyWith(offsetZ: v)),
              allowNeg: true),
          ]);
        },
      ),
    );
  }

  Widget _pieceNum(String label, double value, ValueChanged<double> onChanged, {bool allowNeg = false}) {
    return _InlineNumeric(
      label: label,
      value: value,
      min: allowNeg ? -200.0 : 0.5,
      max: allowNeg ? 200.0 : 200.0,
      onChanged: onChanged,
      decimals: 1,
    );
  }
}

// 인라인 숫자 입력 (소형)
class _InlineNumeric extends StatefulWidget {
  final String label;
  final double value;
  final double min, max;
  final ValueChanged<double> onChanged;
  final int decimals;

  const _InlineNumeric({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimals = 0,
  });

  @override
  State<_InlineNumeric> createState() => _InlineNumericState();
}

class _InlineNumericState extends State<_InlineNumeric> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(widget.decimals));
  }

  @override
  void didUpdateWidget(_InlineNumeric old) {
    super.didUpdateWidget(old);
    if (!_editing && (old.value - widget.value).abs() > 0.001) {
      _ctrl.text = widget.value.toStringAsFixed(widget.decimals);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 65,
          child: Text(widget.label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ),
        SizedBox(
          width: 55, height: 24,
          child: TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
            style: const TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: Colors.purple.withValues(alpha: 0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              filled: true,
              fillColor: Colors.purple.withValues(alpha: 0.05),
            ),
            onTap: () => setState(() => _editing = true),
            onSubmitted: (s) {
              final v = double.tryParse(s);
              if (v != null) {
                final clamped = v.clamp(widget.min, widget.max);
                widget.onChanged(clamped);
                _ctrl.text = clamped.toStringAsFixed(widget.decimals);
              } else {
                _ctrl.text = widget.value.toStringAsFixed(widget.decimals);
              }
              setState(() => _editing = false);
            },
            onEditingComplete: () {
              final v = double.tryParse(_ctrl.text);
              if (v != null) {
                final clamped = v.clamp(widget.min, widget.max);
                widget.onChanged(clamped);
                _ctrl.text = clamped.toStringAsFixed(widget.decimals);
              }
              setState(() => _editing = false);
            },
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.purple,
              thumbColor: Colors.purpleAccent,
              inactiveTrackColor: Colors.white10,
              trackHeight: 1.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            ),
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max),
              min: widget.min, max: widget.max,
              onChanged: (v) {
                widget.onChanged(v);
                if (!_editing) _ctrl.text = v.toStringAsFixed(widget.decimals);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// ⑤ 마스킹 패널
// ============================================================
class MaskingPanel extends StatelessWidget {
  const MaskingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHdr(title: '마스킹 구역', icon: Icons.block, color: Colors.purple),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '* 마스킹: 도금이 되지 않는 보호 영역 (제품 표면 0~100% 기준)',
              style: TextStyle(fontSize: 9, color: Colors.white38),
            ),
          ),

          TextButton.icon(
            onPressed: p.maskingZones.length < 8 ? p.addMaskingZone : null,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('마스킹 추가', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.purple,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),

          if (p.maskingZones.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('마스킹 없음', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ),

          ...p.maskingZones.map((zone) => _MaskingZoneWidget(zone: zone)),
        ]);
      },
    );
  }
}

class _MaskingZoneWidget extends StatelessWidget {
  final MaskingZone zone;
  const _MaskingZoneWidget({required this.zone});

  @override
  Widget build(BuildContext context) {
    final p = context.read<PlatingProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.block, size: 12, color: Colors.purple),
          const SizedBox(width: 5),
          Text(zone.label, style: const TextStyle(fontSize: 11, color: Colors.purple)),
          const Spacer(),
          GestureDetector(
            onTap: () => p.removeMaskingZone(zone.id),
            child: const Icon(Icons.close, size: 14, color: Colors.red),
          ),
        ]),
        const SizedBox(height: 4),
        _rangeRow('X 범위', zone.xMin, zone.xMax,
          (mn, mx) => p.updateMaskingZone(zone.id, zone.copyWith(xMin: mn, xMax: mx))),
        _rangeRow('Y 범위', zone.yMin, zone.yMax,
          (mn, mx) => p.updateMaskingZone(zone.id, zone.copyWith(yMin: mn, yMax: mx))),
        _rangeRow('Z 범위', zone.zMin, zone.zMax,
          (mn, mx) => p.updateMaskingZone(zone.id, zone.copyWith(zMin: mn, zMax: mx))),
      ]),
    );
  }

  Widget _rangeRow(String label, double min, double max,
      void Function(double, double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 50,
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54))),
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
        Text('${(min*100).toStringAsFixed(0)}-${(max*100).toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 9, color: Colors.purple)),
      ]),
    );
  }
}
