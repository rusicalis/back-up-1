import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/plating_models.dart';
import '../providers/plating_provider.dart';
import '../services/simulation_service.dart';
// ============================================================
// 3D 투영 시스템 (X=폭, Y=높이, Z=길이)
// ============================================================
class Proj3D {
  final double rotX, rotY;
  final double zoom;
  final Offset center;
  final double scale;

  const Proj3D({
    required this.rotX, required this.rotY,
    required this.zoom, required this.center, required this.scale,
  });

  Offset project(Vec3 v) {
    final rx = rotX * math.pi / 180.0;
    final ry = rotY * math.pi / 180.0;

    double x1 = v.x * math.cos(ry) - v.z * math.sin(ry);
    double y1 = v.y;
    double z1 = v.x * math.sin(ry) + v.z * math.cos(ry);

    double x2 = x1;
    double y2 = y1 * math.cos(rx) - z1 * math.sin(rx);
    double z2 = y1 * math.sin(rx) + z1 * math.cos(rx);

    const double fov = 800.0;
    final persp = fov / (fov + z2 + 300.0);
    return Offset(
      center.dx + x2 * scale * zoom * persp,
      center.dy - y2 * scale * zoom * persp,
    );
  }

  double projectDepth(Vec3 v) {
    final rx = rotX * math.pi / 180.0;
    final ry = rotY * math.pi / 180.0;
    final y1 = v.y;
    final z1 = v.x * math.sin(ry) + v.z * math.cos(ry);
    return y1 * math.sin(rx) + z1 * math.cos(rx);
  }

  bool isFrontFace(Offset p0, Offset p1, Offset p2) {
    final cross = (p1.dx - p0.dx) * (p2.dy - p0.dy) -
                  (p1.dy - p0.dy) * (p2.dx - p0.dx);
    return cross <= 0;
  }
}

// ============================================================
// 히트맵 색상 (파란→청록→초록→노랑→빨강) — 완전 불투명
// ============================================================
Color heatColor(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < 0.25) {
    return Color.fromARGB(255, 0, (t/0.25*255).round(), 255);
  } else if (t < 0.5) {
    return Color.fromARGB(255, 0, 255, ((1-(t-0.25)/0.25)*255).round());
  } else if (t < 0.75) {
    return Color.fromARGB(255, ((t-0.5)/0.25*255).round(), 255, 0);
  } else {
    return Color.fromARGB(255, 255, ((1-(t-0.75)/0.25)*255).round(), 0);
  }
}

// 전기장 분포 컬러맵 (파란→보라→핑크→흰색) — 완전 불투명
Color fieldStrengthColor(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < 0.33) {
    final u = t / 0.33;
    return Color.fromARGB(255, (u * 100).round(), (u * 20).round(), 200);
  } else if (t < 0.66) {
    final u = (t - 0.33) / 0.33;
    return Color.fromARGB(255, (100 + u * 155).round(), (20 + u * 10).round(), (200 + u * 55).round());
  } else {
    final u = (t - 0.66) / 0.34;
    return Color.fromARGB(255, 255, (30 + u * 225).round(), (255 * u).round());
  }
}

// ============================================================
// 렌더링 요소 (깊이 정렬용)
// ============================================================
class _RenderItem {
  final List<Vec3> verts;
  final Color fillColor;
  final Color? edgeColor;
  final double depth;
  final bool isEdgeOnly;
  final bool isOpaquePatch;
  final bool cullBackFace;
  final bool isOccluder;
  final Vec3? faceNormal;

  const _RenderItem({
    required this.verts,
    required this.fillColor,
    this.edgeColor,
    required this.depth,
    this.isEdgeOnly = false,
    this.isOpaquePatch = false,
    this.cullBackFace = true,
    this.isOccluder = true,
    this.faceNormal,
  });
}

// ============================================================
// 메인 3D 씬 페인터
// ============================================================
class PlatingScene3DPainter extends CustomPainter {
  final PlatingProvider p;

  PlatingScene3DPainter({required this.p});

  @override
  void paint(Canvas canvas, Size size) {
    final tank = p.tank;
    final anode = p.anode;
    final products = p.products;

    // 스케일 계산
    final maxDim = [tank.width, tank.depth, tank.length].reduce(math.max);
    final baseScale = (size.shortestSide * 0.32) / maxDim.clamp(1.0, 10000.0);

    final proj = Proj3D(
      rotX: p.rotX, rotY: p.rotY,
      zoom: p.zoom,
      center: Offset(size.width / 2 + p.panX, size.height / 2 + p.panY),
      scale: baseScale,
    );

    final hw = tank.width / 2;
    final hd = tank.depth;
    final hl = tank.length / 2;
    final sl = tank.solutionLevel;

    final renderItems = <_RenderItem>[];

    // ① 탱크
    if (p.showTank) {
      _collectTankItems(renderItems, proj, hw, hd, hl, sl);
    }

    // ② 양극 (다수 제품 기반) — showAnodes 플래그 적용
    final anodePositions = PlatingSimulationService.getAnodePositionsMulti(
      tank: tank, anode: anode, products: products,
    );
    if (p.showAnodes) {
      _collectAnodeItems(renderItems, proj, anode, anodePositions, sl);
    }

    // ③ 두께 포인트 / 전기장 포인트 별로 제품 ID 분류
    final Map<String, List<ThicknessPoint>> thickByProduct = {};
    for (final tp in p.thicknessPoints) {
      thickByProduct.putIfAbsent(tp.productId, () => []).add(tp);
    }
    final Map<String, List<FieldStrengthPoint>> fieldByProduct = {};
    for (final fp in p.fieldStrengthPoints) {
      fieldByProduct.putIfAbsent(fp.productId, () => []).add(fp);
    }

    // ④ 제품들 렌더링
    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      final productThick = thickByProduct[product.id] ?? [];
      final productField = fieldByProduct[product.id] ?? [];
      final isSelected = i == p.selectedProductIndex;
      _collectProductItems(
        items: renderItems,
        proj: proj,
        product: product,
        thicknessPoints: productThick,
        fieldPoints: productField,
        showHeatmap: p.showHeatmap,
        heatmapMode: p.heatmapMode,
        solutionLevel: sl,
        isSelected: isSelected,
        productIdx: i,
      );
    }

    // ⑤ 마스킹 영역 (선택된 제품 기준)
    if (p.maskingZones.isNotEmpty && products.isNotEmpty) {
      _collectMaskingItems(renderItems, proj, p.product, p.maskingZones);
    }

    renderItems.sort((a, b) => a.depth.compareTo(b.depth));
    final occluders = renderItems
        .where((item) => !item.isEdgeOnly && item.isOccluder)
        .toList(growable: false);

    for (final item in renderItems) {
      if (item.verts.length < 2) continue;
      final pts = item.verts.map((v) => proj.project(v)).toList();

      if (item.isEdgeOnly) {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) { path.lineTo(pts[i].dx, pts[i].dy); }
        if (item.verts.length > 2) path.close();
        canvas.drawPath(path, Paint()
          ..color = item.fillColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
        continue;
      }

      if (item.cullBackFace && pts.length >= 3) {
        final normal = item.faceNormal ?? _computeFaceNormal(item.verts);
        if (!_isFrontFacingNormal(proj, normal)) continue;
      }

      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) { path.lineTo(pts[i].dx, pts[i].dy); }
      path.close();

