import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/plating_models.dart';
import '../services/simulation_service.dart';

// 히트맵 표시 모드
enum HeatmapMode {
  thickness,    // 도금 두께 (µm)
  fieldStrength, // 전기장 강도 분포
}

// 2D 전기력선 뷰 모드
enum FieldLine2DMode {
  none,   // 3D 뷰 (기본)
  top,    // 위에서 내려본 (XZ 평면)
  side,   // 옆에서 바라본 (XY 평면)
}

class _ParsedStlPreview {
  final int triangleCount;
  final int vertexCount;
  final List<Vec3> previewVertices;
  final List<CadTriangle> triangles;
  final double boundWidth;
  final double boundDepth;
  final double boundLength;

  const _ParsedStlPreview({
    required this.triangleCount,
    required this.vertexCount,
    required this.previewVertices,
    required this.triangles,
    required this.boundWidth,
    required this.boundDepth,
    required this.boundLength,
  });
}

class PlatingProvider extends ChangeNotifier {
  TankSettings _tank = TankSettings();
  AnodeSettings _anode = AnodeSettings();
  // 다수 제품 지원
  List<ProductSettings> _products = [ProductSettings()];
  int _selectedProductIndex = 0;
  ElectricalSettings _elec = ElectricalSettings();
  List<MaskingZone> _maskingZones = [];

  List<FieldLine> _fieldLines = [];
  List<ThicknessPoint> _thicknessPoints = [];
  List<FieldStrengthPoint> _fieldStrengthPoints = [];
  AnalysisResult? _analysisResult;

  bool _isSimulating = false;
  bool _showFieldLines = true;
  bool _showHeatmap = true;
  bool _showTank = true;
  bool _showSolution = true;
  bool _showAnodes = true;          // 양극 숨김/표시
  int _selectedTab = 0;
  HeatmapMode _heatmapMode = HeatmapMode.thickness;
  FieldLine2DMode _fieldLine2DMode = FieldLine2DMode.none; // 2D 전기력선 모드

  // 3D 뷰 파라미터
  double _rotX = -14.0;
  double _rotY = -34.0;
  double _zoom = 1.55;
  double _panX = 0.0;
  double _panY = -14.0;

  // getters
  TankSettings get tank => _tank;
  AnodeSettings get anode => _anode;
  // 단일 제품 하위 호환 getter
  ProductSettings get product => _products.isNotEmpty
      ? _products[_selectedProductIndex.clamp(0, _products.length - 1)]
      : ProductSettings();
  List<ProductSettings> get products => List.unmodifiable(_products);
  int get selectedProductIndex => _selectedProductIndex;
  int get productCount => _products.length;
  ElectricalSettings get elec => _elec;
  List<MaskingZone> get maskingZones => List.unmodifiable(_maskingZones);
  List<FieldLine> get fieldLines => _fieldLines;
  List<ThicknessPoint> get thicknessPoints => _thicknessPoints;
  List<FieldStrengthPoint> get fieldStrengthPoints => _fieldStrengthPoints;
  AnalysisResult? get analysisResult => _analysisResult;
  bool get isSimulating => _isSimulating;
  bool get showFieldLines => _showFieldLines;
  bool get showHeatmap => _showHeatmap;
  bool get showTank => _showTank;
  bool get showSolution => _showSolution;
  bool get showAnodes => _showAnodes;
  int get selectedTab => _selectedTab;
  HeatmapMode get heatmapMode => _heatmapMode;
  FieldLine2DMode get fieldLine2DMode => _fieldLine2DMode;
  double get rotX => _rotX;
  double get rotY => _rotY;
  double get zoom => _zoom;
  double get panX => _panX;
  double get panY => _panY;

  // 총 표면적 (dm²)
  double get totalSurfaceAreaDm2 {
    double total = 0;
    for (final p in _products) {
      total += p.surfaceAreaDm2;
    }
    return total;
  }

  // --- 탱크 업데이트 ---
  void updateTank(TankSettings s) {
    _tank = s;
    if (_tank.solutionLevel > _tank.depth) {
      _tank = _tank.copyWith(solutionLevel: _tank.depth);
    }
    notifyListeners();
  }

