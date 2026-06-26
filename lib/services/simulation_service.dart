import 'dart:math' as math;
import '../models/plating_models.dart';

// ============================================================
// 전기도금 물리 시뮬레이션 서비스 v11
// ─ 좌표계: X=폭, Y=높이(바닥=0), Z=길이
//
// 물리 개선 (v11) — 사용자 정의 물리법칙 완전 정합:
//  [법칙] (1) 거리가 짧을수록 두껍다(거리=최우선 지배).
//         (2) 양극을 "정면으로" 볼 때 가장 두껍다.
//         (3) 정면이 아니어도 가까우면 두껍다(단, 정면보다 낮게).
//         (4) 멀어지면 끝단이라도 얇다.
//         (5) 사이에 제품/차폐막이 있으면 방해받는다(shadow).
//  ★★ 윗면만 두껍고 측면이 파랗던 v10 문제 해결.
//     모든 노출면을 "통일 공식"으로 계산:
//       기여 = (기본노출 + 정면보너스·alignment + 측면보너스 + 우회) ×
//              invDist(거리) × 정렬보정 × 거리집중
//     → 정면 측면이 최대, 윗면/비정면은 그보다 낮게, 멀면 얇게.
//  ★ exposureFactor 중복증폭 제거(면균형은 faceTerm 이 전담).
//  → test: 정면측면 최대 / 측면 두께 형성 / 거리단조 / 차폐 검증 통과.
//
// 물리 개선 (v10) — "윗면 두께" 정합성 + 면 균형 회복:
//  ★★ 양극을 "세로로 긴 막대"로 모델링 — 표면점→양극 거리를 중심점이
//     아니라 막대(높이=depth, 길이=length) 위 "최근접점"으로 계산.
//     [효과] 키 큰(높이 솟은) 제품의 윗면이 양극 상단과 가까워져
//            정상적으로 두껍게 형성됨. (v9 에서 가까운 제품 윗면이
//            파랗게 죽던 문제 = 양극을 점으로 봐서 윗면이 멀다고 오판)
//  ★ faceBias 의 거리 이중감쇠 제거 — 거리 단조성은 distanceDominance
//    하나로만 보장, faceBias 는 면별 분포만 결정.
//  ★ 측면 정면(directTerm) 단일점 과집중 완화 + 윗면(topTerm) 비중 상향
//    + 모서리(dogbone/curvature) 스파이크 완화 → 면 전반 균형.
//  → test: 가까운 제품 윗면 두꺼움 + 거리 단조감소를 5개 구성에서 검증.
//
// 물리 개선 (v9) — 거리-두께 정합성 "완전" 보장:
//  ★★ 정규화 이후 적용되던 normalBias(상/측면 최대 1.82배 증폭)를
//     1차 가중치 단계로 이동 → 전류보존·거리게이트의 지배를 받게 함.
//     (먼 제품의 "윗면 모서리 빨강 과도금" 비물리 현상의 주원인 제거)
//  ★★ positionBoost / proximityBoost / faceBias 의 "보너스(1.0 초과분)"를
//     모두 distanceDominance(edgeGate)로 감쇠 → 어떤 정렬/형상/높이에서도
//     멀어질수록 두께가 증가하는 역전이 발생하지 않음.
//  → test/repro_test.dart: 다양한 양극 구성(following/absolute, count1/2,
//    spacing, 장대양극, 급경사 대각선)에서 단조성 검증 통과.
//
// 물리 개선 (v8) — 거리-두께 정합성 강화:
//  ★ 거리 지배 인자(distanceDominance) 도입
//     - 최근접 양극까지의 실제 거리에 1/r² 단조감쇠 게이트 적용
//     - 면별 노출/면적 보정이 거리 손실을 "역전"시키지 못하도록 묶음
//     → "양극에서 멀수록 도금 두께가 반드시 얇아진다" 보장
//  ★ 면별 노출 부스트(top/bottom/side/backside)를 곱셈 누적에서
//    상한이 있는 합산형 exposureFactor 로 전환 (폭주 방지)
//
// 기존 개선 (v7):
//  1. 전기력선 전방향 방출 — 양극 6면 + 모든 모서리에서 방출
//  2. 양극 간 간격(anodeSpacing) 독립 조절 지원
//  3. 제품/양극 위치 분리 — absolutePosition 플래그
//  4. 도금 두께 과다 수정 — dirFactor 정규화 버그 해결
//  5. 셀 수 대폭 증가 — 더 촘촘한 표면
//  6. 전기장 분포 히트맵 데이터
// ============================================================
class PlatingSimulationService {
  static const double faradayConst = 96485.0; // C/mol

  // ----------------------------------------------------------
  // 용액 내 여부
  // ----------------------------------------------------------
  static bool _inSolution(Vec3 p, double sl) =>
      p.y >= -0.01 && p.y <= sl + 0.01;

  // ----------------------------------------------------------
  // 양극 위치 목록
  // absolutePosition=true 이면 제품 위치 무관하게 고정 기준
  // ----------------------------------------------------------
  static List<(Vec3, Vec3)> getAnodePositions({
    required TankSettings tank,
    required AnodeSettings anode,
    required ProductSettings product,
  }) =>
      getAnodePositionsMulti(tank: tank, anode: anode, products: [product]);

  static List<(Vec3, Vec3)> getAnodePositionsMulti({
    required TankSettings tank,
    required AnodeSettings anode,
    required List<ProductSettings> products,
  }) {
    if (products.isEmpty) return [];

    // 기준점: absolutePosition이면 탱크 중심, 아니면 제품 평균 중심
    double baseX, baseZ;
    if (anode.absolutePosition) {
      baseX = 0.0 + anode.posXOffset;
      baseZ = 0.0 + anode.posZOffset;
    } else {
      final avgX =
          products.map((p) => p.posX).reduce((a, b) => a + b) / products.length;
      final avgZ =
          products.map((p) => p.posZ).reduce((a, b) => a + b) / products.length;
      baseX = avgX + anode.posXOffset;
      baseZ = avgZ + anode.posZOffset;
    }

    final anodeCY = anode.yOffset + anode.depth / 2;

    // 양극 쌍 수
    final pairs = ((anode.count + 1) ~/ 2).clamp(1, 10);

    // 양극 간 Z 간격: 0이면 자동(length * 1.5), 양수면 직접 지정
    final zSpacing = pairs > 1
        ? (anode.anodeSpacing > 0
            ? anode.anodeSpacing
            : anode.length * 1.5)
        : 0.0;
    final zStart = -(pairs - 1) * zSpacing / 2;

    final result = <(Vec3, Vec3)>[];
    for (int i = 0; i < pairs; i++) {
      final zPos = baseZ + zStart + i * zSpacing;
      // 좌측 양극
      result.add((
        Vec3(baseX - anode.distFromProduct, anodeCY, zPos),
        const Vec3(1, 0, 0),
      ));
      // 우측 양극 (count >= 2)
      if (anode.count >= 2) {
        result.add((
          Vec3(baseX + anode.distFromProduct, anodeCY, zPos),
          const Vec3(-1, 0, 0),
        ));
      }
    }
    return result;
  }

  // ----------------------------------------------------------
  // 전기장 스칼라 강도 (1/r)
  // ----------------------------------------------------------
  static double computeFieldStrengthAt(
    Vec3 point,
    List<(Vec3, Vec3)> anodePositions,
    double solutionLevel, {
    AnodeSettings? anode,
  }) {
    if (!_inSolution(point, solutionLevel)) return 0.0;
    double total = 0.0;
    for (final (center, _) in anodePositions) {
      final dist = (point - center).length.clamp(0.5, 10000.0);
      double areaBoost = 1.0;
      if (anode != null) {
        final anodeFaceArea = (anode.depth * anode.length).clamp(1.0, double.infinity);
        areaBoost = 0.72 + math.pow(anodeFaceArea / 250.0, 0.32).toDouble();
      }
      total += areaBoost / math.pow(dist, 1.12).toDouble();
    }
    return total;
  }

  // ----------------------------------------------------------
  // 도그본 효과 (모서리 전류 집중)
  // ----------------------------------------------------------
  static double _dogboneEffect(Vec3 pos, Vec3 normal, ProductSettings prod) {
    final cx = prod.posX;
    final cy = prod.posY + prod.depth / 2;
    final cz = prod.posZ;
    final hw = prod.width / 2;
    final hd = prod.depth / 2;
    final hl = prod.length / 2;

    final dx = hw > 0 ? (pos.x - cx).abs() / hw : 0.0;
    final dy = hd > 0 ? (pos.y - cy).abs() / hd : 0.0;
    final dz = hl > 0 ? (pos.z - cz).abs() / hl : 0.0;

    double edgeFactor;
    if (normal.x.abs() > 0.5) {
      edgeFactor = math.max(dy, dz);
    } else if (normal.y.abs() > 0.5) {
      edgeFactor = math.max(dx, dz);
    } else {
      edgeFactor = math.max(dx, dy);
    }
    // v10: 모서리 집중 완화(0.8→0.45) — 단일 에지점 폭증 방지.
    return 1.0 + 0.45 * math.pow(edgeFactor.clamp(0.0, 1.0), 2.0).toDouble();
  }