      if (item.fillColor.a > 0) {
        canvas.drawPath(path, Paint()..color = item.fillColor);
      }
      if (item.edgeColor != null) {
        canvas.drawPath(path, Paint()
          ..color = item.edgeColor!
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke);
      }
    }

    if (p.showFieldLines && p.fieldLines.isNotEmpty && p.fieldLine2DMode == FieldLine2DMode.none) {
      _drawFieldLines(canvas, proj, p.fieldLines, sl, occluders);
    }

    // ⑦ 라벨 & 치수선
    _drawLabels(canvas, proj, tank, anode, products, anodePositions, sl);

    // ⑧ 좌표축
    _drawAxes(canvas, proj, maxDim * 0.25);

    // ⑨ 범례
    if (p.showHeatmap) {
      if (p.heatmapMode == HeatmapMode.thickness && p.thicknessPoints.isNotEmpty) {
        _drawThicknessLegend(canvas, size, p.thicknessPoints);
      } else if (p.heatmapMode == HeatmapMode.fieldStrength && p.fieldStrengthPoints.isNotEmpty) {
        _drawFieldStrengthLegend(canvas, size, p.fieldStrengthPoints);
      }
    }

    // ⑩ 줌 레벨 + 제품 정보
    _drawOverlayInfo(canvas, size, p);
  }

  // ----------------------------------------------------------
  // 탱크 렌더
  // ----------------------------------------------------------
  void _collectTankItems(List<_RenderItem> items, Proj3D proj,
      double hw, double hd, double hl, double sl) {
    final v = [
      Vec3(-hw, 0,  -hl), Vec3(hw, 0,  -hl),
      Vec3(hw,  0,  hl),  Vec3(-hw, 0, hl),
      Vec3(-hw, hd, -hl), Vec3(hw,  hd, -hl),
      Vec3(hw,  hd, hl),  Vec3(-hw, hd, hl),
    ];

    final faces = [
      ([v[0],v[1],v[5],v[4]], const Color(0x15607D8B)),
      ([v[3],v[2],v[6],v[7]], const Color(0x12607D8B)),
      ([v[0],v[3],v[7],v[4]], const Color(0x12607D8B)),
      ([v[1],v[2],v[6],v[5]], const Color(0x12607D8B)),
      ([v[0],v[1],v[2],v[3]], const Color(0x18607D8B)),
    ];

    for (final (faceVerts, color) in faces) {
      final centerV = faceVerts.fold<Vec3>(Vec3.zero, (acc, v2) => acc + v2) / faceVerts.length.toDouble();
      items.add(_RenderItem(
        verts: faceVerts,
        fillColor: color,
        edgeColor: Colors.blueGrey.shade400.withValues(alpha: 0.5),
        depth: proj.projectDepth(centerV),
        isOccluder: false,
      ));
    }

    // 용액면
    if (sl > 0 && sl <= hd) {
      final solFace = [
        Vec3(-hw, sl, -hl), Vec3(hw, sl, -hl),
        Vec3(hw, sl, hl),  Vec3(-hw, sl, hl),
      ];
      items.add(_RenderItem(
        verts: solFace,
        fillColor: const Color(0x3000B4D8),
        edgeColor: const Color(0x8800B4D8),
        depth: proj.projectDepth(Vec3(0, sl, 0)) - 0.1,
        isOccluder: false,
      ));
    }
  }

  // ----------------------------------------------------------
  // 양극 렌더
  // ----------------------------------------------------------
  void _collectAnodeItems(List<_RenderItem> items, Proj3D proj,
      AnodeSettings anode, List<(Vec3, Vec3)> positions, double sl) {
    for (int ai = 0; ai < positions.length; ai++) {
      final (center, _) = positions[ai];
      final hw = anode.width / 2;
      final hd = anode.depth / 2;
      final hl = anode.length / 2;

      final yBot = center.y - hd;
      final yTop = math.min(center.y + hd, sl);

      if (yBot >= sl) continue;

      final isLeft = ai % 2 == 0;

      final verts = [
        Vec3(center.x-hw, yBot, center.z-hl),
        Vec3(center.x+hw, yBot, center.z-hl),
        Vec3(center.x+hw, yTop, center.z-hl),
        Vec3(center.x-hw, yTop, center.z-hl),
        Vec3(center.x-hw, yBot, center.z+hl),
        Vec3(center.x+hw, yBot, center.z+hl),
        Vec3(center.x+hw, yTop, center.z+hl),
        Vec3(center.x-hw, yTop, center.z+hl),
      ];

      final fillColor = isLeft
          ? const Color(0xBBFF8C00)
          : const Color(0xBBFF6030);

      _addBoxItems(items, proj, verts, fill: fillColor, edge: const Color(0xFFFF6500));

      final yTopFull = center.y + hd;
      if (yTopFull > sl) {
        final vertsAbove = [
          Vec3(center.x-hw, sl, center.z-hl), Vec3(center.x+hw, sl, center.z-hl),
          Vec3(center.x+hw, yTopFull, center.z-hl), Vec3(center.x-hw, yTopFull, center.z-hl),
          Vec3(center.x-hw, sl, center.z+hl), Vec3(center.x+hw, sl, center.z+hl),
          Vec3(center.x+hw, yTopFull, center.z+hl), Vec3(center.x-hw, yTopFull, center.z+hl),
        ];
        _addBoxItems(items, proj, vertsAbove,
            fill: const Color(0x44888888), edge: const Color(0x66888888), isOccluder: false);
      }
    }
  }

  // ----------------------------------------------------------
  // 제품 + 히트맵 렌더
  // 모드: thickness (도금두께) / fieldStrength (전기장강도)
  // ----------------------------------------------------------
  void _collectProductItems({
      required List<_RenderItem> items,
      required Proj3D proj,
      required ProductSettings product,
      required List<ThicknessPoint> thicknessPoints,
      required List<FieldStrengthPoint> fieldPoints,
      required bool showHeatmap,
      required HeatmapMode heatmapMode,
      required double solutionLevel,
      required bool isSelected,
      required int productIdx}) {

    if (product.cadImport.isImported && product.cadImport.previewVertices.isNotEmpty) {
      _collectCadPreviewItems(
        items,
        proj,
        product,
        thicknessPoints,
        fieldPoints,
        showHeatmap,
        heatmapMode,
        isSelected,
      );
      return;
    }

    if (product.useLegoMode && product.legoPieces.isNotEmpty) {
      _collectLegoItems(items, proj, product, thicknessPoints, fieldPoints,
          showHeatmap, heatmapMode, solutionLevel, isSelected);
      return;
    }

    final hasHeatmapSurface = showHeatmap &&
        ((heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) ||
            (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty));

    // 히트맵 표시
    if (hasHeatmapSurface) {
      if (heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) {
        _renderThicknessPatches(items, proj, thicknessPoints, product);
      } else if (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty) {
        _renderFieldStrengthPatches(items, proj, fieldPoints, product);
      }
    }

    final surfaceVerts = _buildSurfaceVerts(product);
    final frameVerts = _buildFrameVerts(product);

    final hasHeatData = (heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) ||
        (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty);

    final materialBase = product.material.color;
    final prodColor = isSelected
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.12),
            materialBase.withValues(alpha: hasHeatmapSurface ? 0.18 : 0.96),
          )
        : materialBase.withValues(alpha: hasHeatmapSurface ? 0.10 : 0.93);
    final shouldRenderSolidWithHeatmap = true;
    final edgeColor = isSelected
        ? Colors.lightBlueAccent
        : materialBase.withValues(alpha: 0.98);

    if (shouldRenderSolidWithHeatmap) {
      _addProductSolidItems(
        items,
        proj,
        product,
        surfaceVerts,
        prodColor,
        edgeColor,
        isOccluder: true,
      );
    }

    if (showHeatmap && hasHeatData) {
      final wireColor = isSelected
          ? Colors.white.withValues(alpha: 0.9)
          : product.material.color.withValues(alpha: 0.72);
      _addProductFrameLines(items, proj, frameVerts, color: wireColor, product: product);
    }

    if (isSelected) {
      _addProductFrameLines(items, proj, frameVerts,
          color: Colors.cyanAccent.withValues(alpha: 0.55), product: product);
    }
  }

  // 도금 두께 패치 렌더링 — 면별 정확한 격자 간격 사용
  void _renderThicknessPatches(List<_RenderItem> items, Proj3D proj,
      List<ThicknessPoint> thicknessPoints, ProductSettings product) {
    double minT = double.infinity, maxT = double.negativeInfinity;
    for (final tp in thicknessPoints) {
      if (tp.inSolution && !tp.isMasked && tp.thickness > 0) {
        if (tp.thickness < minT) minT = tp.thickness;
        if (tp.thickness > maxT) maxT = tp.thickness;
      }
    }
    if (minT == double.infinity) { minT = 0; maxT = 1; }
    final rangeT = (maxT - minT).clamp(0.001, 10000.0);

    // 면별 패치 크기: 해당 면에서 격자 샘플링되는 두 방향의 실제 간격
    const gridRes = 25;
    final sizeX = math.min(product.depth * 2, product.length * 2) / gridRes * 1.12;
    final sizeY = math.min(product.width * 2, product.length * 2) / gridRes * 1.12;
    final sizeZ = math.min(product.width * 2, product.depth  * 2) / gridRes * 1.12;

    for (final tp in thicknessPoints) {
      if (!tp.inSolution) continue;
      Color col;
      if (tp.isMasked) {
        col = const Color(0xFF1A1A44);
      } else {
        final t = (tp.thickness - minT) / rangeT;
        col = heatColor(t);
      }
      final gs = tp.normal.x.abs() > 0.5 ? sizeX
                : tp.normal.y.abs() > 0.5 ? sizeY : sizeZ;
      _addSurfacePatchOpaque(items, proj, tp.position, tp.normal, gs, col);
    }
  }

  // 전기장 분포 패치 렌더링 — 면별 정확한 격자 간격
  void _renderFieldStrengthPatches(List<_RenderItem> items, Proj3D proj,
      List<FieldStrengthPoint> fieldPoints, ProductSettings product) {
    double minS = double.infinity, maxS = double.negativeInfinity;
    for (final fp in fieldPoints) {
      if (fp.inSolution && fp.strength > 0) {
        if (fp.strength < minS) minS = fp.strength;
        if (fp.strength > maxS) maxS = fp.strength;
      }
    }
    if (minS == double.infinity) { minS = 0; maxS = 1; }
    final rangeS = (maxS - minS).clamp(1e-10, double.infinity);

    const gridRes = 25;
    final sizeX = math.min(product.depth * 2, product.length * 2) / gridRes * 1.12;
    final sizeY = math.min(product.width * 2, product.length * 2) / gridRes * 1.12;
    final sizeZ = math.min(product.width * 2, product.depth  * 2) / gridRes * 1.12;

    final visiblePoints = fieldPoints.where((fp) => fp.inSolution).toList();

    visiblePoints.sort((a, b) {
      final da = proj.projectDepth(a.position);
      final db = proj.projectDepth(b.position);
      return da.compareTo(db);
    });

    for (final fp in visiblePoints) {
      final t = (fp.strength - minS) / rangeS;
      final col = fieldStrengthColor(t);
      final gs = fp.normal.x.abs() > 0.5 ? sizeX
                : fp.normal.y.abs() > 0.5 ? sizeY : sizeZ;
      _addSurfacePatchOpaque(items, proj, fp.position, fp.normal, gs, col);
    }
  }

  // 불투명 표면 패치 추가 헬퍼
  // 법선 벡터를 뷰 공간으로 변환하여 정확한 back-face culling 적용
  // 법선의 뷰 공간 z2 < 0 이면 카메라를 향하는 면 (front face)
  void _addSurfacePatchOpaque(List<_RenderItem> items, Proj3D proj,
      Vec3 pos, Vec3 n3, double gs, Color col) {
    final normal = n3.normalized();
    final facing = _viewFacingScore(proj, normal);

    final List<Vec3> patch;
    if (n3.x.abs() > 0.5) {
      // YZ 면 (±X 법선)
      patch = [
        Vec3(pos.x, pos.y - gs/2, pos.z - gs/2),
        Vec3(pos.x, pos.y - gs/2, pos.z + gs/2),
        Vec3(pos.x, pos.y + gs/2, pos.z + gs/2),
        Vec3(pos.x, pos.y + gs/2, pos.z - gs/2),
      ];
    } else if (n3.y.abs() > 0.5) {
      // XZ 면 (±Y 법선)
      patch = [
        Vec3(pos.x - gs/2, pos.y, pos.z - gs/2),
        Vec3(pos.x + gs/2, pos.y, pos.z - gs/2),
        Vec3(pos.x + gs/2, pos.y, pos.z + gs/2),
        Vec3(pos.x - gs/2, pos.y, pos.z + gs/2),
      ];
    } else {
      // XY 면 (±Z 법선)
      patch = [
        Vec3(pos.x - gs/2, pos.y - gs/2, pos.z),
        Vec3(pos.x + gs/2, pos.y - gs/2, pos.z),
        Vec3(pos.x + gs/2, pos.y + gs/2, pos.z),
        Vec3(pos.x - gs/2, pos.y + gs/2, pos.z),
      ];
    }

    // 3) 중심 깊이 계산 후 렌더 아이템 추가
    final centerV = patch.fold<Vec3>(Vec3.zero, (acc, v) => acc + v) / 4.0;
    final depth = proj.projectDepth(centerV);

    if (!_isFrontFacingNormal(proj, normal)) {
      return;
    }

    final alphaScale = (0.94 + facing * 0.08).clamp(0.90, 1.0);
    items.add(_RenderItem(
      verts: patch,
      fillColor: col.withValues(alpha: (col.a / 255.0 * alphaScale).clamp(0.86, 1.0)),
      depth: depth - 0.2,
      isOpaquePatch: true,
      cullBackFace: true,
      isOccluder: false,
      faceNormal: normal,
    ));
  }

  Vec3 _computeFaceNormal(List<Vec3> face) {
    if (face.length < 3) return const Vec3(0, 0, 1);
    return (face[1] - face[0]).cross(face[2] - face[0]).normalized();
  }

  bool _isFrontFacingNormal(Proj3D proj, Vec3 normal) {
    return _viewFacingScore(proj, normal) > 0.0001;
  }

  double _viewFacingScore(Proj3D proj, Vec3 normal) {
    final rx = proj.rotX * math.pi / 180.0;
    final ry = proj.rotY * math.pi / 180.0;
    final x1 = normal.x * math.cos(ry) - normal.z * math.sin(ry);
    final y1 = normal.y;
    final z1 = normal.x * math.sin(ry) + normal.z * math.cos(ry);
    final y2 = y1 * math.cos(rx) - z1 * math.sin(rx);
    final z2 = y1 * math.sin(rx) + z1 * math.cos(rx);
    return Vec3(x1, y2, z2).normalized().z;
  }

  void _collectCadPreviewItems(
      List<_RenderItem> items,
      Proj3D proj,
      ProductSettings product,
      List<ThicknessPoint> thicknessPoints,
      List<FieldStrengthPoint> fieldPoints,
      bool showHeatmap,
      HeatmapMode heatmapMode,
      bool isSelected) {
    if (showHeatmap) {
      if (heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) {
        _renderThicknessPatches(items, proj, thicknessPoints, product);
      } else if (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty) {
        _renderFieldStrengthPatches(items, proj, fieldPoints, product);
      }
    }

    final center = Vec3(product.posX, product.posY + product.depth / 2, product.posZ);
    final tris = product.cadImport.triangles;
    final fillColor = isSelected
        ? Colors.cyanAccent.withValues(alpha: showHeatmap ? 0.78 : 0.92)
        : product.material.color.withValues(alpha: showHeatmap ? 0.72 : 0.88);
    final edgeColor = isSelected
        ? Colors.white.withValues(alpha: 0.82)
        : product.material.color.withValues(alpha: 0.70);

    if (tris.isNotEmpty) {
      for (final tri in tris) {
        final verts = [center + tri.a, center + tri.b, center + tri.c];
        final correctedNormal = _outwardTriangleNormal(verts, tri.normal, center);
        final triCenter = (verts[0] + verts[1] + verts[2]) / 3.0;
        items.add(_RenderItem(
          verts: verts,
          fillColor: fillColor,
          edgeColor: edgeColor,
          depth: proj.projectDepth(triCenter),
          cullBackFace: true,
          isOccluder: true,
          faceNormal: correctedNormal,
        ));
      }
    } else {
      final points = product.cadImport.previewVertices;
      final dotColor = isSelected
          ? Colors.cyanAccent.withValues(alpha: 0.95)
          : product.material.color.withValues(alpha: 0.88);
      for (final pt in points) {
        final world = center + pt;
        final radialNormal = (world - center).normalized();
        _addSurfacePatchOpaque(items, proj, world, radialNormal, 0.8, dotColor);
      }
    }

    final frameVerts = _buildFrameVerts(product);
    _addProductFrameLines(
      items,
      proj,
      frameVerts,
      color: Colors.white.withValues(alpha: 0.72),
      product: product,
    );
  }

  // 레고 피스 렌더링
  void _collectLegoItems(List<_RenderItem> items, Proj3D proj,
      ProductSettings product,
      List<ThicknessPoint> thicknessPoints,
      List<FieldStrengthPoint> fieldPoints,
      bool showHeatmap, HeatmapMode heatmapMode,
      double sl, bool isSelected) {

    final baseCX = product.posX;
    final baseCY = product.posY + product.depth / 2;
    final baseCZ = product.posZ;

    if (showHeatmap) {
      if (heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) {
        _renderThicknessPatches(items, proj, thicknessPoints, product);
      } else if (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty) {
        _renderFieldStrengthPatches(items, proj, fieldPoints, product);
      }
    }

    // 각 레고 피스 와이어프레임
    final hasHeatData = (heatmapMode == HeatmapMode.thickness && thicknessPoints.isNotEmpty) ||
        (heatmapMode == HeatmapMode.fieldStrength && fieldPoints.isNotEmpty);

    for (int pi = 0; pi < product.legoPieces.length; pi++) {
      final piece = product.legoPieces[pi];
      final cx = baseCX + piece.offsetX;
      final cy = baseCY + piece.offsetY;
      final cz = baseCZ + piece.offsetZ;
      final hw = piece.width / 2;
      final hh = piece.height / 2;
      final hl = piece.length / 2;

      final pieceVerts = [
        Vec3(cx-hw, cy-hh, cz-hl), Vec3(cx+hw, cy-hh, cz-hl),
        Vec3(cx+hw, cy+hh, cz-hl), Vec3(cx-hw, cy+hh, cz-hl),
        Vec3(cx-hw, cy-hh, cz+hl), Vec3(cx+hw, cy-hh, cz+hl),
        Vec3(cx+hw, cy+hh, cz+hl), Vec3(cx-hw, cy+hh, cz+hl),
      ];

      _addBoxItems(items, proj, pieceVerts,
        fill: piece.color.withValues(alpha: showHeatmap ? 0.42 : 0.82),
        edge: piece.color.withValues(alpha: isSelected ? 0.95 : 0.78));
      if (showHeatmap && hasHeatData) {
        _addBoxEdgeLines(items, proj, pieceVerts,
          color: piece.color.withValues(alpha: isSelected ? 0.82 : 0.52));
      }
    }
  }

  // ----------------------------------------------------------
  // 마스킹 영역 시각화
  // ----------------------------------------------------------
  void _collectMaskingItems(List<_RenderItem> items, Proj3D proj,
      ProductSettings product, List<MaskingZone> zones) {
    for (final zone in zones) {
      final cx = product.posX - product.width/2 +
          (zone.xMin + zone.xMax) / 2 * product.width;
      final cy = product.posY + zone.yMin * product.depth +
          (zone.yMax - zone.yMin) / 2 * product.depth;
      final cz = product.posZ - product.length/2 +
          (zone.zMin + zone.zMax) / 2 * product.length;
      final hw = (zone.xMax - zone.xMin) / 2 * product.width;
      final hd = (zone.yMax - zone.yMin) / 2 * product.depth;
      final hl = (zone.zMax - zone.zMin) / 2 * product.length;

      final verts = [
        Vec3(cx-hw,cy-hd,cz-hl), Vec3(cx+hw,cy-hd,cz-hl),
        Vec3(cx+hw,cy+hd,cz-hl), Vec3(cx-hw,cy+hd,cz-hl),
        Vec3(cx-hw,cy-hd,cz+hl), Vec3(cx+hw,cy-hd,cz+hl),
        Vec3(cx+hw,cy+hd,cz+hl), Vec3(cx-hw,cy+hd,cz+hl),
      ];
      _addBoxEdgeLines(items, proj, verts, color: const Color(0xFFAA00AA));
    }
  }

  // ----------------------------------------------------------
  // 박스 헬퍼
  // ----------------------------------------------------------
  List<List<Vec3>> _buildSurfaceVerts(ProductSettings product) {
    final cx = product.posX;
    final cy = product.posY + product.depth / 2;
    final cz = product.posZ;
    final hw = product.width / 2;
    final hd = product.depth / 2;
    final hl = product.length / 2;

    switch (product.shape) {
      case ProductShape.box:
      case ProductShape.cylinder:
      case ProductShape.dish:
        final v = _buildFrameVerts(product);
        return [
          [v[0], v[1], v[2], v[3]],
          [v[5], v[4], v[7], v[6]],
          [v[4], v[0], v[3], v[7]],
          [v[1], v[5], v[6], v[2]],
          [v[3], v[2], v[6], v[7]],
          [v[4], v[5], v[1], v[0]],
        ];
      case ProductShape.hollowBox:
        return _buildHollowBoxFaces(product);
      case ProductShape.pipe:
        return _buildPipeFaces(product);
      case ProductShape.lShape:
        final a = [
          Vec3(cx-hw, cy-hd, cz-hl), Vec3(cx, cy-hd, cz-hl),
          Vec3(cx, cy+hd, cz-hl), Vec3(cx-hw, cy+hd, cz-hl),
          Vec3(cx-hw, cy-hd, cz+hl), Vec3(cx, cy-hd, cz+hl),
          Vec3(cx, cy+hd, cz+hl), Vec3(cx-hw, cy+hd, cz+hl),
        ];
        final b = [
          Vec3(cx, cy-hd, cz-hl), Vec3(cx+hw, cy-hd, cz-hl),
          Vec3(cx+hw, cy+hd*0.35, cz-hl), Vec3(cx, cy+hd*0.35, cz-hl),
          Vec3(cx, cy-hd, cz+hl), Vec3(cx+hw, cy-hd, cz+hl),
          Vec3(cx+hw, cy+hd*0.35, cz+hl), Vec3(cx, cy+hd*0.35, cz+hl),
        ];
        return [
          [a[0], a[1], a[2], a[3]], [a[5], a[4], a[7], a[6]], [a[4], a[0], a[3], a[7]],
          [a[1], a[5], a[6], a[2]], [a[3], a[2], a[6], a[7]], [a[4], a[5], a[1], a[0]],
          [b[0], b[1], b[2], b[3]], [b[5], b[4], b[7], b[6]], [b[1], b[5], b[6], b[2]],
          [b[3], b[2], b[6], b[7]], [b[4], b[5], b[1], b[0]],
        ];
      case ProductShape.bracket:
        final body = [
          Vec3(cx-hw, cy-hd, cz-hl*0.65), Vec3(cx+hw*0.3, cy-hd, cz-hl*0.65),
          Vec3(cx+hw*0.3, cy+hd, cz-hl*0.65), Vec3(cx-hw, cy+hd, cz-hl*0.65),
          Vec3(cx-hw, cy-hd, cz+hl*0.05), Vec3(cx+hw*0.3, cy-hd, cz+hl*0.05),
          Vec3(cx+hw*0.3, cy+hd, cz+hl*0.05), Vec3(cx-hw, cy+hd, cz+hl*0.05),
        ];
        final tower = [
          Vec3(cx, cy-hd*0.15, cz-hl*0.1), Vec3(cx+hw, cy-hd*0.15, cz-hl*0.1),
          Vec3(cx+hw, cy+hd, cz-hl*0.1), Vec3(cx, cy+hd, cz-hl*0.1),
          Vec3(cx, cy-hd*0.15, cz+hl), Vec3(cx+hw, cy-hd*0.15, cz+hl),
          Vec3(cx+hw, cy+hd, cz+hl), Vec3(cx, cy+hd, cz+hl),
        ];
        return [
          [body[0], body[1], body[2], body[3]], [body[5], body[4], body[7], body[6]],
          [body[4], body[0], body[3], body[7]], [body[1], body[5], body[6], body[2]],
          [body[3], body[2], body[6], body[7]], [body[4], body[5], body[1], body[0]],
          [tower[0], tower[1], tower[2], tower[3]], [tower[5], tower[4], tower[7], tower[6]],
          [tower[4], tower[0], tower[3], tower[7]], [tower[1], tower[5], tower[6], tower[2]],
          [tower[3], tower[2], tower[6], tower[7]], [tower[4], tower[5], tower[1], tower[0]],
        ];
      case ProductShape.steppedBox:
        final lower = [
          Vec3(cx-hw, cy-hd, cz-hl), Vec3(cx+hw, cy-hd, cz-hl),
          Vec3(cx+hw, cy+hd*0.2, cz-hl), Vec3(cx-hw, cy+hd*0.2, cz-hl),
          Vec3(cx-hw, cy-hd, cz+hl), Vec3(cx+hw, cy-hd, cz+hl),
          Vec3(cx+hw, cy+hd*0.2, cz+hl), Vec3(cx-hw, cy+hd*0.2, cz+hl),
        ];
        final upper = [
          Vec3(cx-hw*0.7, cy+hd*0.2, cz-hl*0.65), Vec3(cx+hw*0.7, cy+hd*0.2, cz-hl*0.65),
          Vec3(cx+hw*0.7, cy+hd, cz-hl*0.65), Vec3(cx-hw*0.7, cy+hd, cz-hl*0.65),
          Vec3(cx-hw*0.7, cy+hd*0.2, cz+hl*0.65), Vec3(cx+hw*0.7, cy+hd*0.2, cz+hl*0.65),
          Vec3(cx+hw*0.7, cy+hd, cz+hl*0.65), Vec3(cx-hw*0.7, cy+hd, cz+hl*0.65),
        ];
        return [
          [lower[0], lower[1], lower[2], lower[3]], [lower[5], lower[4], lower[7], lower[6]],
          [lower[4], lower[0], lower[3], lower[7]], [lower[1], lower[5], lower[6], lower[2]],
          [lower[3], lower[2], lower[6], lower[7]], [lower[4], lower[5], lower[1], lower[0]],
          [upper[0], upper[1], upper[2], upper[3]], [upper[5], upper[4], upper[7], upper[6]],
          [upper[4], upper[0], upper[3], upper[7]], [upper[1], upper[5], upper[6], upper[2]],
          [upper[3], upper[2], upper[6], upper[7]], [upper[4], upper[5], upper[1], upper[0]],
        ];
    }
  }

  List<List<Vec3>> _buildHollowBoxFaces(ProductSettings product) {
    final cx = product.posX;
    final cy = product.posY + product.depth / 2;
    final cz = product.posZ;
    final hw = product.width / 2;
    final hd = product.depth / 2;
    final hl = product.length / 2;
    final innerHw = math.max(0.1, hw - product.wallThickness);
    final innerHd = math.max(0.1, hd - product.wallThickness);
    final innerHl = math.max(0.1, hl - product.wallThickness);

    return [
      [Vec3(cx + hw, cy - hd, cz - hl), Vec3(cx + hw, cy + hd, cz - hl), Vec3(cx + hw, cy + hd, cz + hl), Vec3(cx + hw, cy - hd, cz + hl)],
      [Vec3(cx - hw, cy - hd, cz + hl), Vec3(cx - hw, cy + hd, cz + hl), Vec3(cx - hw, cy + hd, cz - hl), Vec3(cx - hw, cy - hd, cz - hl)],
      [Vec3(cx - hw, cy + hd, cz - hl), Vec3(cx - hw, cy + hd, cz + hl), Vec3(cx + hw, cy + hd, cz + hl), Vec3(cx + hw, cy + hd, cz - hl)],
      [Vec3(cx - hw, cy - hd, cz + hl), Vec3(cx - hw, cy - hd, cz - hl), Vec3(cx + hw, cy - hd, cz - hl), Vec3(cx + hw, cy - hd, cz + hl)],
      [Vec3(cx + hw, cy - hd, cz + hl), Vec3(cx + hw, cy + hd, cz + hl), Vec3(cx - hw, cy + hd, cz + hl), Vec3(cx - hw, cy - hd, cz + hl)],
      [Vec3(cx - hw, cy - hd, cz - hl), Vec3(cx - hw, cy + hd, cz - hl), Vec3(cx + hw, cy + hd, cz - hl), Vec3(cx + hw, cy - hd, cz - hl)],
      [Vec3(cx + innerHw, cy - innerHd, cz - innerHl), Vec3(cx + innerHw, cy - innerHd, cz + innerHl), Vec3(cx + innerHw, cy + innerHd, cz + innerHl), Vec3(cx + innerHw, cy + innerHd, cz - innerHl)],
      [Vec3(cx - innerHw, cy - innerHd, cz + innerHl), Vec3(cx - innerHw, cy - innerHd, cz - innerHl), Vec3(cx - innerHw, cy + innerHd, cz - innerHl), Vec3(cx - innerHw, cy + innerHd, cz + innerHl)],
      [Vec3(cx - innerHw, cy + innerHd, cz - innerHl), Vec3(cx + innerHw, cy + innerHd, cz - innerHl), Vec3(cx + innerHw, cy + innerHd, cz + innerHl), Vec3(cx - innerHw, cy + innerHd, cz + innerHl)],
      [Vec3(cx - innerHw, cy - innerHd, cz + innerHl), Vec3(cx + innerHw, cy - innerHd, cz + innerHl), Vec3(cx + innerHw, cy - innerHd, cz - innerHl), Vec3(cx - innerHw, cy - innerHd, cz - innerHl)],
      [Vec3(cx - innerHw, cy - innerHd, cz + innerHl), Vec3(cx - innerHw, cy + innerHd, cz + innerHl), Vec3(cx + innerHw, cy + innerHd, cz + innerHl), Vec3(cx + innerHw, cy - innerHd, cz + innerHl)],
      [Vec3(cx + innerHw, cy - innerHd, cz - innerHl), Vec3(cx + innerHw, cy + innerHd, cz - innerHl), Vec3(cx - innerHw, cy + innerHd, cz - innerHl), Vec3(cx - innerHw, cy - innerHd, cz - innerHl)],
    ];
  }

  List<List<Vec3>> _buildPipeFaces(ProductSettings product) {
    final cx = product.posX;
    final cy = product.posY + product.depth / 2;
    final cz = product.posZ;
    final outerR = product.width / 2;
    final innerR = math.max(0.1, outerR - product.wallThickness);
    final halfDepth = product.depth / 2;
    const segments = 28;
    final faces = <List<Vec3>>[];

    for (int i = 0; i < segments; i++) {
      final a0 = i / segments * math.pi * 2;
      final a1 = (i + 1) / segments * math.pi * 2;
      final outer0Bottom = Vec3(cx + math.cos(a0) * outerR, cy - halfDepth, cz + math.sin(a0) * outerR);
      final outer1Bottom = Vec3(cx + math.cos(a1) * outerR, cy - halfDepth, cz + math.sin(a1) * outerR);
      final outer1Top = Vec3(cx + math.cos(a1) * outerR, cy + halfDepth, cz + math.sin(a1) * outerR);
      final outer0Top = Vec3(cx + math.cos(a0) * outerR, cy + halfDepth, cz + math.sin(a0) * outerR);
      final inner0Bottom = Vec3(cx + math.cos(a0) * innerR, cy - halfDepth, cz + math.sin(a0) * innerR);
      final inner1Bottom = Vec3(cx + math.cos(a1) * innerR, cy - halfDepth, cz + math.sin(a1) * innerR);
      final inner1Top = Vec3(cx + math.cos(a1) * innerR, cy + halfDepth, cz + math.sin(a1) * innerR);
      final inner0Top = Vec3(cx + math.cos(a0) * innerR, cy + halfDepth, cz + math.sin(a0) * innerR);

      faces.add([outer0Bottom, outer1Bottom, outer1Top, outer0Top]);
      faces.add([inner1Bottom, inner0Bottom, inner0Top, inner1Top]);
      faces.add([outer0Top, outer1Top, inner1Top, inner0Top]);
      faces.add([inner0Bottom, inner1Bottom, outer1Bottom, outer0Bottom]);
    }
    return faces;
  }

  List<Vec3> _buildFrameVerts(ProductSettings product) {
    final cx = product.posX;
    final cy = product.posY + product.depth / 2;
    final cz = product.posZ;
    final hw = product.width / 2;
    final hd = product.depth / 2;
    final hl = product.length / 2;
    return [
      Vec3(cx-hw, cy-hd, cz-hl), Vec3(cx+hw, cy-hd, cz-hl),
      Vec3(cx+hw, cy+hd, cz-hl), Vec3(cx-hw, cy+hd, cz-hl),
      Vec3(cx-hw, cy-hd, cz+hl), Vec3(cx+hw, cy-hd, cz+hl),
      Vec3(cx+hw, cy+hd, cz+hl), Vec3(cx-hw, cy+hd, cz+hl),
    ];
  }

  void _addProductSolidItems(List<_RenderItem> items, Proj3D proj, ProductSettings product,
      List<List<Vec3>> faces, Color fill, Color edge, {bool isOccluder = true}) {
    final productCenter = Vec3(product.posX, product.posY + product.depth / 2, product.posZ);
    for (final face in faces) {
      final centerV = face.fold<Vec3>(Vec3.zero, (a, b) => a + b) / face.length.toDouble();
      final normal = _outwardFaceNormal(face, productCenter);
      final lighting = _computeFaceLighting(face, product.material);
      items.add(_RenderItem(
        verts: face,
        fillColor: Color.alphaBlend(
          Colors.white.withValues(alpha: lighting),
          fill,
        ),
        edgeColor: edge.withValues(alpha: 0.55),
        depth: proj.projectDepth(centerV),
        faceNormal: normal,
        cullBackFace: true,
        isOccluder: isOccluder,
      ));
    }
  }

  double _computeFaceLighting(List<Vec3> face, BaseMaterial material) {
    if (face.length < 3) return 0.0;
    final normal = (face[1] - face[0]).cross(face[2] - face[0]).normalized();
    final lightDir = const Vec3(0.45, 0.85, -0.35);
    final ndotl = normal.dot(lightDir.normalized()).clamp(0.0, 1.0);
    final base = 0.04 + material.conductivityFactor * 0.03;
    return (base + ndotl * 0.14).clamp(0.02, 0.18);
  }

  void _addProductFrameLines(List<_RenderItem> items, Proj3D proj, List<Vec3> v,
      {Color color = Colors.white38, ProductSettings? product}) {
    if (product != null) {
      if (product.shape == ProductShape.hollowBox) {
        _addFaceLoopLines(items, proj, _buildHollowBoxFaces(product), color: color);
        return;
      }
      if (product.shape == ProductShape.pipe) {
        _addFaceLoopLines(items, proj, _buildPipeFaces(product), color: color);
        return;
      }
    }
    _addBoxEdgeLines(items, proj, v, color: color);
  }

  void _addBoxItems(List<_RenderItem> items, Proj3D proj, List<Vec3> v,
      {required Color fill, required Color edge, bool isOccluder = true}) {
    final faces = [
      [v[0],v[1],v[2],v[3]], // 앞
      [v[5],v[4],v[7],v[6]], // 뒤
      [v[4],v[0],v[3],v[7]], // 좌
      [v[1],v[5],v[6],v[2]], // 우
      [v[3],v[2],v[6],v[7]], // 상
      [v[4],v[5],v[1],v[0]], // 하
    ];

    final boxCenter = v.fold<Vec3>(Vec3.zero, (a, b) => a + b) / v.length.toDouble();
    for (final face in faces) {
      final centerV = face.fold<Vec3>(Vec3.zero, (a, b) => a + b) / 4.0;
      items.add(_RenderItem(
        verts: face,
        fillColor: fill,
        edgeColor: edge,
        depth: proj.projectDepth(centerV),
        faceNormal: _outwardFaceNormal(face, boxCenter),
        cullBackFace: true,
        isOccluder: isOccluder,
      ));
    }
  }

  void _addFaceLoopLines(List<_RenderItem> items, Proj3D proj, List<List<Vec3>> faces,
      {Color color = Colors.white38}) {
    for (final face in faces) {
      if (face.length < 2) continue;
      for (int i = 0; i < face.length; i++) {
        final a = face[i];
        final b = face[(i + 1) % face.length];
        final d = proj.projectDepth((a + b) / 2.0);
        items.add(_RenderItem(
          verts: [a, b],
          fillColor: color,
          depth: d + 0.45,
          isEdgeOnly: true,
        ));
      }
    }
  }

  void _addBoxEdgeLines(List<_RenderItem> items, Proj3D proj, List<Vec3> v,
      {Color color = Colors.white38}) {
    final edges = [
      [v[0],v[1]], [v[1],v[2]], [v[2],v[3]], [v[3],v[0]],
      [v[4],v[5]], [v[5],v[6]], [v[6],v[7]], [v[7],v[4]],
      [v[0],v[4]], [v[1],v[5]], [v[2],v[6]], [v[3],v[7]],
    ];
    for (final e in edges) {
      final d = proj.projectDepth((e[0] + e[1]) / 2.0);
      items.add(_RenderItem(
        verts: [e[0], e[1]],
        fillColor: color,
        depth: d + 0.5,
        isEdgeOnly: true,
      ));
    }
  }

  // ----------------------------------------------------------
  // 3D 전기력선 렌더링
  // 깔끔한 노란색 계열 라인 + 자연스러운 베지어 곡선
  // 강도에 따른 투명도/두께 변화 (단색 노랑 기조)
  // ----------------------------------------------------------
  void _drawFieldLines(Canvas canvas, Proj3D proj,
      List<FieldLine> lines, double sl, List<_RenderItem> occluders) {
    if (lines.isEmpty) return;

    final preparedOccluders = <({Rect bounds, Path path, double depth})>[];
    for (final item in occluders) {
      if (item.verts.length < 3) continue;
      final itemPts = item.verts.map((v) => proj.project(v)).toList(growable: false);
      final path = Path()..moveTo(itemPts[0].dx, itemPts[0].dy);
      for (int i = 1; i < itemPts.length; i++) {
        path.lineTo(itemPts[i].dx, itemPts[i].dy);
      }
      path.close();
      preparedOccluders.add((
        bounds: _projectedBounds(itemPts),
        path: path,
        depth: item.depth,
      ));
    }

    final grouped = <int, List<FieldLine>>{};
    for (final line in lines) {
      grouped.putIfAbsent(line.anodeIndex, () => []).add(line);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    for (final key in sortedKeys) {
      grouped[key]!.sort((a, b) => b.intensity.compareTo(a.intensity));
    }

    final renderLines = <FieldLine>[];
    const quotaPerGroup = 24;
    for (final key in sortedKeys) {
      final group = grouped[key]!;
      final takeCount = math.min(group.length, quotaPerGroup);
      if (takeCount <= 0) continue;
      if (takeCount == 1) {
        renderLines.add(group.first);
        continue;
      }
      final usedIndices = <int>{};
      for (int i = 0; i < takeCount; i++) {
        final t = i / (takeCount - 1);
        final idx = (t * (group.length - 1)).round().clamp(0, group.length - 1);
        if (usedIndices.add(idx)) {
          renderLines.add(group[idx]);
        }
      }
    }

    final totalLines = renderLines.length;
    final step = totalLines > 140 ? (totalLines / 140).ceil() : 1;

    for (int li = 0; li < totalLines; li += step) {
      final line = renderLines[li];
      if (line.points.length < 3) continue;

      final sampledPts = <Vec3>[];
      final sampleStride = line.points.length > 72 ? (line.points.length / 72).ceil() : 1;
      for (int i = 0; i < line.points.length; i += sampleStride) {
        final pt = line.points[i];
        if (pt.y <= sl + 0.5) {
          sampledPts.add(pt);
        }
      }
      final lastPoint = line.points.last;
      if (lastPoint.y <= sl + 0.5 && (sampledPts.isEmpty || sampledPts.last != lastPoint)) {
        sampledPts.add(lastPoint);
      }
      if (sampledPts.length < 3) continue;

      final intens = line.intensity.clamp(0.0, 1.0);
      final isLeftAnode = line.anodeIndex.isEven;
      final r = 255;
      final g = isLeftAnode
          ? (188 + intens * 52).round().clamp(188, 240)
          : (214 + intens * 32).round().clamp(214, 246);
      final b = isLeftAnode
          ? (42 + intens * 28).round().clamp(42, 90)
          : (8 + intens * 18).round().clamp(8, 40);
      final alpha = (112 + intens * 108).round().clamp(112, 220);
      final sw = (1.2 + intens * 1.25).clamp(1.2, 2.45);

      final visiblePts = _filterVisibleFieldLinePoints(proj, sampledPts, preparedOccluders);
      if (visiblePts.length < 3) continue;

      final screenPts = _smoothProjectedPoints(
        visiblePts.map((v) => proj.project(v)).toList(growable: false),
      );
      if (screenPts.length < 3) continue;

      final path = _buildSmoothPath(screenPts);
      final lineColor = Color.fromARGB(alpha, r, g, b);
      canvas.drawPath(path, Paint()
        ..color = lineColor
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      if (intens > 0.40 && screenPts.length >= 4) {
        final midIdx = screenPts.length ~/ 2;
        final pm0 = screenPts[(midIdx - 1).clamp(0, screenPts.length - 1)];
        final pm1 = screenPts[midIdx.clamp(0, screenPts.length - 1)];
        if ((pm1 - pm0).distance > 4) {
          _drawArrow(
            canvas,
            pm0,
            pm1,
            Color.fromARGB((alpha * 0.95).round().clamp(100, 220), r, g, b),
            sw,
            4.6,
          );
        }
      }
    }
  }

  Vec3 _outwardFaceNormal(List<Vec3> face, Vec3 solidCenter) {
    final base = _computeFaceNormal(face);
    final faceCenter = face.fold<Vec3>(Vec3.zero, (a, b) => a + b) / face.length.toDouble();
    final outward = (faceCenter - solidCenter).normalized();
    return base.dot(outward) >= 0 ? base : -base;
  }

  Vec3 _outwardTriangleNormal(List<Vec3> face, Vec3 sourceNormal, Vec3 solidCenter) {
    final normalizedSource = sourceNormal.normalized();
    final fallback = normalizedSource.lengthSq < 1e-8 ? _computeFaceNormal(face) : normalizedSource;
    final faceCenter = face.fold<Vec3>(Vec3.zero, (a, b) => a + b) / face.length.toDouble();
    final outward = (faceCenter - solidCenter).normalized();
    return fallback.dot(outward) >= 0 ? fallback : -fallback;
  }


  List<Vec3> _filterVisibleFieldLinePoints(
    Proj3D proj,
    List<Vec3> points,
    List<({Rect bounds, Path path, double depth})> occluders,
  ) {
    if (points.length < 3 || occluders.isEmpty) {
      return points;
    }

    final visible = <Vec3>[];
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final mustKeep = i == 0 || i == points.length - 1;
      final hidden = _isOccludedBySolidPrepared(proj, pt, occluders);
      if (!hidden || mustKeep) {
        visible.add(pt);
      }
    }

    if (visible.length >= 3) {
      return visible;
    }
    return [points.first, points[points.length ~/ 2], points.last];
  }

  bool _isOccludedBySolidPrepared(
    Proj3D proj,
    Vec3 point,
    List<({Rect bounds, Path path, double depth})> occluders,
  ) {
    final screenPoint = proj.project(point);
    final pointDepth = proj.projectDepth(point);

    for (final item in occluders) {
      if (!item.bounds.inflate(0.5).contains(screenPoint)) continue;
      if (!item.path.contains(screenPoint)) continue;
      if (item.depth < pointDepth - 6.0) {
        return true;
      }
    }
    return false;
  }

  Rect _projectedBounds(List<Offset> pts) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final pt in pts) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy > maxY) maxY = pt.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<Offset> _smoothProjectedPoints(List<Offset> pts) {
    if (pts.length < 3) return pts;
    final smoothed = <Offset>[pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final next = pts[i + 1];
      smoothed.add(Offset(
        prev.dx * 0.20 + curr.dx * 0.60 + next.dx * 0.20,
        prev.dy * 0.20 + curr.dy * 0.60 + next.dy * 0.20,
      ));
    }
    smoothed.add(pts.last);
    return smoothed;
  }

  // 화면 좌표 포인트로 Catmull-Rom 스플라인 패스 구성
  Path _buildSmoothPath(List<Offset> pts) {
    if (pts.length < 2) return Path();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts.last.dx, pts.last.dy);
      return path;
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i < pts.length - 2 ? pts[i + 2] : pts[i + 1];
      // Catmull-Rom to cubic Bezier 변환
      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color, double sw,
      [double arrowSize = 5.0]) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1.0) return;
    final angle = math.atan2(dy, dx);
    final path = Path();
    path.moveTo(to.dx, to.dy);
    path.lineTo(to.dx - arrowSize * math.cos(angle - 0.45),
                to.dy - arrowSize * math.sin(angle - 0.45));
    path.moveTo(to.dx, to.dy);
    path.lineTo(to.dx - arrowSize * math.cos(angle + 0.45),
                to.dy - arrowSize * math.sin(angle + 0.45));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = sw
        ..style = PaintingStyle.stroke);
  }

  // ----------------------------------------------------------
  // 라벨 & 치수선
  // ----------------------------------------------------------
  void _drawLabels(Canvas canvas, Proj3D proj,
      TankSettings tank, AnodeSettings anode,
      List<ProductSettings> products,
      List<(Vec3, Vec3)> anodePositions, double sl) {

    // 양극 라벨
    for (int i = 0; i < anodePositions.length; i++) {
      final (center, _) = anodePositions[i];
      final topPt = proj.project(Vec3(center.x, center.y + anode.depth/2 + 3, center.z));
      final label = i % 2 == 0 ? '⊕L${i ~/ 2 + 1}' : '⊕R${i ~/ 2 + 1}';
      _text(canvas, topPt, label, const Color(0xFFFF8C00), 11);
    }

    // 제품 라벨
    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      final prodCY = product.posY + product.depth / 2;
      final prodTop = proj.project(Vec3(product.posX, prodCY + product.depth/2 + 4, product.posZ));
      _text(canvas, prodTop, '⊖P${i + 1}', Colors.lightBlueAccent, 11);
    }

    // 양극-제품 / 양극-양극 거리 표시
    if (anodePositions.isNotEmpty && products.isNotEmpty) {
      final refProduct = products.first;
      final refProdCenter = Vec3(
        refProduct.posX,
        refProduct.posY + refProduct.depth / 2,
        refProduct.posZ,
      );
      final refProdZ = refProduct.posZ;
      final distY = sl + 8;

      final leftAnodes = anodePositions.where((e) => e.$1.x <= refProdCenter.x).toList();
      final rightAnodes = anodePositions.where((e) => e.$1.x > refProdCenter.x).toList();

      if (leftAnodes.isNotEmpty) {
        final leftCenter = leftAnodes.reduce((a, b) => a.$1.x > b.$1.x ? a : b).$1;
        _drawDimLine(
          canvas,
          proj,
          Vec3(leftCenter.x, distY, refProdZ),
          Vec3(refProdCenter.x - refProduct.width / 2, distY, refProdZ),
          '좌 양극-제품: ${(refProdCenter.x - refProduct.width / 2 - leftCenter.x).abs().toStringAsFixed(0)}cm',
          const Color(0xFFFFCC80),
        );
      }

      if (rightAnodes.isNotEmpty) {
        final rightCenter = rightAnodes.reduce((a, b) => a.$1.x < b.$1.x ? a : b).$1;
        _drawDimLine(
          canvas,
          proj,
          Vec3(refProdCenter.x + refProduct.width / 2, distY, refProdZ),
          Vec3(rightCenter.x, distY, refProdZ),
          '우 양극-제품: ${(rightCenter.x - (refProdCenter.x + refProduct.width / 2)).abs().toStringAsFixed(0)}cm',
          const Color(0xFFFFE082),
        );
      }

      if (anodePositions.length >= 2) {
        final leftX = anodePositions.first.$1.x;
        final rightX = anodePositions.last.$1.x;
        _drawDimLine(canvas, proj,
            Vec3(leftX, distY + 6, refProdZ),
            Vec3(rightX, distY + 6, refProdZ),
            '양극간: ${(rightX - leftX).abs().toStringAsFixed(0)}cm',
            const Color(0xFFFFB74D));
      }
    }

    // 제품 간 거리 표시 (다수 제품)
    if (products.length >= 2) {
      for (int i = 0; i < products.length - 1; i++) {
        final p1 = products[i];
        final p2 = products[i + 1];
        final distBetween = (Vec3(p2.posX, p2.posY, p2.posZ) -
            Vec3(p1.posX, p1.posY, p1.posZ)).length;
        final midPt = Vec3(
          (p1.posX + p2.posX) / 2,
          math.max(p1.posY + p1.depth, p2.posY + p2.depth) + 5,
          (p1.posZ + p2.posZ) / 2,
        );
        _text(canvas, proj.project(midPt),
          '제품간: ${distBetween.toStringAsFixed(0)}cm',
          Colors.cyanAccent.withValues(alpha: 0.7), 9);
      }
    }

    // 용액 수위 표시
    final slLabel = proj.project(Vec3(tank.width/2 + 3, sl, -tank.length/2));
    _text(canvas, slLabel, '수위 ${sl.toStringAsFixed(0)}cm', const Color(0x99AADDFF), 10);
  }

  void _drawDimLine(Canvas canvas, Proj3D proj, Vec3 from, Vec3 to, String label, Color color) {
    final p0 = proj.project(from);
    final p1 = proj.project(to);
    final paint = Paint()..color = color.withValues(alpha: 0.7)..strokeWidth = 1.0;
    canvas.drawLine(p0, p1, paint);
    canvas.drawLine(Offset(p0.dx, p0.dy-4), Offset(p0.dx, p0.dy+4), paint);
    canvas.drawLine(Offset(p1.dx, p1.dy-4), Offset(p1.dx, p1.dy+4), paint);
    _text(canvas, Offset((p0.dx+p1.dx)/2, (p0.dy+p1.dy)/2-10), label, color, 10);
  }

  // ----------------------------------------------------------
  // 좌표축
  // ----------------------------------------------------------
  void _drawAxes(Canvas canvas, Proj3D proj, double len) {
    final o = const Vec3(0, 0, 0);
    for (final (end, color, label) in [
      (Vec3(len, 0, 0), Colors.red,   'X 폭'),
      (Vec3(0, len, 0), Colors.green, 'Y 깊이'),
      (Vec3(0, 0, len), Colors.blue,  'Z 길이'),
    ]) {
      final p0 = proj.project(o);
      final p1 = proj.project(end);
      canvas.drawLine(p0, p1, Paint()..color = color..strokeWidth = 2.0
        ..style = PaintingStyle.stroke);
      _text(canvas, p1 + const Offset(4, -4), label, color, 10);
    }
  }

  // ----------------------------------------------------------
  // 도금 두께 범례
  // ----------------------------------------------------------
  void _drawThicknessLegend(Canvas canvas, Size size, List<ThicknessPoint> pts) {
    final active = pts.where((p2) => p2.inSolution && !p2.isMasked).toList();
    if (active.isEmpty) return;

    final minT = active.map((p2) => p2.thickness).reduce(math.min);
    final maxT = active.map((p2) => p2.thickness).reduce(math.max);
    final avgT = active.map((p2) => p2.thickness).reduce((a, b) => a + b) / active.length;

    const bw = 14.0, bh = 100.0;
    final bx = size.width - 70.0, by = size.height - bh - 50.0;

    // 범례 배경
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx - 4, by - 16, 65, bh + 36), const Radius.circular(6)),
      Paint()..color = const Color(0xAA000000),
    );

    final rect = Rect.fromLTWH(bx, by, bw, bh);
    canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(
      Offset(bx, by + bh), Offset(bx, by),
      [const Color(0xFF0000FF), const Color(0xFF00FF00),
       const Color(0xFFFFFF00), const Color(0xFFFF0000)],
      [0.0, 0.33, 0.67, 1.0],
    ));
    canvas.drawRect(rect, Paint()
      ..color = Colors.white38..strokeWidth = 0.8..style = PaintingStyle.stroke);

    _text(canvas, Offset(bx - 4, by - 14), '도금두께(µm)', Colors.white70, 8);
    _text(canvas, Offset(bx + bw + 3, by - 4), maxT.toStringAsFixed(2), Colors.red, 9);
    _text(canvas, Offset(bx + bw + 3, by + bh/2 - 5), avgT.toStringAsFixed(2), Colors.greenAccent, 8);
    _text(canvas, Offset(bx + bw + 3, by + bh - 4), minT.toStringAsFixed(2), Colors.blueAccent, 9);
    _text(canvas, Offset(bx - 4, by + bh + 4), 'avg:${avgT.toStringAsFixed(2)}µm', Colors.white60, 8);
  }

  // ----------------------------------------------------------
  // 전기장 강도 범례
  // ----------------------------------------------------------
  void _drawFieldStrengthLegend(Canvas canvas, Size size, List<FieldStrengthPoint> pts) {
    final active = pts.where((p2) => p2.inSolution && p2.strength > 0).toList();
    if (active.isEmpty) return;

    // minS/maxS used for legend context (implicitly via gradient shader)
    // ignore: unused_local_variable

    const bw = 14.0, bh = 100.0;
    final bx = size.width - 70.0, by = size.height - bh - 50.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx - 4, by - 16, 65, bh + 36), const Radius.circular(6)),
      Paint()..color = const Color(0xAA000000),
    );

    final rect = Rect.fromLTWH(bx, by, bw, bh);
    canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(
      Offset(bx, by + bh), Offset(bx, by),
      [const Color(0xFF6400C8), const Color(0xFFFF00FF), const Color(0xFFFFFFFF)],
      [0.0, 0.5, 1.0],
    ));
    canvas.drawRect(rect, Paint()
      ..color = Colors.white38..strokeWidth = 0.8..style = PaintingStyle.stroke);

    _text(canvas, Offset(bx - 4, by - 14), '전기장강도', Colors.white70, 8);
    _text(canvas, Offset(bx + bw + 3, by - 4), 'High', Colors.white, 9);
    _text(canvas, Offset(bx + bw + 3, by + bh - 4), 'Low', Colors.purpleAccent, 9);
    _text(canvas, Offset(bx - 4, by + bh + 4), '분포 컬러맵', Colors.white60, 8);
  }

  // ----------------------------------------------------------
  // 오버레이 정보
  // ----------------------------------------------------------
  void _drawOverlayInfo(Canvas canvas, Size size, PlatingProvider p) {
    final modeLabel = p.heatmapMode == HeatmapMode.thickness ? '두께맵' : '전기장맵';
    _text(canvas, Offset(10, size.height - 20),
        'Zoom: ${p.zoom.toStringAsFixed(2)}x  |  제품: ${p.productCount}개  |  '
        '표면적: ${p.totalSurfaceAreaDm2.toStringAsFixed(2)} dm²  |  모드: $modeLabel',
        Colors.white30, 10);
  }

  void _text(Canvas canvas, Offset pos, String text, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: color, fontSize: fs, fontWeight: FontWeight.w500,
        shadows: const [Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(1,1))],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant PlatingScene3DPainter oldDelegate) => true;
}

