import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plating_provider.dart';
import '../models/plating_models.dart';

// ============================================================
// 분석 결과 탭
// ============================================================
class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlatingProvider>(
      builder: (ctx, p, _) {
        final result = p.analysisResult;
        if (result == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, size: 48, color: Colors.white24),
                const SizedBox(height: 16),
                const Text('시뮬레이션을 실행하세요',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('상단의 "시뮬레이션" 버튼을 누르세요',
                    style: TextStyle(color: Colors.white24, fontSize: 12)),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 종합 평가
              _buildGradeCard(result),
              const SizedBox(height: 10),
              // 표면적 + 권장 전류/전압
              _buildSurfaceAreaCard(result, p),
              const SizedBox(height: 10),
              // 두께 통계
              _buildThicknessCard(result),
              const SizedBox(height: 10),
              // 전류밀도
              _buildCurrentDensityCard(result, p.elec),
              const SizedBox(height: 10),
              _buildMaterialImpactCard(p),
              const SizedBox(height: 10),
              // 다수 제품 분석 (2개 이상일 때)
              if (p.productCount > 1) ...[
                _buildMultiProductCard(p),
                const SizedBox(height: 10),
              ],
              // 경고
              if (result.warnings.isNotEmpty) _buildWarningsCard(result),
              if (result.warnings.isNotEmpty) const SizedBox(height: 10),
              // 권장사항
              _buildRecommendationsCard(result),
              const SizedBox(height: 10),
              // Faraday 계산
              _buildFaradayCard(result, p.elec, p.totalSurfaceAreaDm2),
            ],
          ),
        );
      },
    );
  }

  // 종합 평가 카드
  Widget _buildGradeCard(AnalysisResult r) {
    final gradeColors = {
      'A': Colors.green, 'B': Colors.lightGreen,
      'C': Colors.orange, 'D': Colors.red,
    };
    final color = gradeColors[r.overallGrade] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(r.overallGrade,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('종합 평가: ${_gradeLabel(r.overallGrade)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text('균일도: ${(r.uniformityIndex * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 2),
            LinearProgressIndicator(
              value: r.uniformityIndex,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
        ),
      ]),
    );
  }

  String _gradeLabel(String g) {
    switch (g) {
      case 'A': return '우수 (최적 조건)';
      case 'B': return '양호 (약간 조정 필요)';
      case 'C': return '보통 (개선 권장)';
      case 'D': return '불량 (조건 재검토)';
      default: return '평가 불가';
    }
  }

  // 표면적 + 권장 전류/전압 카드
  Widget _buildSurfaceAreaCard(AnalysisResult r, PlatingProvider p) {
    return _card(
      title: '표면적 및 권장 설정',
      icon: Icons.area_chart,
      color: Colors.teal,
      children: [
        _statRow('총 표면적', '${r.totalSurfaceAreaDm2.toStringAsFixed(3)} dm²', Colors.tealAccent),
        _statRow('권장 전류', '${r.recommendedCurrent.toStringAsFixed(2)} A', Colors.greenAccent),
        _statRow('권장 전압', '${r.recommendedVoltage.toStringAsFixed(2)} V', Colors.lime),
        _statRow('현재 전류', '${p.elec.current.toStringAsFixed(1)} A',
          (r.recommendedCurrent > 0 &&
           (p.elec.current - r.recommendedCurrent).abs() / r.recommendedCurrent.clamp(0.001, 100000) < 0.3)
              ? Colors.green : Colors.orange),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            '💡 "표면적 기준 적정 전류/전압 자동 산출" 버튼으로\n전기 설정을 자동으로 최적화할 수 있습니다.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ),
      ],
    );
  }

  // 두께 통계 카드
  Widget _buildThicknessCard(AnalysisResult r) {
    return _card(
      title: '도금 두께 분석',
      icon: Icons.layers,
      color: Colors.cyan,
      children: [
        _statRow('최소 두께', '${r.minThickness.toStringAsFixed(2)} µm', Colors.blue),
        _statRow('최대 두께', '${r.maxThickness.toStringAsFixed(2)} µm', Colors.red),
        _statRow('평균 두께', '${r.avgThickness.toStringAsFixed(2)} µm', Colors.green),
        _statRow('두께 편차',
          '${(r.maxThickness - r.minThickness).toStringAsFixed(2)} µm', Colors.orange),
        const SizedBox(height: 8),
        _buildThicknessBar(r),
      ],
    );
  }

  Widget _buildThicknessBar(AnalysisResult r) {
    final total = r.maxThickness - r.minThickness;
    if (total < 0.001) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('두께 분포', style: TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 4),
        Container(
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: [Color(0xFF0000FF), Color(0xFF00FF00),
                       Color(0xFFFFFF00), Color(0xFFFF0000)],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${r.minThickness.toStringAsFixed(1)} µm',
              style: const TextStyle(fontSize: 9, color: Colors.blue)),
            Text('${r.avgThickness.toStringAsFixed(1)} µm',
              style: const TextStyle(fontSize: 9, color: Colors.green)),
            Text('${r.maxThickness.toStringAsFixed(1)} µm',
              style: const TextStyle(fontSize: 9, color: Colors.red)),
          ],
        ),
      ],
    );
  }

  // 전류밀도 카드
  Widget _buildCurrentDensityCard(AnalysisResult r, ElectricalSettings e) {
    final cdRange = e.platingType.currentDensityRange;
    final isInRange = r.avgCurrentDensity >= cdRange.$1 && r.avgCurrentDensity <= cdRange.$2;

    return _card(
      title: '전류밀도 분석',
      icon: Icons.electric_bolt,
      color: Colors.orange,
      children: [
        _statRow('평균 전류밀도',
          '${r.avgCurrentDensity.toStringAsFixed(3)} A/dm²',
          isInRange ? Colors.green : Colors.orange),
        _statRow('권장 범위', '${cdRange.$1}~${cdRange.$2} A/dm²', Colors.white70),
        _statRow('총 전하량', '${r.totalCharge.toStringAsFixed(1)} A·min', Colors.cyan),
        _statRow('전류효율', '${e.platingType.currentEfficiency}%', Colors.tealAccent),
        const SizedBox(height: 6),
        _buildCdGauge(r.avgCurrentDensity, cdRange.$1, cdRange.$2),
      ],
    );
  }

  Widget _buildCdGauge(double current, double min, double max) {
    final extended = max * 1.5;
    final normalizedCurrent = (current / extended).clamp(0.0, 1.0);
    final normalizedMin = min / extended;
    final normalizedMax = max / extended;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                ),
                Positioned(
                  left: normalizedMin * width,
                  width: (normalizedMax - normalizedMin) * width,
                  top: 0, bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                Positioned(
                  left: (normalizedCurrent * width - 2).clamp(0, width - 4),
                  top: 2, bottom: 2, width: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0', style: TextStyle(fontSize: 9, color: Colors.white38)),
            const Text('권장 범위', style: TextStyle(fontSize: 9, color: Colors.green)),
            Text(extended.toStringAsFixed(0),
              style: const TextStyle(fontSize: 9, color: Colors.white38)),
          ],
        ),
      ],
    );
  }

  Widget _buildMaterialImpactCard(PlatingProvider p) {
    return _card(
      title: '재질 영향성 검토',
      icon: Icons.precision_manufacturing,
      color: Colors.amber,
      children: [
        ...p.products.asMap().entries.map((entry) {
          final product = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: product.material.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: product.material.color.withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: product.material.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('제품 ${entry.key + 1} · ${product.material.label}',
                          style: TextStyle(fontSize: 11, color: product.material.color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(product.material.processNote,
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    '전도도 계수 ${product.material.conductivityFactor.toStringAsFixed(2)} · '
                    '차폐 계수 ${product.material.shieldingFactor.toStringAsFixed(2)} · '
                    'throw power ${product.material.throwPowerFactor.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // 다수 제품 분석 카드
  Widget _buildMultiProductCard(PlatingProvider p) {
    return _card(
      title: '다수 제품 분석',
      icon: Icons.widgets,
      color: Colors.lightBlue,
      children: [
        _statRow('제품 수', '${p.productCount}개', Colors.lightBlueAccent),
        _statRow('총 표면적', '${p.totalSurfaceAreaDm2.toStringAsFixed(3)} dm²', Colors.tealAccent),
        const Divider(color: Colors.white12, height: 10),
        ...p.products.asMap().entries.map((entry) {
          final i = entry.key;
          final prod = entry.value;
          final areaDm2 = prod.surfaceAreaDm2;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.lightBlue.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text('${i+1}',
                    style: const TextStyle(fontSize: 9, color: Colors.lightBlueAccent)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(prod.shape.label,
                    style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  Text(
                    '${prod.width.toStringAsFixed(0)}×${prod.depth.toStringAsFixed(0)}×'
                    '${prod.length.toStringAsFixed(0)} cm  |  ${areaDm2.toStringAsFixed(3)} dm²'
                    '${prod.useLegoMode ? "  [레고]" : ""}',
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                ]),
              ),
            ]),
          );
        }),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.lightBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            '* 다수 제품: 마주보는 면은 차폐 효과로 도금 두께 감소 적용됨\n'
            '* 제품 간 거리가 넓을수록 균일도 향상',
            style: TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ),
      ],
    );
  }

  // 경고 카드
  Widget _buildWarningsCard(AnalysisResult r) {
    return _card(
      title: '주의 사항',
      icon: Icons.warning_amber,
      color: Colors.orange,
      children: r.warnings.map((w) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning, size: 13, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(w, style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          ],
        ),
      )).toList(),
    );
  }

  // 권장사항 카드
  Widget _buildRecommendationsCard(AnalysisResult r) {
    return _card(
      title: '개선 권장사항',
      icon: Icons.lightbulb_outline,
      color: Colors.greenAccent,
      children: r.recommendations.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withValues(alpha: 0.2),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text('${e.key + 1}',
                  style: const TextStyle(fontSize: 9, color: Colors.greenAccent)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.value,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
      )).toList(),
    );
  }

  // Faraday 계산 카드
  Widget _buildFaradayCard(AnalysisResult r, ElectricalSettings e, double areaDm2) {
    const F = 96485.0;
    // 이론 평균 두께 계산 (표면적 기반)
    final effectiveArea = areaDm2.clamp(0.001, 100000.0);
    final avgCd = e.current / effectiveArea;
    final expectedThickness = (e.platingType.atomicWeight * avgCd * 0.01 *
        e.platingTime * 60 * (e.platingType.currentEfficiency / 100)) /
        (e.platingType.valence * F * e.platingType.density * 0.01) * 1e4;

    return _card(
      title: 'Faraday 법칙 계산',
      icon: Icons.functions,
      color: Colors.purpleAccent,
      children: [
        const Text(
          't(µm) = (M·Cd·A·T·η) / (n·F·ρ·A_patch) × 10⁴',
          style: TextStyle(fontSize: 9, color: Colors.purpleAccent, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 6),
        _statRow('원자량 M', '${e.platingType.atomicWeight} g/mol', Colors.white70),
        _statRow('전류 I', '${e.current.toStringAsFixed(1)} A', Colors.white70),
        _statRow('표면적', '${areaDm2.toStringAsFixed(3)} dm²', Colors.tealAccent),
        _statRow('전류밀도 Cd', '${avgCd.toStringAsFixed(3)} A/dm²', Colors.greenAccent),
        _statRow('시간 T', '${(e.platingTime * 60).toStringAsFixed(0)} s', Colors.white70),
        _statRow('전류효율 η', '${e.platingType.currentEfficiency}%', Colors.white70),
        _statRow('원자가 n', '${e.platingType.valence}', Colors.white70),
        _statRow('밀도 ρ', '${e.platingType.density} g/cm³', Colors.white70),
        const Divider(color: Colors.white12),
        _statRow('이론 평균 두께',
          '${expectedThickness.toStringAsFixed(3)} µm', Colors.purpleAccent),
        _statRow('시뮬 평균 두께',
          '${r.avgThickness.toStringAsFixed(3)} µm', Colors.cyan),
        _statRow('이론/시뮬 비율',
          expectedThickness > 0
              ? '${(r.avgThickness / expectedThickness * 100).toStringAsFixed(1)}%'
              : 'N/A',
          Colors.white60),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _statRow(String key, String val, Color valColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          Text(val, style: TextStyle(
            fontSize: 11, color: valColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