  void updateAnode(AnodeSettings s) { _anode = s; notifyListeners(); }

  // --- 단일 제품 업데이트 (선택된 제품) ---
  void updateProduct(ProductSettings s) {
    if (_products.isEmpty) return;
    final idx = _selectedProductIndex.clamp(0, _products.length - 1);
    final updated = List<ProductSettings>.from(_products);
    updated[idx] = s;
    _products = updated;
    notifyListeners();
  }

  // --- 특정 인덱스 제품 업데이트 ---
  void updateProductAt(int index, ProductSettings s) {
    if (index < 0 || index >= _products.length) return;
    final updated = List<ProductSettings>.from(_products);
    updated[index] = s;
    _products = updated;
    notifyListeners();
  }

  void updateProductMaterial(int index, BaseMaterial material) {
    if (index < 0 || index >= _products.length) return;
    final target = _products[index];
    updateProductAt(index, target.copyWith(material: material));
  }

  String? attachCadFile({
    required int index,
    required String fileName,
    required String fileType,
    Uint8List? bytes,
  }) {
    if (index < 0 || index >= _products.length) {
      return '잘못된 제품 인덱스입니다.';
    }

    try {
      final product = _products[index];
      final normalizedType = fileType.trim().toUpperCase();
      final isStl = normalizedType == 'STL';
      final isStep = normalizedType == 'STEP' || normalizedType == 'STP';
      final isIges = normalizedType == 'IGES' || normalizedType == 'IGS';

      var cadImport = CadImportData(
        fileName: fileName,
        fileType: normalizedType,
        isImported: true,
        importedAt: DateTime.now(),
        summary: '$fileName 파일이 첨부되어 제품 형상 참조 상태로 반영되었습니다.',
      );

      var nextProduct = product;
      if (isStl) {
        if (bytes == null || bytes.isEmpty) {
          return 'STL 파일 데이터를 읽지 못했습니다.';
        }

        final parsed = _parseStlPreview(bytes);
        if (parsed == null) {
          return 'STL 파일 파싱에 실패했습니다. ASCII/Binary STL 형식인지 확인해 주세요.';
        }

        final safeWidth = parsed.boundWidth.clamp(1.0, _tank.width).toDouble();
        final safeDepth = parsed.boundDepth.clamp(1.0, _tank.depth).toDouble();
        final safeLength = parsed.boundLength.clamp(1.0, _tank.length).toDouble();
        nextProduct = product.copyWith(
          width: safeWidth,
          depth: safeDepth,
          length: safeLength,
        );
        cadImport = cadImport.copyWith(
          triangleCount: parsed.triangleCount,
          vertexCount: parsed.vertexCount,
          previewVertices: parsed.previewVertices,
          triangles: parsed.triangles,
          boundWidth: parsed.boundWidth,
          boundDepth: parsed.boundDepth,
          boundLength: parsed.boundLength,
          summary:
              '$fileName STL 파일이 첨부되었습니다. 메시 미리보기 ${parsed.previewVertices.length}점, 삼각형 ${parsed.triangleCount}개를 읽었고 외곽 치수 ${parsed.boundWidth.toStringAsFixed(1)}×${parsed.boundDepth.toStringAsFixed(1)}×${parsed.boundLength.toStringAsFixed(1)} cm 로 제품 형상에 반영했습니다.',
        );
      } else if (isStep || isIges) {
        cadImport = cadImport.copyWith(
          summary:
              '$fileName $normalizedType 파일이 첨부되었습니다. 현재 버전에서는 STEP/IGES 원본 메시 파싱 대신 CAD 참조 상태로 저장되며, 제품 형상 보정과 표면적 계산에 반영됩니다.',
        );
      } else {
        return '지원하지 않는 CAD 형식입니다: $normalizedType';
      }

      final updated = nextProduct.copyWith(cadImport: cadImport);
      final products = List<ProductSettings>.from(_products);
      products[index] = updated;
      _products = products;
      notifyListeners();
      return null;
    } catch (e, st) {
      debugPrint('attachCadFile error: $e');
      debugPrint('$st');
      return 'CAD 처리 중 오류가 발생했습니다: $e';
    }
  }