// ============================================================
// 배경 그리드
// ============================================================
class GridBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1.0;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ============================================================
// 2D 전기력선 CustomPainter
// mode=top  → 위에서 내려본 (XZ 평면): X=가로, Z=세로
// mode=side → 옆에서 바라본 (XY 평면): X=가로, Y=세로
// ============================================================
class FieldLine2DPainter extends CustomPainter {
  final PlatingProvider p;
  final FieldLine2DMode mode;

  FieldLine2DPainter({required this.p, required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final tank   = p.tank;
    final anode  = p.anode;
    final products = p.products;
    final fieldLines = p.fieldLines;
    final sl = tank.solutionLevel;

    // 뷰 범위 결정
    final viewW = tank.width;
    final viewH = mode == FieldLine2DMode.top ? tank.length : sl;

    final scaleX = size.width  * 0.88 / viewW.clamp(1.0, 100000.0);
    final scaleY = size.height * 0.88 / viewH.clamp(1.0, 100000.0);
    final offsetX = size.width  * 0.06;
    final offsetY = mode == FieldLine2DMode.top ? size.height * 0.06 : size.height * 0.94;

    // 2D 프로젝션
    Offset proj2D(Vec3 v) {
      if (mode == FieldLine2DMode.top) {
        // 위에서 내려본: XZ 평면 (X→가로, Z→세로, Y 무시)
        return Offset(
          offsetX + (v.x + viewW / 2) * scaleX,
          offsetY + (v.z + tank.length / 2) * scaleY,
        );
      } else {
        // 옆에서 바라본: XY 평면 (X→가로, Y→세로 아래→위)
        return Offset(
          offsetX + (v.x + viewW / 2) * scaleX,
          offsetY - v.y * scaleY,
        );
      }
    }

    // 배경
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF060C18));