  // ----------------------------------------------------------
  // 용액 깊이 보정 (상단 근처 약간 감소)
  // ----------------------------------------------------------
  static double _solutionDepthFactor(Vec3 pos, double sl) {
    if (sl <= 0) return 1.0;
    final ratio = (sl - pos.y) / sl;
    return 0.92 + 0.08 * ratio.clamp(0.0, 1.0);
  }

  // ----------------------------------------------------------
  // 다중 제품 차폐
  // ----------------------------------------------------------
  static double _computeShadowFactor(
    Vec3 pos,
    Vec3 normal,
    List<ProductSettings> allProducts,
    ProductSettings currentProduct,
  ) {
    double shadowFactor = 1.0;
    for (final other in allProducts) {
      if (other.id == currentProduct.id) continue;
      final toOther = Vec3(
        other.posX - pos.x,
        (other.posY + other.depth / 2) - pos.y,
        other.posZ - pos.z,
      );
      final dist = toOther.length;
      if (dist < 0.01) continue;
      final facing = normal.dot(toOther.normalized()).clamp(0.0, 1.0);
      shadowFactor -= facing * math.exp(-dist / 50.0) * 0.4;
    }
    return shadowFactor.clamp(0.2, 1.0);
  }

  // ----------------------------------------------------------
  // ■ 전기력선 계산 (v7 전방향 방출)
  //
  // 실제 전기도금 특성:
  //  - 양극의 모든 면(앞/뒤/위/아래/좌/우)에서 전기력선 방출
  //  - 선들이 굴절하며 제품 모든 면(윗면/아랫면/측면)에 도달
  //  - 일부 선은 돌아서 뒷면에도 도달 (전해질 통해 우회)
  // ----------------------------------------------------------
  static List<FieldLine> computeFieldLines({
    required TankSettings tank,
    required AnodeSettings anode,
    required ProductSettings product,
    required int numLinesPerAnode,
  }) =>
      computeFieldLinesMulti(
        tank: tank,
        anode: anode,
        products: [product],
        numLinesPerAnode: numLinesPerAnode,
      );

  static List<FieldLine> computeFieldLinesMulti({
    required TankSettings tank,
    required AnodeSettings anode,
    required List<ProductSettings> products,
    required int numLinesPerAnode,
  }) {
    if (products.isEmpty) return [];
    final lines = <FieldLine>[];
    final anodePositions = getAnodePositionsMulti(
      tank: tank,
      anode: anode,
      products: products,
    );
    final sl = tank.solutionLevel;

    for (int ai = 0; ai < anodePositions.length; ai++) {
      final (anodeCenter, _) = anodePositions[ai];
      // 양극이 용액 밖이면 건너뜀
      if (anodeCenter.y - anode.depth / 2 > sl) continue;

      // 양극의 유효 Y 범위 (용액 내)
      final anodeYBot = (anodeCenter.y - anode.depth / 2).clamp(0.0, sl);
      final anodeYTop = (anodeCenter.y + anode.depth / 2).clamp(0.0, sl);
      final anodeHL = anode.length / 2;
      final anodeHW = anode.width / 2;

      for (final product in products) {
        final prodCX = product.posX;
        final prodCY = product.posY + product.depth / 2;
        final prodCZ = product.posZ;
        final prodHW = product.width / 2;
        final prodHD = product.depth / 2;
        final prodHL = product.length / 2;
        final cadTargets = product.cadImport.isImported && product.cadImport.triangles.isNotEmpty
            ? _cadTargetPoints(product)
            : const <Vec3>[];

        final distToProduct =
            (anodeCenter - Vec3(prodCX, prodCY, prodCZ)).length;
        final refDist = anode.distFromProduct.clamp(10.0, 500.0);
        if (distToProduct > refDist * 5.0) continue;

        // ────────────────────────────────────────────────────
        // 방출 포인트 전략:
        //  A) 정면 방출 (양극→제품 정면): 강한 강도
        //  B) 위/아래 방출 (양극 상하면→제품 위/아래/측면): 중간 강도
        //  C) 측면 방출 (양극 측면→제품 측면): 약한 강도
        //  D) 돌아가는 선 (양극 뒷면→우회→제품 뒷면): 매우 약한 강도
        // ────────────────────────────────────────────────────
        final isLeft = anodeCenter.x < prodCX;
        final mirrorSign = isLeft ? 1.0 : -1.0;
        // numLinesPerAnode=64 → gridN=8 (8×8=64)
        final denseN = 8;
        final mediumN = 6;
        final sideN = 5;
        final wrapN = 4;

        // ── A) 정면 방출: 양극 전면 → 제품 대향면 (좌우 완전 대칭) ──
        for (int yi = 0; yi < denseN; yi++) {
          for (int zi = 0; zi < denseN; zi++) {
            final yFrac = (yi + 0.5) / denseN;
            final zFrac = (zi + 0.5) / denseN;
            final startY = (anodeYBot + yFrac * (anodeYTop - anodeYBot)).clamp(0.0, sl);
            final startZ = anodeCenter.z + (zFrac - 0.5) * anode.length;
            if (startY > sl) continue;
            final startX = isLeft ? anodeCenter.x + anodeHW : anodeCenter.x - anodeHW;
            final start = Vec3(startX, startY, startZ);
            // 정면 타겟: 동일 Y, Z 위치를 제품 대향면에 정확히 매핑
            final fallbackTarget = Vec3(
              isLeft ? prodCX - prodHW : prodCX + prodHW,
              (prodCY - prodHD + yFrac * prodHD * 2).clamp(0.0, sl),
              prodCZ + (zFrac - 0.5) * prodHL * 2,
            );
            final target = cadTargets.isNotEmpty
                ? _closestCadTargetPoint(
                    product: product,
                    start: start,
                    preferFacingSide: isLeft,
                  )
                : fallbackTarget;
            _addFieldLine(lines, start, target,
                sl, ai, 1.0 * product.material.throwPowerFactor, refDist, distToProduct);
          }
        }

        // ── B) 윗면 방출: 양극 상단 → 제품 윗면 (대칭) ──────────
        if (anodeYTop < sl) {
          for (int xi = 0; xi < mediumN; xi++) {
            for (int zi = 0; zi < mediumN; zi++) {
              final xFrac = (xi + 0.5) / mediumN;
              final zFrac = (zi + 0.5) / mediumN;
              final startX = anodeCenter.x + (xFrac - 0.5) * anode.width;
              final startZ = anodeCenter.z + (zFrac - 0.5) * anode.length;
              final start = Vec3(startX, anodeYTop.clamp(0.0, sl), startZ);
              final fallbackTarget = Vec3(
                prodCX + mirrorSign * ((xFrac - 0.5) * prodHW),
                prodCY + prodHD,
                prodCZ + (zFrac - 0.5) * prodHL * 2,
              );
              final target = cadTargets.isNotEmpty
                  ? _closestCadTargetPoint(
                      product: product,
                      start: start,
                      preferFacingSide: isLeft,
                    )
                  : fallbackTarget;
              _addFieldLine(lines, start, target,
                  sl, ai, 1.02 * product.material.throwPowerFactor, refDist, distToProduct);
            }
          }
        }

        // ── C) 아랫면 방출: 양극 하단/측면 → 제품 바닥면 ─────────
        if (anodeYBot >= 0.0) {
          final bottomN = (mediumN + 1).clamp(4, 9);
          for (int xi = 0; xi < bottomN; xi++) {
            for (int zi = 0; zi < bottomN; zi++) {
              final xFrac = (xi + 0.5) / bottomN;
              final zFrac = (zi + 0.5) / bottomN;
              final startX = anodeCenter.x + (xFrac - 0.5) * anode.width;
              final startZ = anodeCenter.z + (zFrac - 0.5) * anode.length;
              final start = Vec3(startX, anodeYBot.clamp(0.0, sl), startZ);
              final fallbackTarget = Vec3(
                prodCX + mirrorSign * ((xFrac - 0.5) * prodHW),
                prodCY - prodHD,
                prodCZ + (zFrac - 0.5) * prodHL * 2,
              );
              final target = cadTargets.isNotEmpty
                  ? _closestCadTargetPoint(
                      product: product,
                      start: start,
                      preferFacingSide: isLeft,
                    )
                  : fallbackTarget;
              _addFieldLine(lines, start, target,
                  sl, ai, 1.18 * product.material.throwPowerFactor, refDist, distToProduct, bottomArc: true);
            }
          }
        }

        // ── D) 측면(Z) 방출: 양극 Z 끝 → 제품 Z 측면 (대칭) ───
        for (int yi = 0; yi < sideN; yi++) {
          final yFrac = (yi + 0.5) / sideN;
          final startY = (anodeYBot + yFrac * (anodeYTop - anodeYBot)).clamp(0.0, sl);
          if (startY > sl) continue;
          final prodY = (prodCY - prodHD + yFrac * prodHD * 2).clamp(0.0, sl);
          final prodX = prodCX + mirrorSign * (prodHW * 0.5);
          final startFrontUpper = Vec3(anodeCenter.x, startY, anodeCenter.z + anodeHL);
          final startFrontLower = Vec3(anodeCenter.x, startY, anodeCenter.z - anodeHL);
          final startMidUpper = Vec3(
            isLeft ? anodeCenter.x + anodeHW : anodeCenter.x - anodeHW,
            startY,
            anodeCenter.z + anodeHL * 0.55,
          );
          final startMidLower = Vec3(
            isLeft ? anodeCenter.x + anodeHW : anodeCenter.x - anodeHW,
            startY,
            anodeCenter.z - anodeHL * 0.55,
          );
          final targetUpper = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(product: product, start: startFrontUpper, preferFacingSide: isLeft)
              : Vec3(prodX, prodY, prodCZ + prodHL);
          final targetLower = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(product: product, start: startFrontLower, preferFacingSide: isLeft)
              : Vec3(prodX, prodY, prodCZ - prodHL);
          final targetMidUpper = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(product: product, start: startMidUpper, preferFacingSide: isLeft)
              : Vec3(prodCX + mirrorSign * (prodHW * 0.75), prodY, prodCZ + prodHL * 0.55);
          final targetMidLower = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(product: product, start: startMidLower, preferFacingSide: isLeft)
              : Vec3(prodCX + mirrorSign * (prodHW * 0.75), prodY, prodCZ - prodHL * 0.55);
          _addFieldLine(lines, startFrontUpper, targetUpper,
              sl, ai, 1.04 * product.material.throwPowerFactor, refDist, distToProduct);
          _addFieldLine(lines, startFrontLower, targetLower,
              sl, ai, 1.04 * product.material.throwPowerFactor, refDist, distToProduct);
          _addFieldLine(lines, startMidUpper, targetMidUpper,
              sl, ai, 0.98 * product.material.throwPowerFactor, refDist, distToProduct);
          _addFieldLine(lines, startMidLower, targetMidLower,
              sl, ai, 0.98 * product.material.throwPowerFactor, refDist, distToProduct);
        }

        // ── E) 우회선: 양극 → 제품 뒷면 (약한 throw power) ─────
        for (int yi = 0; yi < wrapN; yi++) {
          for (int zi = 0; zi < wrapN; zi++) {
            final yFrac = (yi + 0.5) / wrapN;
            final zFrac = (zi + 0.5) / wrapN;
            final startY = (anodeYBot + yFrac * (anodeYTop - anodeYBot)).clamp(0.0, sl);
            if (startY > sl) continue;
            final startX = isLeft ? anodeCenter.x + anodeHW : anodeCenter.x - anodeHW;
            final start = Vec3(startX, startY, anodeCenter.z + (zFrac - 0.5) * anode.length);
            final fallbackTarget = Vec3(
              isLeft ? prodCX + prodHW : prodCX - prodHW,
              (prodCY - prodHD + yFrac * prodHD * 2).clamp(0.0, sl),
              prodCZ + (zFrac - 0.5) * prodHL * 1.5,
            );
            final target = cadTargets.isNotEmpty
                ? _closestCadTargetPoint(
                    product: product,
                    start: start,
                    preferFacingSide: !isLeft,
                  )
                : fallbackTarget;
            _addFieldLine(lines, start, target,
                sl, ai, 0.86 * product.material.throwPowerFactor, refDist, distToProduct, wrap: true);
          }
        }

        final facingX = isLeft ? prodCX - prodHW : prodCX + prodHW;
        final rearX = isLeft ? prodCX + prodHW : prodCX - prodHW;
        for (final yFrac in const <double>[0.28, 0.72]) {
          final startY = (anodeYBot + yFrac * (anodeYTop - anodeYBot)).clamp(0.0, sl);
          if (startY > sl) continue;
          final startFront = Vec3(
            isLeft ? anodeCenter.x + anodeHW : anodeCenter.x - anodeHW,
            startY,
            anodeCenter.z,
          );
          final mappedY = (prodCY - prodHD + yFrac * prodHD * 2).clamp(0.0, sl);
          final facingTarget = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(
                  product: product,
                  start: startFront,
                  preferFacingSide: isLeft,
                )
              : Vec3(facingX, mappedY, prodCZ);
          final rearTarget = cadTargets.isNotEmpty
              ? _closestCadTargetPoint(
                  product: product,
                  start: startFront,
                  preferFacingSide: !isLeft,
                )
              : Vec3(rearX, mappedY, prodCZ);
          _addFieldLine(lines, startFront, facingTarget,
              sl, ai, 1.0 * product.material.throwPowerFactor, refDist, distToProduct);
          _addFieldLine(lines, startFront, rearTarget,
              sl, ai, 0.78 * product.material.throwPowerFactor, refDist, distToProduct, wrap: true);
        }
      }
    }
    return lines;
  }