  _ParsedStlPreview? _parseStlPreview(Uint8List bytes) {
    try {
      final ascii = String.fromCharCodes(bytes.take(math.min(bytes.length, 5000)));
      if (ascii.trimLeft().startsWith('solid')) {
        return _parseAsciiStl(bytes);
      }
      return _parseBinaryStl(bytes);
    } catch (e) {
      debugPrint('STL parse error: $e');
      return null;
    }
  }

  _ParsedStlPreview? _parseAsciiStl(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    final matches = RegExp(r'vertex\s+([-+0-9eE\.]+)\s+([-+0-9eE\.]+)\s+([-+0-9eE\.]+)')
        .allMatches(text)
        .toList();
    if (matches.isEmpty) return null;

    final verts = <Vec3>[];
    final rawTriangles = <({Vec3 a, Vec3 b, Vec3 c})>[];
    double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity, maxZ = double.negativeInfinity;

    for (int i = 0; i + 2 < matches.length; i += 3) {
      final triVerts = <Vec3>[];
      for (int j = 0; j < 3; j++) {
        final m = matches[i + j];
        final x = double.tryParse(m.group(1) ?? '') ?? 0.0;
        final y = double.tryParse(m.group(2) ?? '') ?? 0.0;
        final z = double.tryParse(m.group(3) ?? '') ?? 0.0;
        final v = Vec3(x, y, z);
        triVerts.add(v);
        verts.add(v);
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        minZ = math.min(minZ, z);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        maxZ = math.max(maxZ, z);
      }
      rawTriangles.add((a: triVerts[0], b: triVerts[1], c: triVerts[2]));
    }

    return _normalizeStlPreview(
      verts,
      rawTriangles: rawTriangles,
      triangleCount: rawTriangles.length,
      vertexCount: verts.length,
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }

  _ParsedStlPreview? _parseBinaryStl(Uint8List bytes) {
    if (bytes.length < 84) return null;
    final data = ByteData.sublistView(bytes);
    final triCount = data.getUint32(80, Endian.little);
    if (triCount == 0) return null;

    final verts = <Vec3>[];
    final rawTriangles = <({Vec3 a, Vec3 b, Vec3 c})>[];
    double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity, maxZ = double.negativeInfinity;
    var offset = 84;

    for (int i = 0; i < triCount; i++) {
      if (offset + 50 > bytes.length) break;
      offset += 12;
      final triVerts = <Vec3>[];
      for (int v = 0; v < 3; v++) {
        final x = data.getFloat32(offset, Endian.little);
        final y = data.getFloat32(offset + 4, Endian.little);
        final z = data.getFloat32(offset + 8, Endian.little);
        offset += 12;
        final vertex = Vec3(x, y, z);
        triVerts.add(vertex);
        verts.add(vertex);
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        minZ = math.min(minZ, z);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        maxZ = math.max(maxZ, z);
      }
      rawTriangles.add((a: triVerts[0], b: triVerts[1], c: triVerts[2]));
      offset += 2;
    }
    if (verts.isEmpty) return null;

    return _normalizeStlPreview(
      verts,
      rawTriangles: rawTriangles,
      triangleCount: rawTriangles.length,
      vertexCount: verts.length,
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }

  _ParsedStlPreview _normalizeStlPreview(
    List<Vec3> verts, {
    required List<({Vec3 a, Vec3 b, Vec3 c})> rawTriangles,
    required int triangleCount,
    required int vertexCount,
    required double minX,
    required double minY,
    required double minZ,
    required double maxX,
    required double maxY,
    required double maxZ,
  }) {
    final width = math.max(1.0, maxX - minX);
    final depth = math.max(1.0, maxY - minY);
    final length = math.max(1.0, maxZ - minZ);
    final center = Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
    final scale = 1.0;
    final sampled = <Vec3>[];
    final step = verts.length > 1200 ? (verts.length / 1200).ceil() : 1;
    for (int i = 0; i < verts.length; i += step) {
      final v = verts[i];
      sampled.add(Vec3(
        (v.x - center.x) * scale,
        (v.y - center.y) * scale,
        (v.z - center.z) * scale,
      ));
    }

    final normalizedTriangles = <CadTriangle>[];
    final triangleStep = rawTriangles.length > 2400 ? (rawTriangles.length / 2400).ceil() : 1;
    for (int i = 0; i < rawTriangles.length; i += triangleStep) {
      final tri = rawTriangles[i];
      final a = Vec3((tri.a.x - center.x) * scale, (tri.a.y - center.y) * scale, (tri.a.z - center.z) * scale);
      final b = Vec3((tri.b.x - center.x) * scale, (tri.b.y - center.y) * scale, (tri.b.z - center.z) * scale);
      final c = Vec3((tri.c.x - center.x) * scale, (tri.c.y - center.y) * scale, (tri.c.z - center.z) * scale);
      final normal = ((b - a).cross(c - a)).normalized();
      normalizedTriangles.add(CadTriangle(a: a, b: b, c: c, normal: normal));
    }

    return _ParsedStlPreview(
      triangleCount: triangleCount,
      vertexCount: vertexCount,
      previewVertices: sampled,
      triangles: normalizedTriangles,
      boundWidth: width,
      boundDepth: depth,
      boundLength: length,
    );
  }

  // --- 제품 추가 ---
  void addProduct() {
    if (_products.length >= 10) return; // 최대 10개
    final lastProduct = _products.last;
    // 마지막 제품에서 Z축으로 간격을 두고 배치
    final newPosZ = lastProduct.posZ + lastProduct.length + 10.0;
    final newProduct = ProductSettings(
      width: lastProduct.width,
      depth: lastProduct.depth,
      length: lastProduct.length,
      posX: lastProduct.posX,
      posY: lastProduct.posY,
      posZ: newPosZ,
      shape: lastProduct.shape,
      wallThickness: lastProduct.wallThickness,
    );
    _products = [..._products, newProduct];
    _selectedProductIndex = _products.length - 1;
    notifyListeners();
  }

  // --- 제품 제거 ---
  void removeProduct(int index) {
    if (_products.length <= 1) return; // 최소 1개
    final updated = List<ProductSettings>.from(_products);
    updated.removeAt(index);
    _products = updated;
    if (_selectedProductIndex >= _products.length) {
      _selectedProductIndex = _products.length - 1;
    }
    notifyListeners();
  }

  // --- 선택 제품 변경 ---
  void selectProduct(int index) {
    if (index < 0 || index >= _products.length) return;
    _selectedProductIndex = index;
    notifyListeners();
  }

  // --- 레고 피스 관리 ---
  void addLegoPiece(int productIndex) {
    if (productIndex < 0 || productIndex >= _products.length) return;
    final product = _products[productIndex];
    final pieceId = DateTime.now().microsecondsSinceEpoch.toString();
    final newPiece = LegoPiece(
      id: pieceId,
      width: 10.0, height: 10.0, length: 10.0,
      offsetX: 0, offsetY: 0,
      offsetZ: product.legoPieces.length * 12.0,
    );
    updateProductAt(productIndex, product.copyWith(
      legoPieces: [...product.legoPieces, newPiece],
    ));
  }

  void updateLegoPiece(int productIndex, String pieceId, LegoPiece updated) {
    if (productIndex < 0 || productIndex >= _products.length) return;
    final product = _products[productIndex];
    final pieces = product.legoPieces
        .map((p) => p.id == pieceId ? updated : p)
        .toList();
    updateProductAt(productIndex, product.copyWith(legoPieces: pieces));
  }

  void removeLegoPiece(int productIndex, String pieceId) {
    if (productIndex < 0 || productIndex >= _products.length) return;
    final product = _products[productIndex];
    final pieces = product.legoPieces.where((p) => p.id != pieceId).toList();
    updateProductAt(productIndex, product.copyWith(legoPieces: pieces));
  }

  // --- 전기 설정 업데이트 ---
  void updateElec(ElectricalSettings s) {
    _elec = s;
    if (s.autoVoltage) {
      final autoV = s.computeVoltage(
        _anode.distFromProduct,
        totalSurfaceAreaDm2 * 100.0,
      );
      _elec = s.copyWith(voltage: autoV);
    }
    notifyListeners();
  }

  // 표면적 기반 전류/전압 자동 산출
  void applyRecommendedElecFromArea() {
    final areaDm2 = totalSurfaceAreaDm2;
    if (areaDm2 <= 0) return;
    final recommendedCurrent = _elec.computeCurrentFromArea(areaDm2);
    final newElec = _elec.copyWith(current: recommendedCurrent);
    final recommendedVoltage = newElec.computeVoltage(
      _anode.distFromProduct, areaDm2 * 100.0);
    _elec = newElec.copyWith(voltage: recommendedVoltage);
    notifyListeners();
  }

  void setShowFieldLines(bool v) { _showFieldLines = v; notifyListeners(); }
  void setShowHeatmap(bool v) { _showHeatmap = v; notifyListeners(); }
  void setShowTank(bool v) { _showTank = v; notifyListeners(); }
  void setShowSolution(bool v) { _showSolution = v; notifyListeners(); }
  void setShowAnodes(bool v) { _showAnodes = v; notifyListeners(); }
  void setSelectedTab(int v) { _selectedTab = v; notifyListeners(); }
  void setHeatmapMode(HeatmapMode mode) { _heatmapMode = mode; notifyListeners(); }
  void setFieldLine2DMode(FieldLine2DMode mode) { _fieldLine2DMode = mode; notifyListeners(); }

  void rotate(double dx, double dy) {
    _rotY += dx * 0.4;
    _rotX += dy * 0.4;
    _rotX = _rotX.clamp(-85.0, 85.0);
    notifyListeners();
  }

  void pan(double dx, double dy) {
    _panX += dx;
    _panY += dy;
    notifyListeners();
  }

  void addZoom(double delta) {
    _zoom = (_zoom * (1.0 + delta * 0.1)).clamp(0.1, 10.0);
    notifyListeners();
  }

  void setZoom(double z) {
    _zoom = z.clamp(0.1, 10.0);
    notifyListeners();
  }

  void resetView() {
    _rotX = -14.0;
    _rotY = -34.0;
    _zoom = 1.55;
    _panX = 0.0;
    _panY = -14.0;
    notifyListeners();
  }

  // --- 마스킹 ---
  void addMaskingZone() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _maskingZones = [..._maskingZones, MaskingZone(id: id)];
    notifyListeners();
  }

  void updateMaskingZone(String id, MaskingZone updated) {
    _maskingZones = _maskingZones.map((m) => m.id == id ? updated : m).toList();
    notifyListeners();
  }

  void removeMaskingZone(String id) {
    _maskingZones = _maskingZones.where((m) => m.id != id).toList();
    notifyListeners();
  }

  // --- 시뮬레이션 ---
  Future<void> runSimulation() async {
    _isSimulating = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 30));

    try {
      _fieldLines = PlatingSimulationService.computeFieldLinesMulti(
        tank: _tank, anode: _anode, products: _products,
        numLinesPerAnode: 64,
      );
      _thicknessPoints = PlatingSimulationService.computeThicknessMulti(
        tank: _tank, anode: _anode, products: _products,
        elec: _elec, maskingZones: _maskingZones, gridResolution: 25,
      );
      _fieldStrengthPoints = PlatingSimulationService.computeFieldStrengthMap(
        tank: _tank, anode: _anode, products: _products,
        gridResolution: 25,
      );
      _analysisResult = PlatingSimulationService.analyze(
        thicknessPoints: _thicknessPoints,
        tank: _tank, anode: _anode, products: _products, elec: _elec,
      );
    } catch (e) {
      debugPrint('Simulation error: $e');
    }

    _isSimulating = false;
    notifyListeners();
  }
}