    // 그리드선
    _drawGrid(canvas, size, offsetX, offsetY, scaleX, scaleY, viewW, viewH, sl);

    // 탱크 외곽선
    _drawTankOutline(canvas, proj2D, tank, sl);

    // 양극 위치
    final anodePositions = PlatingSimulationService.getAnodePositionsMulti(
      tank: tank, anode: anode, products: products,
    );
    _drawAnodes2D(canvas, proj2D, anode, anodePositions, sl);

    // 제품 윤곽
    for (int i = 0; i < products.length; i++) {
      _drawProduct2D(canvas, proj2D, products[i], i);
    }

    // 전기력선
    if (fieldLines.isNotEmpty) {
      _drawFieldLines2D(canvas, proj2D, fieldLines, sl);
    }

    // 범례 라벨
    _drawLabels2D(canvas, size, mode);
  }

  void _drawGrid(Canvas canvas, Size size, double ox, double oy,
      double sx, double sy, double vw, double vh, double sl) {
    final gPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    const step = 10.0;
    for (double x = -vw/2; x <= vw/2; x += step) {
      final px = ox + (x + vw/2) * sx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), gPaint);
    }
    if (mode == FieldLine2DMode.top) {
      for (double z = -vh/2; z <= vh/2; z += step) {
        final py = oy + (z + vh/2) * sy;
        canvas.drawLine(Offset(0, py), Offset(size.width, py), gPaint);
      }
    } else {
      for (double y = 0; y <= sl; y += step) {
        final py = oy - y * sy;
        canvas.drawLine(Offset(0, py), Offset(size.width, py), gPaint);
      }
    }
  }

  void _drawTankOutline(Canvas canvas, Offset Function(Vec3) proj, TankSettings tank, double sl) {
    final paint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (mode == FieldLine2DMode.top) {
      // XZ 사각형
      final tl = proj(Vec3(-tank.width/2, 0, -tank.length/2));
      final tr = proj(Vec3( tank.width/2, 0, -tank.length/2));
      final br = proj(Vec3( tank.width/2, 0,  tank.length/2));
      final bl = proj(Vec3(-tank.width/2, 0,  tank.length/2));
      canvas.drawPath(Path()..moveTo(tl.dx,tl.dy)..lineTo(tr.dx,tr.dy)
        ..lineTo(br.dx,br.dy)..lineTo(bl.dx,bl.dy)..close(), paint);
    } else {
      // XY 사각형 (용액 수위까지)
      final tl = proj(Vec3(-tank.width/2, sl, 0));
      final tr = proj(Vec3( tank.width/2, sl, 0));
      final br = proj(Vec3( tank.width/2,  0, 0));
      final bl = proj(Vec3(-tank.width/2,  0, 0));
      canvas.drawPath(Path()..moveTo(tl.dx,tl.dy)..lineTo(tr.dx,tr.dy)
        ..lineTo(br.dx,br.dy)..lineTo(bl.dx,bl.dy)..close(), paint);
      // 용액면
      final sLine = Paint()..color = const Color(0x6600B4D8)..strokeWidth = 1.5;
      canvas.drawLine(tl, tr, sLine);
    }
  }

  void _drawAnodes2D(Canvas canvas, Offset Function(Vec3) proj,
      AnodeSettings anode, List<(Vec3, Vec3)> positions, double sl) {
    final paint = Paint()
      ..color = const Color(0xCCFF8C00)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFFF6500)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < positions.length; i++) {
      final (center, _) = positions[i];
      Rect rect;
      if (mode == FieldLine2DMode.top) {
        final tl = proj(Vec3(center.x - anode.width/2, 0, center.z - anode.length/2));
        final br = proj(Vec3(center.x + anode.width/2, 0, center.z + anode.length/2));
        rect = Rect.fromLTRB(math.min(tl.dx, br.dx), math.min(tl.dy, br.dy), math.max(tl.dx, br.dx), math.max(tl.dy, br.dy));
      } else {
        final yBot = (center.y - anode.depth/2).clamp(0.0, sl);
        final yTop = (center.y + anode.depth/2).clamp(0.0, sl);
        final tl = proj(Vec3(center.x - anode.width/2, yTop, 0));
        final br = proj(Vec3(center.x + anode.width/2, yBot, 0));
        rect = Rect.fromLTRB(math.min(tl.dx, br.dx), math.min(tl.dy, br.dy), math.max(tl.dx, br.dx), math.max(tl.dy, br.dy));
      }
      if (rect.width < 2) rect = rect.inflate(2);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
      final labelPt = rect.topCenter + const Offset(0, -12);
      _text2D(canvas, labelPt, i % 2 == 0 ? '⊕L' : '⊕R', const Color(0xFFFF8C00), 9);
    }
  }

  void _drawProduct2D(Canvas canvas, Offset Function(Vec3) proj,
      ProductSettings prod, int idx) {
    final paint = Paint()
      ..color = const Color(0x5500B4D8)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    Rect rect;
    final cy = prod.posY + prod.depth / 2;
    if (mode == FieldLine2DMode.top) {
      final tl = proj(Vec3(prod.posX - prod.width/2, 0, prod.posZ - prod.length/2));
      final br = proj(Vec3(prod.posX + prod.width/2, 0, prod.posZ + prod.length/2));
      rect = Rect.fromLTRB(math.min(tl.dx, br.dx), math.min(tl.dy, br.dy), math.max(tl.dx, br.dx), math.max(tl.dy, br.dy));
    } else {
      final tl = proj(Vec3(prod.posX - prod.width/2, cy + prod.depth/2, 0));
      final br = proj(Vec3(prod.posX + prod.width/2, cy - prod.depth/2, 0));
      rect = Rect.fromLTRB(math.min(tl.dx, br.dx), math.min(tl.dy, br.dy), math.max(tl.dx, br.dx), math.max(tl.dy, br.dy));
    }
    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, border);
    _text2D(canvas, rect.topCenter + const Offset(-8, -13), '⊖P${idx+1}', Colors.lightBlueAccent, 9);
  }

  // 2D 전기장 시각화 — Streamline (유선) 스타일
  // 양극→제품 방향의 전기력선을 부드러운 곡선 선으로 표현
  // 강도별 색상(파랑→청록→녹→노랑→주황→빨강) + 방향 화살표
  // 배경에 미세한 컬러 영역으로 필드 세기 분포 표시
  void _drawFieldLines2D(Canvas canvas, Offset Function(Vec3) proj,
      List<FieldLine> lines, double sl) {
    if (lines.isEmpty) return;

    // ── Step 1: 배경 필드 세기 영역 (매우 연한 컬러맵) ──────────
    // 강도 높은 영역만 매우 연하게 표시하여 배경 참고용으로 활용
    final allPts = <(Offset, double)>[];
    for (final line in lines) {
      if (line.points.isEmpty) continue;
      for (final pt3d in line.points.where((pt) => pt.y <= sl + 0.5)) {
        allPts.add((proj(pt3d), line.intensity));
      }
    }

    if (allPts.isNotEmpty) {
      // 강한 필드 영역만 매우 연하게 배경 표시
      final bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28.0);
      for (final (pt, intens) in allPts) {
        if (intens < 0.5) continue; // 강한 필드만
        final Color c;
        if (intens < 0.7) {
          c = Color.fromARGB(12, 0, 200, 255);
        } else if (intens < 0.85) {
          c = Color.fromARGB(15, 100, 230, 0);
        } else {
          c = Color.fromARGB(18, 255, 180, 0);
        }
        canvas.drawCircle(pt, 22.0, bgPaint..color = c);
      }
    }

    // ── Step 2: 전기력선 스트림라인 (핵심) ──────────────────────
    // 각 FieldLine을 2D 투영 후 부드러운 Catmull-Rom 곡선으로 표현
    // 강도순 정렬: 약한 것 먼저 (강한 것이 위에 그려짐)
    final sorted = List<FieldLine>.from(lines)
      ..sort((a, b) => a.intensity.compareTo(b.intensity));

    // 서브샘플링: 최대 120개 라인
    final totalLines = sorted.length;
    final step = totalLines > 120 ? (totalLines / 120).ceil() : 1;

    for (int li = 0; li < totalLines; li += step) {
      final line = sorted[li];
      if (line.points.length < 3) continue;
      final validPts = line.points.where((pt) => pt.y <= sl + 0.5).toList();
      if (validPts.length < 3) continue;

      final intens = line.intensity.clamp(0.0, 1.0);

      // 강도별 색상 (파랑→청록→녹색→노랑→주황→빨강)
      final Color lineCol;
      if (intens < 0.2) {
        final u = intens / 0.2;
        lineCol = Color.fromARGB((70 + u*30).round(), 30, (120+u*135).round(), 255);
      } else if (intens < 0.4) {
        final u = (intens - 0.2) / 0.2;
        lineCol = Color.fromARGB((90 + u*20).round(), (u*50).round(), 230, (255-u*255).round());
      } else if (intens < 0.6) {
        final u = (intens - 0.4) / 0.2;
        lineCol = Color.fromARGB((100 + u*20).round(), (50+u*150).round(), 230, 0);
      } else if (intens < 0.8) {
        final u = (intens - 0.6) / 0.2;
        lineCol = Color.fromARGB((115 + u*25).round(), 220, (230-u*80).round(), 0);
      } else {
        final u = (intens - 0.8) / 0.2;
        lineCol = Color.fromARGB((130 + u*50).round(), 255, (150-u*100).round(), 0);
      }

      final sw = (0.8 + intens * 1.4).clamp(0.8, 2.2);

      // 2D 투영 포인트
      final pts2d = validPts.map((v) => proj(v)).toList();

      // Catmull-Rom 스플라인으로 부드러운 경로
      final path = Path()..moveTo(pts2d.first.dx, pts2d.first.dy);
      for (int i = 0; i < pts2d.length - 1; i++) {
        final p0 = i > 0 ? pts2d[i-1] : pts2d[i];
        final p1 = pts2d[i];
        final p2 = pts2d[i+1];
        final p3 = i < pts2d.length - 2 ? pts2d[i+2] : pts2d[i+1];
        final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;
        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }

      canvas.drawPath(path, Paint()
        ..color = lineCol
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      // ── 방향 화살표: 강도 0.3 이상, 중간 지점 ──────────────
      if (intens > 0.3 && pts2d.length >= 4) {
        final midIdx = pts2d.length ~/ 2;
        final pm0 = pts2d[midIdx - 1];
        final pm1 = pts2d[midIdx];
        if ((pm1 - pm0).distance > 5) {
          _drawArrow2D(canvas, pm0, pm1, lineCol.withValues(alpha: 0.9), sw);
        }
      }
    }

    // ── Step 3: 강도 구간별 레전드 컬러바 (우측 하단) ─────────
    // (레전드는 _drawLabels2D에서 처리하므로 여기선 생략)
  }
  void _drawArrow2D(Canvas canvas, Offset from, Offset to, Color color, double sw) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final angle = math.atan2(dy, dx);
    const size = 5.0;
    final path = Path();
    path.moveTo(to.dx, to.dy);
    path.lineTo(to.dx - size * math.cos(angle - 0.45), to.dy - size * math.sin(angle - 0.45));
    path.moveTo(to.dx, to.dy);
    path.lineTo(to.dx - size * math.cos(angle + 0.45), to.dy - size * math.sin(angle + 0.45));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = sw..style = PaintingStyle.stroke);
  }

  void _drawLabels2D(Canvas canvas, Size size, FieldLine2DMode mode) {
    final modeStr = mode == FieldLine2DMode.top ? '위에서 내려본 뷰 (XZ 평면)' : '옆에서 바라본 뷰 (XY 단면)';
    final xLabel  = 'X→ (폭)';
    final yLabel  = mode == FieldLine2DMode.top ? 'Z→ (길이)' : 'Y↑ (깊이)';

    final bg = Paint()..color = Colors.black54;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(6, 6, 220, 22), const Radius.circular(4)), bg);
    _text2D(canvas, const Offset(10, 9), '2D 전기력선 — $modeStr', Colors.cyanAccent, 9);
    _text2D(canvas, Offset(size.width - 50, size.height - 18), xLabel, Colors.white38, 8);
    _text2D(canvas, Offset(4, size.height / 2), yLabel, Colors.white38, 8);
  }

  void _text2D(Canvas canvas, Offset pos, String text, Color color, double fs) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: color, fontSize: fs, fontWeight: FontWeight.w500,
        shadows: const [Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(1,1))],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant FieldLine2DPainter old) => true;
}