  // 전기력선 하나 추가 (헬퍼)
  // 큐빅 베지어 (4점) 제어로 더 자연스러운 곡선 생성
  static void _addFieldLine(
    List<FieldLine> lines,
    Vec3 start,
    Vec3 target,
    double sl,
    int anodeIndex,
    double intensityMult,
    double refDist,
    double distToProduct, {
    bool wrap = false,
    bool bottomArc = false,
  }) {
    if (target.y > sl) return;

    final dir = (target - start);
    final dist = dir.length;
    if (dist < 0.5) return;

    final horizontal = Vec3(dir.x, 0, dir.z);
    final horizontalLen = horizontal.length;
    final horizontalNorm = horizontalLen > 0.0001
        ? horizontal / horizontalLen
        : const Vec3(1, 0, 0);
    final sideNormal = Vec3(-horizontalNorm.z, 0, horizontalNorm.x).normalized();
    final verticalBias = (target.y - start.y) / dist;
    final xBias = (target.x - start.x) / dist;
    final zBias = (target.z - start.z) / dist;
    final lateralCurve = (xBias.abs() * 0.55 + zBias.abs() * 0.30).clamp(0.12, 0.72);
    final midY = (start.y + target.y) * 0.5;
    final sideBendSign = ((start.z + target.z) >= 0 ? 1.0 : -1.0) *
        (start.x <= target.x ? 1.0 : -1.0);
    final sideBend = sideNormal * (dist * (0.05 + lateralCurve * 0.12) * sideBendSign);

    Vec3 cp1;
    Vec3 cp2;
    Vec3 cp3;
    Vec3 cp4;

    if (wrap) {
      final lift = (dist * (0.28 + lateralCurve * 0.24)).clamp(5.0, dist * 0.82);
      final sideShift = horizontalLen * 0.16;
      cp1 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.18 + sideBend.x * 0.35,
        (start.y + lift * 0.28).clamp(0.0, sl),
        start.z + horizontalNorm.z * (horizontalLen * 0.10 + sideShift) + sideBend.z * 0.35,
      );
      cp2 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.42 + sideBend.x * 0.90,
        (midY + lift * 0.72).clamp(0.0, sl),
        start.z + horizontalNorm.z * (horizontalLen * 0.42 + sideShift) + sideBend.z * 0.90,
      );
      cp3 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.38 + sideBend.x * 0.60,
        (midY + lift * 0.58).clamp(0.0, sl),
        target.z - horizontalNorm.z * (horizontalLen * 0.18 - sideShift * 0.35) + sideBend.z * 0.60,
      );
      cp4 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.16 + sideBend.x * 0.18,
        (target.y + lift * 0.10).clamp(0.0, sl),
        target.z - horizontalNorm.z * horizontalLen * 0.08 + sideBend.z * 0.18,
      );
    } else if (bottomArc) {
      final dip = (dist * (0.10 + lateralCurve * 0.12)).clamp(2.0, dist * 0.28);
      cp1 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.16 + sideBend.x * 0.20,
        (start.y - dip * 0.55).clamp(0.0, sl),
        start.z + horizontalNorm.z * horizontalLen * 0.12 + sideBend.z * 0.20,
      );
      cp2 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.40 + sideBend.x * 0.62,
        (midY - dip).clamp(0.0, sl),
        start.z + horizontalNorm.z * horizontalLen * 0.34 + sideBend.z * 0.62,
      );
      cp3 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.28 + sideBend.x * 0.35,
        (target.y - dip * 0.28).clamp(0.0, sl),
        target.z - horizontalNorm.z * horizontalLen * 0.22 + sideBend.z * 0.35,
      );
      cp4 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.10 + sideBend.x * 0.10,
        (target.y + dip * 0.06).clamp(0.0, sl),
        target.z - horizontalNorm.z * horizontalLen * 0.08 + sideBend.z * 0.10,
      );
    } else {
      final arch = (dist * (0.12 + lateralCurve * 0.18 + verticalBias.abs() * 0.12))
          .clamp(2.2, dist * 0.36);
      cp1 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.16 + sideBend.x * 0.28,
        (start.y + arch * 0.30 + dir.y * 0.08).clamp(0.0, sl),
        start.z + horizontalNorm.z * horizontalLen * 0.14 + sideBend.z * 0.28,
      );
      cp2 = Vec3(
        start.x + horizontalNorm.x * horizontalLen * 0.38 + sideBend.x * 0.82,
        (midY + arch).clamp(0.0, sl),
        start.z + horizontalNorm.z * horizontalLen * 0.34 + sideBend.z * 0.82,
      );
      cp3 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.26 + sideBend.x * 0.52,
        (midY + arch * 0.72 - dir.y * 0.05).clamp(0.0, sl),
        target.z - horizontalNorm.z * horizontalLen * 0.22 + sideBend.z * 0.52,
      );
      cp4 = Vec3(
        target.x - horizontalNorm.x * horizontalLen * 0.10 + sideBend.x * 0.14,
        (target.y + arch * 0.10).clamp(0.0, sl),
        target.z - horizontalNorm.z * horizontalLen * 0.08 + sideBend.z * 0.14,
      );
    }

    final steps = (72 + dist / 1.2).round().clamp(72, 144);
    final pts = <Vec3>[];
    for (int s = 0; s <= steps; s++) {
      final t = s / steps;
      final pt = _quinticBezier(start, cp1, cp2, cp3, cp4, target, t);
      if (pt.y > sl + 1.0) break;
      if (pt.y < -0.5) break;
      pts.add(pt);
    }

    if (pts.length >= 4) {
      final baseIntensity =
          (1.0 / (1.0 + dist / 60.0)).clamp(0.05, 1.0);
      final distFactor = math.exp(-distToProduct / (refDist * 3.0)).clamp(0.1, 1.0);
      final intensity =
          (baseIntensity * distFactor * intensityMult).clamp(0.05, 1.0);
      lines.add(FieldLine(
        points: pts,
        intensity: intensity,
        anodeIndex: anodeIndex,
      ));
    }
  }

  // 5차 베지어 (P0, CP1, CP2, CP3, CP4, P1)
  static Vec3 _quinticBezier(
    Vec3 p0,
    Vec3 cp1,
    Vec3 cp2,
    Vec3 cp3,
    Vec3 cp4,
    Vec3 p1,
    double t,
  ) {
    final mt = 1 - t;
    final mt2 = mt * mt;
    final mt3 = mt2 * mt;
    final mt4 = mt3 * mt;
    final mt5 = mt4 * mt;
    final t2 = t * t;
    final t3 = t2 * t;
    final t4 = t3 * t;
    final t5 = t4 * t;
    return p0 * mt5 +
        cp1 * (5 * mt4 * t) +
        cp2 * (10 * mt3 * t2) +
        cp3 * (10 * mt2 * t3) +
        cp4 * (5 * mt * t4) +
        p1 * t5;
  }


  // ----------------------------------------------------------
  // 표면 샘플 포인트 생성
  // ----------------------------------------------------------
  static List<(Vec3, Vec3)> getProductSurfacePoints({
    required ProductSettings product,
    required int resolution,
  }) {
    if (product.cadImport.isImported && product.cadImport.triangles.isNotEmpty) {
      final cadPoints = _cadSurfacePoints(product, resolution);
      if (cadPoints.isNotEmpty) {
        return cadPoints;
      }
    }
    if (product.useLegoMode && product.legoPieces.isNotEmpty) {
      return _legoSurfacePoints(product, resolution);
    }
    final cx = product.posX;
    final cy = product.posY + product.depth / 2;
    final cz = product.posZ;
    final hw = product.width / 2;
    final hd = product.depth / 2;
    final hl = product.length / 2;
    final wt = product.wallThickness;

    switch (product.shape) {
      case ProductShape.box:
        return _boxSurface(cx, cy, cz, hw, hd, hl, resolution);
      case ProductShape.cylinder:
        return _cylinderSurface(cx, cy, cz, hw, hd, resolution);
      case ProductShape.dish:
        return _dishSurface(cx, cy, cz, hw, hd * 0.25, hl, resolution);
      case ProductShape.hollowBox:
        return _hollowBoxSurface(cx, cy, cz, hw, hd, hl, wt, resolution);
      case ProductShape.lShape:
        return _lShapeSurface(cx, cy, cz, hw, hd, hl, resolution);
      case ProductShape.pipe:
        return _pipeSurface(cx, cy, cz, hw, hd, wt, resolution);
      case ProductShape.bracket:
        return _bracketSurface(cx, cy, cz, hw, hd, hl, resolution);
      case ProductShape.steppedBox:
        return _steppedBoxSurface(cx, cy, cz, hw, hd, hl, resolution);
    }
  }

  static List<(Vec3, Vec3)> _cadSurfacePoints(ProductSettings product, int resolution) {
    final tris = product.cadImport.triangles;
    if (tris.isEmpty) return const [];

    final center = Vec3(product.posX, product.posY + product.depth / 2, product.posZ);
    final totalTriangles = tris.length;
    final targetSamples = (resolution * resolution * 6).clamp(180, 1800);
    final stride = totalTriangles > targetSamples ? (totalTriangles / targetSamples).ceil() : 1;
    final points = <(Vec3, Vec3)>[];

    for (int i = 0; i < totalTriangles; i += stride) {
      final tri = tris[i];
      final a = center + tri.a;
      final b = center + tri.b;
      final c = center + tri.c;
      final normal = tri.normal.lengthSq < 1e-8
          ? (b - a).cross(c - a).normalized()
          : tri.normal.normalized();
      if (normal.lengthSq < 1e-8) continue;

      final centroid = (a + b + c) / 3.0;
      points.add((centroid, normal));

      if (resolution >= 14) {
        points.add((((a + b) / 2.0), normal));
        points.add((((b + c) / 2.0), normal));
        points.add((((c + a) / 2.0), normal));
      }
    }

    return points;
  }

  static List<Vec3> _cadTargetPoints(ProductSettings product) {
    final tris = product.cadImport.triangles;
    if (tris.isEmpty) return const [];

    final center = Vec3(product.posX, product.posY + product.depth / 2, product.posZ);
    final points = <Vec3>[];
    final stride = tris.length > 240 ? (tris.length / 240).ceil() : 1;
    for (int i = 0; i < tris.length; i += stride) {
      final tri = tris[i];
      final a = center + tri.a;
      final b = center + tri.b;
      final c = center + tri.c;
      points.add((a + b + c) / 3.0);
    }
    return points;
  }

  static Vec3 _closestCadTargetPoint({
    required ProductSettings product,
    required Vec3 start,
    required bool preferFacingSide,
  }) {
    final candidates = _cadTargetPoints(product);
    if (candidates.isEmpty) {
      final prodCX = product.posX;
      final prodCY = product.posY + product.depth / 2;
      final prodCZ = product.posZ;
      final prodHW = product.width / 2;
      return Vec3(
        preferFacingSide ? prodCX - prodHW : prodCX + prodHW,
        prodCY,
        prodCZ,
      );
    }

    Vec3 best = candidates.first;
    double bestScore = double.infinity;
    for (final candidate in candidates) {
      final dxPenalty = preferFacingSide
          ? math.max(0.0, candidate.x - product.posX) * 0.75
          : math.max(0.0, product.posX - candidate.x) * 0.75;
      final score = (candidate - start).length + dxPenalty;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  static List<(Vec3, Vec3)> _legoSurfacePoints(
      ProductSettings product, int resolution) {
    final pts = <(Vec3, Vec3)>[];
    final baseCX = product.posX;
    final baseCY = product.posY + product.depth / 2;
    final baseCZ = product.posZ;
    for (final piece in product.legoPieces) {
      final cx = baseCX + piece.offsetX;
      final cy = baseCY + piece.offsetY;
      final cz = baseCZ + piece.offsetZ;
      final r = resolution ~/ 2 + 2;
      switch (piece.shape) {
        case LegoPieceShape.box:
          pts.addAll(_boxSurface(
              cx, cy, cz, piece.width / 2, piece.height / 2, piece.length / 2, r));
          break;
        case LegoPieceShape.cylinder:
          pts.addAll(
              _cylinderSurface(cx, cy, cz, piece.width / 2, piece.height / 2, r));
          break;
        case LegoPieceShape.sphere:
          pts.addAll(_sphereSurface(cx, cy, cz, piece.width / 2, r));
          break;
      }
    }
    return pts;
  }

  static List<(Vec3, Vec3)> _boxSurface(
      double cx, double cy, double cz,
      double hw, double hd, double hl, int n) {
    final pts = <(Vec3, Vec3)>[];
    for (int a = 0; a < n; a++) {
      for (int b = 0; b < n; b++) {
        final u = (a + 0.5) / n;
        final v = (b + 0.5) / n;
        pts.add((Vec3(cx + hw, cy + (v - .5) * 2 * hd, cz + (u - .5) * 2 * hl),
            const Vec3(1, 0, 0)));
        pts.add((Vec3(cx - hw, cy + (v - .5) * 2 * hd, cz + (u - .5) * 2 * hl),
            const Vec3(-1, 0, 0)));
        pts.add((Vec3(cx + (u - .5) * 2 * hw, cy + hd, cz + (v - .5) * 2 * hl),
            const Vec3(0, 1, 0)));
        pts.add((Vec3(cx + (u - .5) * 2 * hw, cy - hd, cz + (v - .5) * 2 * hl),
            const Vec3(0, -1, 0)));
        pts.add((Vec3(cx + (u - .5) * 2 * hw, cy + (v - .5) * 2 * hd, cz + hl),
            const Vec3(0, 0, 1)));
        pts.add((Vec3(cx + (u - .5) * 2 * hw, cy + (v - .5) * 2 * hd, cz - hl),
            const Vec3(0, 0, -1)));
      }
    }
    return pts;
  }

  static List<(Vec3, Vec3)> _cylinderSurface(
      double cx, double cy, double cz, double r, double hd, int n) {
    final pts = <(Vec3, Vec3)>[];
    final aSteps = n * 4;
    final hSteps = n;
    for (int ai = 0; ai < aSteps; ai++) {
      for (int hi = 0; hi < hSteps; hi++) {
        final angle = (ai + 0.5) / aSteps * 2 * math.pi;
        final yFrac = (hi + 0.5) / hSteps;
        pts.add((
          Vec3(cx + r * math.cos(angle), cy - hd + yFrac * 2 * hd,
              cz + r * math.sin(angle)),
          Vec3(math.cos(angle), 0, math.sin(angle)),
        ));
      }
    }
    for (int ai = 0; ai < aSteps; ai++) {
      for (int ri = 0; ri < n; ri++) {
        final angle = (ai + 0.5) / aSteps * 2 * math.pi;
        final pr = r * (ri + 0.5) / n;
        pts.add((Vec3(cx + pr * math.cos(angle), cy + hd, cz + pr * math.sin(angle)),
            const Vec3(0, 1, 0)));
        pts.add((Vec3(cx + pr * math.cos(angle), cy - hd, cz + pr * math.sin(angle)),
            const Vec3(0, -1, 0)));
      }
    }
    return pts;
  }

  static List<(Vec3, Vec3)> _dishSurface(
      double cx, double cy, double cz,
      double r, double hd, double depth, int n) {
    final pts = <(Vec3, Vec3)>[];
    final aSteps = n * 4;
    for (int ai = 0; ai < aSteps; ai++) {
      final angle = (ai + 0.5) / aSteps * 2 * math.pi;
      pts.add((Vec3(cx + r * math.cos(angle), cy, cz + r * math.sin(angle)),
          Vec3(math.cos(angle), 0, math.sin(angle))));
    }
    for (int ai = 0; ai < aSteps; ai++) {
      for (int ri = 0; ri < n; ri++) {
        final angle = (ai + 0.5) / aSteps * 2 * math.pi;
        final rFrac = (ri + 0.5) / n;
        final pr = r * rFrac;
        final dip = hd * rFrac * rFrac;
        pts.add((
          Vec3(cx + pr * math.cos(angle), cy + hd - dip,
              cz + pr * math.sin(angle)),
          Vec3(-math.cos(angle) * 0.2, 1, -math.sin(angle) * 0.2),
        ));
      }
    }
    return pts;
  }

  static List<(Vec3, Vec3)> _hollowBoxSurface(
      double cx, double cy, double cz,
      double hw, double hd, double hl, double wt, int n) {
    final outer = _boxSurface(cx, cy, cz, hw, hd, hl, n);
    final inner = _boxSurface(cx, cy, cz, (hw - wt).clamp(0.1, hw),
            (hd - wt).clamp(0.1, hd), (hl - wt).clamp(0.1, hl), n)
        .map((p) => (p.$1, -p.$2))
        .toList();
    return [...outer, ...inner];
  }

  static List<(Vec3, Vec3)> _lShapeSurface(
      double cx, double cy, double cz,
      double hw, double hd, double hl, int n) {
    return [
      ..._boxSurface(cx - hw / 4, cy, cz, hw * 3 / 4, hd, hl, n),
      ..._boxSurface(cx + hw / 4, cy - hd / 4, cz, hw / 4, hd * 3 / 4, hl, n),
    ];
  }

  static List<(Vec3, Vec3)> _pipeSurface(
      double cx, double cy, double cz,
      double r, double hd, double wt, int n) {
    return [
      ..._cylinderSurface(cx, cy, cz, r, hd, n),
      ..._cylinderSurface(cx, cy, cz, (r - wt).clamp(0.1, r), hd, n)
          .map((p) => (p.$1, -p.$2)),
    ];
  }

  static List<(Vec3, Vec3)> _bracketSurface(
      double cx, double cy, double cz,
      double hw, double hd, double hl, int n) {
    return [
      ..._boxSurface(cx - hw * 0.15, cy, cz, hw * 0.85, hd, hl * 0.5, n),
      ..._boxSurface(cx + hw * 0.35, cy + hd * 0.15, cz + hl * 0.45,
          hw * 0.35, hd * 0.7, hl * 0.45, n),
      ..._cylinderSurface(cx + hw * 0.42, cy + hd * 0.15, cz + hl * 0.45,
          hw * 0.22, hd * 0.35, (n / 2).round().clamp(4, 12)),
    ];
  }

  static List<(Vec3, Vec3)> _steppedBoxSurface(
      double cx, double cy, double cz,
      double hw, double hd, double hl, int n) {
    return [
      ..._boxSurface(cx, cy - hd * 0.12, cz, hw, hd * 0.88, hl, n),
      ..._boxSurface(cx + hw * 0.12, cy + hd * 0.38, cz + hl * 0.1,
          hw * 0.72, hd * 0.35, hl * 0.72, (n / 1.5).round().clamp(4, 16)),
    ];
  }

  static List<(Vec3, Vec3)> _sphereSurface(
      double cx, double cy, double cz, double r, int n) {
    final pts = <(Vec3, Vec3)>[];
    final phiSteps = n * 3;
    final thetaSteps = n * 4;
    for (int pi2 = 0; pi2 < phiSteps; pi2++) {
      for (int ti = 0; ti < thetaSteps; ti++) {
        final phi = (pi2 + 0.5) / phiSteps * math.pi;
        final theta = (ti + 0.5) / thetaSteps * 2 * math.pi;
        final nx = math.sin(phi) * math.cos(theta);
        final ny = math.cos(phi);
        final nz = math.sin(phi) * math.sin(theta);
        pts.add((Vec3(cx + r * nx, cy + r * ny, cz + r * nz), Vec3(nx, ny, nz)));
      }
    }
    return pts;
  }

  // ----------------------------------------------------------
  // 도금 두께 계산 (v7: 전류 보존, 도그본 보정)
  // ----------------------------------------------------------
  static List<ThicknessPoint> computeThickness({
    required TankSettings tank,
    required AnodeSettings anode,
    required ProductSettings product,
    required ElectricalSettings elec,
    required List<MaskingZone> maskingZones,
    required int gridResolution,
  }) =>
      computeThicknessMulti(
        tank: tank,
        anode: anode,
        products: [product],
        elec: elec,
        maskingZones: maskingZones,
        gridResolution: gridResolution,
      );

  static List<ThicknessPoint> computeThicknessMulti({
    required TankSettings tank,
    required AnodeSettings anode,
    required List<ProductSettings> products,
    required ElectricalSettings elec,
    required List<MaskingZone> maskingZones,
    required int gridResolution,
  }) {
    if (products.isEmpty) return [];

    final results = <ThicknessPoint>[];
    final pt = elec.platingType;
    final sl = tank.solutionLevel;
    final conductivity = pt.electrolyteConductivity;

    final anodePosList = getAnodePositionsMulti(
      tank: tank, anode: anode, products: products,
    );

    final timeSec = elec.platingTime * 60.0;
    final atomicWeight = pt.atomicWeight;
    final valence = pt.valence.toDouble();
    final density = pt.density;
    final efficiency = pt.currentEfficiency / 100.0;

    // ── 1차 패스: 가중치 수집 ───────────────────────────────
    final allPts = <_SurfPt>[];

    for (final product in products) {
      final surfPts = getProductSurfacePoints(
          product: product, resolution: gridResolution);

      for (final (pos, normal) in surfPts) {
        final inSol = _inSolution(pos, sl);

        // 마스킹
        final relX = product.width > 0
            ? (pos.x - (product.posX - product.width / 2)) / product.width
            : 0.5;
        final relY =
            product.depth > 0 ? (pos.y - product.posY) / product.depth : 0.5;
        final relZ = product.length > 0
            ? (pos.z - (product.posZ - product.length / 2)) / product.length
            : 0.5;
        final masked = maskingZones.any((m) => m.contains(relX, relY, relZ));

        if (!inSol || masked) {
          allPts.add(_SurfPt(
            pos: pos, normal: normal,
            weight: 0.0,
            inSolution: inSol, isMasked: masked,
            productId: product.id, product: product,
          ));
          continue;
        }

        // ── 각 양극에서의 기여 합산 ──────────────────────────
        // 모든 면에 두께가 형성되도록 직접 노출/우회/측면 확산 성분을 동시에 반영
        final materialConductivity = product.material.conductivityFactor;
        final materialThrowPower = product.material.throwPowerFactor;
        final materialShielding = product.material.shieldingFactor;

        double totalDirWeight = 0.0;
        double frontExposure = 0.0;
        double wrapExposure = 0.0;
        double sideSweep = 0.0;
        double positionCoupling = 0.0;
        double dominantAnodeInfluence = 0.0;
        double nearestAnodeDistance = double.infinity;
        // 양극은 실제로 "세로로 긴 막대"(높이=depth, 길이=length)이지만
        // anodePosList 는 중심점만 제공한다. 따라서 키 큰 제품의 윗면이
        // 양극보다 한참 위라고 잘못 계산되어 윗면이 과도하게 얇아졌다.
        // → 양극의 Y(높이)/Z(길이) 연장을 고려해 "막대 위 최근접점"까지의
        //   거리를 사용한다. (물리적으로 정확: 긴 양극은 윗면도 커버)
        final anodeHalfY = anode.depth / 2;
        final anodeHalfZ = anode.length / 2;
        for (final (anodeCenter, _) in anodePosList) {
          // 양극 막대 위에서 현재 표면점에 가장 가까운 점(클램프)
          final nearOnAnode = Vec3(
            anodeCenter.x,
            (pos.y).clamp(anodeCenter.y - anodeHalfY, anodeCenter.y + anodeHalfY),
            (pos.z).clamp(anodeCenter.z - anodeHalfZ, anodeCenter.z + anodeHalfZ),
          );
          final fromAnodeVec = pos - nearOnAnode;
          final fromAnode = fromAnodeVec.normalized();
          final alignment = -fromAnode.dot(normal); // 양극 향하는 면이 양수
          final dist = fromAnodeVec.length.clamp(0.5, 10000.0);
          nearestAnodeDistance = math.min(nearestAnodeDistance, dist);
          final distRatio = dist / (anode.distFromProduct.clamp(5.0, 1000.0));
          final invDist = 1.0 / math.pow(dist, 1.72).toDouble();

          final reverseTerm = math.max(0.0, -alignment);
          final lateralOffset = product.width > 0
              ? ((pos.x - anodeCenter.x).abs() / (product.width / 2 + anode.width / 2 + 0.001)).clamp(0.0, 2.5)
              : 1.0;
          final longitudinalOffset = product.length > 0
              ? ((pos.z - anodeCenter.z).abs() / (product.length / 2 + anode.length / 2 + 0.001)).clamp(0.0, 2.5)
              : 1.0;
          final verticalOffset = product.depth > 0
              ? ((pos.y - anodeCenter.y).abs() / (product.depth / 2 + anode.depth / 2 + 0.001)).clamp(0.0, 2.5)
              : 1.0;
          final alignmentWindow = math.exp(-(lateralOffset * lateralOffset) * 1.20) *
              math.exp(-(longitudinalOffset * longitudinalOffset) * 0.60);
          final verticalWindow = math.exp(-(verticalOffset * verticalOffset) * 0.70);
          final sizeCoverage =
              (math.min(anode.length, product.length) /
                      math.max(anode.length, product.length).clamp(0.001, double.infinity)) *
                  0.55 +
              (math.min(anode.depth, product.depth) /
                      math.max(anode.depth, product.depth).clamp(0.001, double.infinity)) *
                  0.45;
          final anodeFacingArea = (anode.depth * anode.length).clamp(1.0, double.infinity);
          final productFacingArea = (product.depth * product.length).clamp(1.0, double.infinity);
          final anodeAreaRatio = (anodeFacingArea / productFacingArea).clamp(0.35, 8.0);
          final anodeAreaBoost = 0.78 + math.pow(anodeAreaRatio, 0.34).toDouble();
          final positionWindow =
              (0.18 + alignmentWindow * 0.62 + verticalWindow * 0.20) * (0.65 + sizeCoverage * 0.35) * anodeAreaBoost;
          final distanceFocus = 1.0 / (1.0 + math.pow(math.max(0.0, distRatio - 1.0), 1.35));

          // ══════════════════════════════════════════════════════════
          // ■ v11 — 통일된 면별 기여 공식 (사용자 물리 법칙 정합)
          //
          // 사용자 정의 물리:
          //  (1) 거리가 짧을수록 두껍다 (거리 = 최우선 지배 인자) → invDist
          //  (2) 양극을 "정면으로" 바라보는 면이 가장 두껍다 → directTerm(=alignment)
          //  (3) 정면이 아니어도 가까우면 두껍다(단, 정면보다 낮게)
          //      → 모든 노출면에 거리 기반 기본 노출(baseExposure) 부여
          //  (4) 멀어지면 끝단이라도 얇다 → invDist 가 전체를 지배
          //
          // [설계] 한 점의 단일 양극 기여 =
          //    (정면성 보너스 + 기본 노출) × invDist × 정렬/근접 보정
          //  - 정면성 보너스: directTerm (양극 정면일수록 큼) → "정면이 최대"
          //  - 기본 노출:     모든 외부 노출면에 부여(윗면·측면·하면 공통)
          //                   → "정면 아니어도 가까우면 두껍게" (정면보다는 낮음)
          //  - 윗면/측면을 차별하지 않음 → 윗면만 빨갛고 측면이 파란 문제 해결
          // ══════════════════════════════════════════════════════════

          // 양극 정면성: 면 법선이 양극을 향할수록 1.0 (정면), 측면 0, 뒷면 음수
          final facing = math.max(0.0, alignment);            // 0~1 (정면=1)
          final sideOpen = (1.0 - alignment.abs()).clamp(0.0, 1.0); // 측면 노출

          // 기본 노출(모든 외부 노출면 공통) — 정면이 아니어도 가까우면 도금됨.
          //   윗면/하면/측면 구분 없이 동일 부여 → 면 균형 확보.
          const baseExposure = 0.55;
          // 정면성 보너스 — 양극을 정면으로 볼수록 추가(정면이 최대 두께).
          final facingBonus = facing * 1.85;
          // 측면 개방 보너스(정면 아니지만 노출된 측면) — 정면보다 작게.
          final sideBonus = sideOpen * 0.45;
          // 뒷면(양극 반대) — 우회 전류만, 재질 throwing power 의존.
          final wrapBonus = reverseTerm * (0.12 + conductivity * 0.12) *
              (0.6 + materialThrowPower.clamp(0.0, 2.0) * 0.4);

          final faceTerm = baseExposure + facingBonus + sideBonus + wrapBonus;

          // 정렬/근접 보정: 양극 정면 정렬(positionWindow)이 좋을수록 약간 가산.
          //   단, 기본 노출이 있으므로 정렬 안 맞아도 0 이 되지 않음.
          final alignBoost = 0.65 + positionWindow * 0.55;

          // 노출 인자 누적(면별 분포 진단/시각화용 — exposureFactor 에 사용)
          frontExposure += facing * invDist;
          sideSweep += sideOpen * invDist;
          wrapExposure += wrapBonus * invDist;
          positionCoupling += positionWindow * distanceFocus * invDist;

          // 단일 양극 기여: 면노출 × 거리(invDist) × 정렬보정 × 거리집중
          final weightedContribution =
              faceTerm * invDist * alignBoost * distanceFocus * 1750.0;
          dominantAnodeInfluence = math.max(dominantAnodeInfluence, weightedContribution);
          totalDirWeight += weightedContribution;
        }

        // 도그본, 깊이, 차폐
        final dogbone = _dogboneEffect(pos, normal, product);
        final depthFactor = _solutionDepthFactor(pos, sl);
        final shadow = _computeShadowFactor(pos, normal, products, product);

        final normalizedX = product.width > 0
            ? ((pos.x - product.posX).abs() / (product.width / 2)).clamp(0.0, 1.0)
            : 0.0;
        final normalizedY = product.depth > 0
            ? ((pos.y - (product.posY + product.depth / 2)).abs() / (product.depth / 2)).clamp(0.0, 1.0)
            : 0.0;
        final normalizedZ = product.length > 0
            ? ((pos.z - product.posZ).abs() / (product.length / 2)).clamp(0.0, 1.0)
            : 0.0;
        final edgeBlend = (normalizedX * 0.55 + normalizedY * 0.75 + normalizedZ * 0.60)
            .clamp(0.0, 1.2);
        // v10: 측면 모서리 단일점이 폭증해 면 전체(특히 윗면)를 굶기던 문제로
        //   에지 부스트를 완화(0.65→0.35).
        final curvatureBoost = 1.0 + math.pow(edgeBlend, 2.2).toDouble() * 0.35;

        final cavityPenalty = () {
          switch (product.shape) {
            case ProductShape.hollowBox:
            case ProductShape.pipe:
              return normal.dot(Vec3(0, 0, -1)).abs() > 0.4 ? 0.86 : 0.94;
            case ProductShape.bracket:
              return pos.z > product.posZ ? 0.90 : 1.0;
            case ProductShape.steppedBox:
              return pos.y > product.posY + product.depth * 0.55 ? 0.92 : 1.0;
            default:
              return 1.0;
          }
        }();

        final farSidePenalty = () {
          if (anodePosList.isEmpty) return 1.0;
          final leftAnodeX = anodePosList.map((e) => e.$1.x).reduce(math.min);
          final rightAnodeX = anodePosList.map((e) => e.$1.x).reduce(math.max);
          final leftDist = (pos.x - leftAnodeX).abs();
          final rightDist = (rightAnodeX - pos.x).abs();
          final imbalance = ((leftDist - rightDist).abs() /
                  (math.max(leftDist, rightDist) + 0.001))
              .clamp(0.0, 1.0);
          return 1.0 - imbalance * 0.04;
        }();

        final normalizedNearestDistance = nearestAnodeDistance.isFinite
            ? (nearestAnodeDistance / (anode.distFromProduct.clamp(5.0, 1000.0))).clamp(0.45, 4.0)
            : 4.0;
        final proximityBoost = 1.0 + math.max(0.0, 1.25 - normalizedNearestDistance) * 0.85;
        final positionBoost = 0.55 + positionCoupling * 2.6;
        // v10: 측면 hotspot 단일점 과집중을 완화(0.72→0.88, 비중 2.6→1.4)
        //   → 가까운 제품의 전류가 한 측면 모서리에만 쏠려 윗면이 굶지 않도록.
        final dominantFocus = 0.88 + dominantAnodeInfluence / (totalDirWeight + 1.0) * 0.55;
        final anodeFacingArea = (anode.depth * anode.length).clamp(1.0, double.infinity);
        final productFacingArea = (product.depth * product.length).clamp(1.0, double.infinity);
        final anodeAreaRatio = (anodeFacingArea / productFacingArea).clamp(0.35, 8.0);
        final areaScale = 0.76 + math.pow(anodeAreaRatio, 0.42).toDouble();

        // ──────────────────────────────────────────────────────────
        // ■ 거리 지배 인자 (Distance Dominance) — v8 물리 정합성 강화
        //
        // 핵심: "양극에서 멀어질수록 도금 두께는 반드시 얇아진다"는
        //       물리 법칙이 어떤 설정/형상에서도 깨지지 않도록,
        //       최근접 양극까지의 실제 거리에 단조 감소하는 게이트를
        //       두께 가중치 전체에 곱한다.
        //
        // - nearestAnodeDistance(절대거리 cm)를 기준으로 1/r^p 형태로
        //   강하게 감쇠 → 면별 노출/면적 보정이 거리 손실을 역전시키지 못함
        // - refDistForDominance: 양극-제품 기준 거리. 이보다 멀면 급감.
        // ──────────────────────────────────────────────────────────
        final refDistForDominance = anode.distFromProduct.clamp(5.0, 1000.0);
        final absNearest = nearestAnodeDistance.isFinite
            ? nearestAnodeDistance.clamp(1.0, 100000.0)
            : refDistForDominance * 4.0;
        // 정규화 거리: 1.0 = 기준 양극거리. >1 이면 기준보다 멀다.
        final distRatioAbs = absNearest / refDistForDominance;
        // 거리 감쇠: 1/r^1.6 (전기장 1/r 와 전류밀도 집중의 절충).
        //  기준거리(1.0)=1.0, 2배=~0.33, 3배=~0.17, 4배=~0.11.
        //  단조 감소를 보장하면서, 먼 곳에도 최소 throwing power 잔류량 유지.
        //  throwPower 가 큰 재질일수록 먼 곳 잔류 두께가 약간 더 남도록 보정.
        final decayExp = (1.62 - (materialThrowPower - 1.0) * 0.18).clamp(1.35, 1.85);
        final distanceDominance =
            (1.0 / math.pow(distRatioAbs.clamp(0.35, 14.0), decayExp).toDouble())
                .clamp(0.004, 3.0);

        // v11: 면별 균형은 이미 faceTerm(통일 공식)에서 처리되므로,
        //   여기서는 재질 throwing power 에 의한 "우회 도금" 잔여 보정만
        //   가볍게 적용한다(이중 증폭 방지). 측면 확산은 약하게 가산.
        final exposureFactor = (1.0 +
                wrapExposure * (0.45 + materialThrowPower * 0.20) +
                sideSweep * 0.30 +
                frontExposure * 0.20)
            .clamp(1.0, 2.6);

        // ──────────────────────────────────────────────────────────
        // ■ 모서리(에지) 효과의 거리 종속화 — v8.1
        //
        // dogbone / curvatureBoost 는 모서리에 전류가 집중되는 에지 효과로,
        // 가까운 제품에서는 실제로 관찰되지만, "양극에서 가장 먼 제품의
        // 모서리"가 가까운 제품의 면보다 두꺼워지는 것은 비물리적이다.
        //
        // → 모서리 부스트의 "초과분(1.0 이상)"을 distanceDominance 로 감쇠시킨다.
        //   가까운 점(dominance≈1): 에지 효과 거의 그대로 유지
        //   먼 점(dominance≪1):     에지 효과가 거리 감쇠 비율만큼 약화
        // ──────────────────────────────────────────────────────────
        final edgeGate = distanceDominance.clamp(0.0, 1.0);
        final dogboneScaled = 1.0 + (dogbone - 1.0) * edgeGate;
        final curvatureScaled = 1.0 + (curvatureBoost - 1.0) * edgeGate;

        // 거리와 결합되지 않은 "형상/재질" 계열 보정
        // (모서리 계열은 거리 게이트가 적용된 *Scaled 값을 사용)
        final shapeMaterialFactor = dogboneScaled *
            depthFactor *
            shadow *
            materialConductivity *
            materialThrowPower *
            materialShielding *
            curvatureScaled *
            cavityPenalty *
            farSidePenalty *
            areaScale;

        // ──────────────────────────────────────────────────────────
        // ■ v9 — 위치/근접 보정의 거리 종속화
        //
        // positionBoost / proximityBoost 는 "양극과의 정렬·근접"에 따른
        // 보정이지만, 먼 제품이라도 Z(길이)방향 정렬이 좋으면 값이 커져
        // 거리지배 게이트를 우회할 위험이 있다.
        // → 1.0 을 초과하는 부분(보너스)만 distanceDominance(=edgeGate)로
        //   감쇠시켜, 멀어질수록 정렬 보너스도 함께 사라지게 한다.
        // ──────────────────────────────────────────────────────────
        final positionBoostGated = 1.0 + (positionBoost - 1.0) * edgeGate;
        final proximityBoostGated = 1.0 + (proximityBoost - 1.0) * edgeGate;

        // 거리 의존 코어: 직접 전류 가중치 × 근접/위치 보정(거리종속) × 지배도
        final distanceCore =
            totalDirWeight * proximityBoostGated * positionBoostGated * dominantFocus;

        // ──────────────────────────────────────────────────────────
        // ■ v10 — 면 방향(faceBias) 처리 정정
        //
        // [v9 의 과오] faceBias 의 초과분을 edgeGate(거리)로 또 감쇠시키는 바람에,
        //   "양극에 가까운 제품의 윗면"까지 두께가 과도하게 눌려 파랗게(얇게)
        //   표현되었다. (사용자 지적: 가까운 윗면=빨강이어야 하는데 파랑)
        //
        // [정정 원칙] 거리 단조성은 distanceDominance "하나"로만 보장한다.
        //   faceBias 는 한 제품 내부의 "면별 상대 분포"(상/하/측면 균형)를
        //   결정하는 자연스러운 요소이므로 거리로 추가 감쇠하지 않는다.
        //   → 가까운 제품: 윗면·측면 모두 두껍게(빨강)
        //   → 먼 제품:    distanceDominance 가 전체를 균등 감쇠 → 얇게(파랑)
        // ──────────────────────────────────────────────────────────
        final faceBias = () {
          if (normal.y < -0.35) return 1.30; // 하면
          if (normal.y > 0.35) return 1.40;  // 상면
          if (normal.z.abs() > 0.35) return 1.42; // 길이방향 측면
          if (normal.x.abs() > 0.35) return 1.15; // 폭방향 측면
          return 1.0;
        }();

        // 최종 가중치:
        //  거리 단조성 = distanceDominance(전체에 곱) 하나로 보장.
        //  faceBias 는 면별 분포만 결정(거리 감쇠 없음).
        final weight = (distanceCore *
                shapeMaterialFactor *
                exposureFactor *
                faceBias *
                distanceDominance)
            .clamp(0.0, double.infinity);

        allPts.add(_SurfPt(
          pos: pos, normal: normal,
          weight: weight,
          inSolution: true, isMasked: false,
          productId: product.id, product: product,
          distGate: distanceDominance,
        ));
      }
    }

    // ── 2차 패스: 전류 보존 정규화 ──────────────────────────
    final totalWeight = allPts
        .where((p) => p.inSolution && !p.isMasked)
        .fold(0.0, (sum, p) => sum + p.weight);

    if (totalWeight <= 0) return [];

    double totalAreaDm2 =
        products.fold(0.0, (s, p2) => s + p2.surfaceAreaDm2);
    if (totalAreaDm2 <= 0) totalAreaDm2 = 1.0;

    final totalCurrent = elec.current;
    final activePtCount =
        allPts.where((p) => p.inSolution && !p.isMasked).length;
    final areaPerPtCm2 = activePtCount > 0
        ? totalAreaDm2 * 100.0 / activePtCount
        : 0.01;

    // ── 3차 패스: 두께 계산 ──────────────────────────────────
    for (final sp in allPts) {
      if (!sp.inSolution || sp.isMasked) {
        results.add(ThicknessPoint(
          position: sp.pos, normal: sp.normal,
          thickness: 0.0, currentDensity: 0.0,
          isMasked: sp.isMasked, inSolution: sp.inSolution,
          productId: sp.productId,
        ));
        continue;
      }

      // v9: 면방향(normalBias)은 1차 가중치 단계에서 이미 반영·거리게이트
      //     처리되었으므로, 여기서는 전류보존 분배만 수행한다(이중 증폭 제거).
      final weightFraction = sp.weight / totalWeight;
      final localCurrent = totalCurrent * weightFraction;
      final localCdCm2 = areaPerPtCm2 > 0 ? localCurrent / areaPerPtCm2 : 0.0;
      final redistributedCdCm2 = localCdCm2;
      final redistributedCdDm2 = redistributedCdCm2 * 100.0;

      // Faraday: T(µm) = (M × Cd[A/cm²] × t[s] × η) / (n × F × ρ) × 10⁴
      final thicknessMicron = (atomicWeight * redistributedCdCm2 * timeSec * efficiency) /
          (valence * faradayConst * density) * 1e4;

      results.add(ThicknessPoint(
        position: sp.pos, normal: sp.normal,
        thickness: thicknessMicron.clamp(0.0, 10000.0),
        currentDensity: redistributedCdDm2,
        inSolution: true,
        productId: sp.productId,
      ));
    }

    return results;
  }

  // ----------------------------------------------------------
  // 전기장 강도 분포 히트맵
  // ----------------------------------------------------------
  static List<FieldStrengthPoint> computeFieldStrengthMap({
    required TankSettings tank,
    required AnodeSettings anode,
    required List<ProductSettings> products,
    required int gridResolution,
  }) {
    if (products.isEmpty) return [];
    final sl = tank.solutionLevel;
    final anodePosList = getAnodePositionsMulti(
      tank: tank, anode: anode, products: products,
    );
    final results = <FieldStrengthPoint>[];
    for (final product in products) {
      final surfPts = getProductSurfacePoints(
          product: product, resolution: gridResolution);
      for (final (pos, normal) in surfPts) {
        final inSol = _inSolution(pos, sl);
        double strength = 0.0;
        if (inSol) {
          strength = computeFieldStrengthAt(pos, anodePosList, sl, anode: anode);
          final anodeFacingArea = (anode.depth * anode.length).clamp(1.0, double.infinity);
          final productFacingArea = (product.depth * product.length).clamp(1.0, double.infinity);
          final areaScale = 0.78 + math.pow((anodeFacingArea / productFacingArea).clamp(0.35, 8.0), 0.38).toDouble();
          final orientationBoost = () {
            if (normal.y < -0.35) return 1.72;
            if (normal.y > 0.35) return 1.92;
            if (normal.z.abs() > 0.35) return 1.98;
            if (normal.x.abs() > 0.35) return 1.20;
            return 1.0;
          }();
          strength *= orientationBoost * areaScale;
        }
        results.add(FieldStrengthPoint(
          position: pos, normal: normal,
          strength: strength, inSolution: inSol,
          productId: product.id,
        ));
      }
    }
    return results;
  }

  // ----------------------------------------------------------
  // 분석 결과
  // ----------------------------------------------------------
  static AnalysisResult analyze({
    required List<ThicknessPoint> thicknessPoints,
    required TankSettings tank,
    required AnodeSettings anode,
    required List<ProductSettings> products,
    required ElectricalSettings elec,
  }) {
    final active =
        thicknessPoints.where((p) => p.inSolution && !p.isMasked).toList();
    if (active.isEmpty) {
      return const AnalysisResult(
        minThickness: 0, maxThickness: 0, avgThickness: 0,
        uniformityIndex: 0, avgCurrentDensity: 0, totalCharge: 0,
        overallGrade: 'N/A', recommendations: [], warnings: [],
      );
    }

    final ts = active.map((p) => p.thickness).toList();
    final cds = active.map((p) => p.currentDensity).toList();
    final minT = ts.reduce(math.min);
    final maxT = ts.reduce(math.max);
    final avgT = ts.reduce((a, b) => a + b) / ts.length;
    final avgCd = cds.reduce((a, b) => a + b) / cds.length;
    final variance = ts
            .map((t) => (t - avgT) * (t - avgT))
            .reduce((a, b) => a + b) /
        ts.length;
    final stdDev = math.sqrt(variance);
    final uniformity =
        1.0 - (stdDev / avgT.clamp(0.01, 1e6)).clamp(0.0, 1.0);

    double totalAreaDm2 =
        products.fold(0.0, (s, p) => s + p.surfaceAreaDm2);
    final cdRange = elec.platingType.currentDensityRange;
    final targetCd = (cdRange.$1 + cdRange.$2) / 2.0;
    final recommendedCurrent = targetCd * totalAreaDm2;
    final recommendedVoltage =
        elec.computeVoltage(anode.distFromProduct, totalAreaDm2 * 100.0);

    String grade;
    if (uniformity > 0.85) {
      grade = 'A';
    } else if (uniformity > 0.70) {
      grade = 'B';
    } else if (uniformity > 0.55) {
      grade = 'C';
    } else {
      grade = 'D';
    }

    final recs = <String>[];
    final warns = <String>[];

    if (avgCd < cdRange.$1) {
      warns.add(
          '⚠ 전류밀도 부족 (${avgCd.toStringAsFixed(2)} < ${cdRange.$1} A/dm²)');
      recs.add(
          '전류를 높이거나 양극 거리를 줄이세요 (권장: ${recommendedCurrent.toStringAsFixed(1)} A)');
    } else if (avgCd > cdRange.$2) {
      warns.add(
          '⚠ 전류밀도 과다 (${avgCd.toStringAsFixed(2)} > ${cdRange.$2} A/dm²)');
      recs.add(
          '전류를 줄이거나 양극 거리를 늘리세요 (권장: ${recommendedCurrent.toStringAsFixed(1)} A)');
    }
    if (uniformity < 0.60) {
      warns.add('⚠ 균일도 낮음 — 도그본 효과 확인 필요');
      recs.add('양극 수 증가, 양극-제품 거리 재조정 또는 보조 양극 사용');
    }
    for (final product in products) {
      if (tank.solutionLevel < product.posY + product.depth + 5) {
        warns.add('⚠ 용액이 제품을 완전히 덮지 않음');
        recs.add(
            '용액 수위를 높이세요 (현재: ${tank.solutionLevel.toStringAsFixed(0)} cm)');
      }
    }
    if (recs.isEmpty) recs.add('현재 설정 양호 — 시운전 후 미세 조정');

    return AnalysisResult(
      minThickness: minT,
      maxThickness: maxT,
      avgThickness: avgT,
      uniformityIndex: uniformity,
      avgCurrentDensity: avgCd,
      totalCharge: elec.current * elec.platingTime,
      overallGrade: grade,
      recommendations: recs,
      warnings: warns,
      totalSurfaceAreaDm2: totalAreaDm2,
      recommendedCurrent: recommendedCurrent,
      recommendedVoltage: recommendedVoltage,
    );
  }

  static AnalysisResult analyzeSingle({
    required List<ThicknessPoint> thicknessPoints,
    required TankSettings tank,
    required AnodeSettings anode,
    required ProductSettings product,
    required ElectricalSettings elec,
  }) =>
      analyze(
        thicknessPoints: thicknessPoints,
        tank: tank,
        anode: anode,
        products: [product],
        elec: elec,
      );
}

// 내부 계산용 표면 포인트
class _SurfPt {
  final Vec3 pos;
  final Vec3 normal;
  final double weight;
  final bool inSolution;
  final bool isMasked;
  final String productId;
  final ProductSettings product;
  // v9: 점의 거리지배 게이트(0~1+). 정규화 이후의 어떤 보정도
  //     이 값을 초과해 두께를 키우지 못하도록 상한으로 사용한다.
  final double distGate;

  const _SurfPt({
    required this.pos,
    required this.normal,
    required this.weight,
    required this.inSolution,
    required this.isMasked,
    required this.productId,
    required this.product,
    this.distGate = 1.0,
  });
}

// 전기장 강도 포인트
class FieldStrengthPoint {
  final Vec3 position;
  final Vec3 normal;
  final double strength;
  final bool inSolution;
  final String productId;

  const FieldStrengthPoint({
    required this.position,
    required this.normal,
    required this.strength,
    required this.inSolution,
    required this.productId,
  });
}
