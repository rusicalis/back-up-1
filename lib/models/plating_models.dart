import 'package:flutter/material.dart';
import 'dart:math' as math;

// ============================================================
// 도금 종류
// ============================================================
enum PlatingType {
  silver, tin, zincAcid, zincAlkaline, cadmium,
  nickelElectro, nickelSulfamate, chromeDense,
}

extension PlatingTypeExtension on PlatingType {
  String get label {
    switch (this) {
      case PlatingType.silver:           return '은 (Silver)';
      case PlatingType.tin:              return '주석 (Tin)';
      case PlatingType.zincAcid:         return '아연 산성';
      case PlatingType.zincAlkaline:     return '아연 알칼리';
      case PlatingType.cadmium:          return '카드뮴';
      case PlatingType.nickelElectro:    return '전기니켈';
      case PlatingType.nickelSulfamate:  return '설파민산 니켈';
      case PlatingType.chromeDense:      return '고밀도 크롬';
    }
  }
  Color get color {
    switch (this) {
      case PlatingType.silver:           return const Color(0xFFC0C0C0);
      case PlatingType.tin:              return const Color(0xFF8A8A8A);
      case PlatingType.zincAcid:         return const Color(0xFF6B8E6B);
      case PlatingType.zincAlkaline:     return const Color(0xFF5B8A7A);
      case PlatingType.cadmium:          return const Color(0xFF9B8B6B);
      case PlatingType.nickelElectro:    return const Color(0xFF7B9B8B);
      case PlatingType.nickelSulfamate:  return const Color(0xFF8B9BAB);
      case PlatingType.chromeDense:      return const Color(0xFFABC0D0);
    }
  }
  double get currentEfficiency {
    switch (this) {
      case PlatingType.silver:           return 98.0;
      case PlatingType.tin:              return 90.0;
      case PlatingType.zincAcid:         return 95.0;
      case PlatingType.zincAlkaline:     return 75.0;
      case PlatingType.cadmium:          return 90.0;
      case PlatingType.nickelElectro:    return 97.0;
      case PlatingType.nickelSulfamate:  return 99.0;
      case PlatingType.chromeDense:      return 22.0;
    }
  }
  double get atomicWeight {
    switch (this) {
      case PlatingType.silver:           return 107.87;
      case PlatingType.tin:              return 118.71;
      case PlatingType.zincAcid:         return 65.38;
      case PlatingType.zincAlkaline:     return 65.38;
      case PlatingType.cadmium:          return 112.41;
      case PlatingType.nickelElectro:    return 58.69;
      case PlatingType.nickelSulfamate:  return 58.69;
      case PlatingType.chromeDense:      return 52.00;
    }
  }
  int get valence {
    switch (this) {
      case PlatingType.silver:           return 1;
      case PlatingType.tin:              return 2;
      case PlatingType.zincAcid:         return 2;
      case PlatingType.zincAlkaline:     return 2;
      case PlatingType.cadmium:          return 2;
      case PlatingType.nickelElectro:    return 2;
      case PlatingType.nickelSulfamate:  return 2;
      case PlatingType.chromeDense:      return 6;
    }
  }
  double get density {
    switch (this) {
      case PlatingType.silver:           return 10.49;
      case PlatingType.tin:              return 7.30;
      case PlatingType.zincAcid:         return 7.13;
      case PlatingType.zincAlkaline:     return 7.13;
      case PlatingType.cadmium:          return 8.65;
      case PlatingType.nickelElectro:    return 8.90;
      case PlatingType.nickelSulfamate:  return 8.90;
      case PlatingType.chromeDense:      return 7.19;
    }
  }
  (double, double) get currentDensityRange {
    switch (this) {
      case PlatingType.silver:           return (0.5, 3.0);
      case PlatingType.tin:              return (1.0, 5.0);
      case PlatingType.zincAcid:         return (1.0, 6.0);
      case PlatingType.zincAlkaline:     return (0.5, 4.0);
      case PlatingType.cadmium:          return (0.5, 3.0);
      case PlatingType.nickelElectro:    return (2.0, 8.0);
      case PlatingType.nickelSulfamate:  return (3.0, 15.0);
      case PlatingType.chromeDense:      return (20.0, 80.0);
    }
  }
  double get electrolyteConductivity {
    switch (this) {
      case PlatingType.silver:           return 0.08;
      case PlatingType.tin:              return 0.05;
      case PlatingType.zincAcid:         return 0.04;
      case PlatingType.zincAlkaline:     return 0.06;
      case PlatingType.cadmium:          return 0.07;
      case PlatingType.nickelElectro:    return 0.05;
      case PlatingType.nickelSulfamate:  return 0.04;
      case PlatingType.chromeDense:      return 0.02;
    }
  }
}

// ============================================================
// 3D 벡터
// ============================================================
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const Vec3 zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double get lengthSq => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSq);

  Vec3 normalized() {
    final l = length;
    if (l < 1e-12) return Vec3.zero;
    return Vec3(x / l, y / l, z / l);
  }

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(
    y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x,
  );

  Vec3 lerp(Vec3 o, double t) => this + (o - this) * t;

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(1)},${y.toStringAsFixed(1)},${z.toStringAsFixed(1)})';
}

// ============================================================
// 제품 형태 종류
// ============================================================
enum ProductShape {
  box,           // 사각기둥
  cylinder,      // 원기둥
  dish,          // 접시형 (납작한 원통)
  hollowBox,     // 속빈 박스
  lShape,        // L자형
  pipe,          // 파이프 (속빈 원통)
  bracket,       // 브라켓형 굴곡 부품
  steppedBox,    // 단차 박스
}

extension ProductShapeExtension on ProductShape {
  String get label {
    switch (this) {
      case ProductShape.box:        return '사각기둥 (Box)';
      case ProductShape.cylinder:   return '원기둥 (Cylinder)';
      case ProductShape.dish:       return '접시형 (Dish)';
      case ProductShape.hollowBox:  return '속빈 박스 (Hollow)';
      case ProductShape.lShape:     return 'L자형 (L-Shape)';
      case ProductShape.pipe:       return '파이프 (Pipe)';
      case ProductShape.bracket:    return '브라켓형 (Bracket)';
      case ProductShape.steppedBox: return '단차 박스 (Stepped Box)';
    }
  }
}

// ============================================================
// 레고 블록 피스 (복합 제품 모델링용)
// ============================================================
enum LegoPieceShape { box, cylinder, sphere }

class LegoPiece {
  final String id;
  final LegoPieceShape shape;
  final double width;   // X
  final double height;  // Y
  final double length;  // Z
  final double offsetX; // 제품 중심 기준 오프셋
  final double offsetY;
  final double offsetZ;
  final Color color;

  const LegoPiece({
    required this.id,
    this.shape = LegoPieceShape.box,
    this.width = 10.0,
    this.height = 10.0,
    this.length = 10.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetZ = 0.0,
    this.color = Colors.lightBlue,
  });

  LegoPiece copyWith({
    LegoPieceShape? shape,
    double? width, double? height, double? length,
    double? offsetX, double? offsetY, double? offsetZ,
    Color? color,
  }) => LegoPiece(
    id: id,
    shape: shape ?? this.shape,
    width: width ?? this.width,
    height: height ?? this.height,
    length: length ?? this.length,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
    offsetZ: offsetZ ?? this.offsetZ,
    color: color ?? this.color,
  );

  /// 전체 바운딩 박스 계산
  (Vec3, Vec3) getBoundingBox() {
    return (
      Vec3(offsetX - width/2, offsetY - height/2, offsetZ - length/2),
      Vec3(offsetX + width/2, offsetY + height/2, offsetZ + length/2),
    );
  }
}

// ============================================================
// 마스킹 구역
// ============================================================
class MaskingZone {
  final String id;
  final double xMin, xMax; // 제품 내 상대 좌표 (0~1)
  final double yMin, yMax;
  final double zMin, zMax;
  final String label;

  const MaskingZone({
    required this.id,
    this.xMin = 0.3, this.xMax = 0.7,
    this.yMin = 0.3, this.yMax = 0.7,
    this.zMin = 0.0, this.zMax = 0.3,
    this.label = '마스킹',
  });

  MaskingZone copyWith({
    double? xMin, double? xMax,
    double? yMin, double? yMax,
    double? zMin, double? zMax,
    String? label,
  }) => MaskingZone(
    id: id,
    xMin: xMin ?? this.xMin, xMax: xMax ?? this.xMax,
    yMin: yMin ?? this.yMin, yMax: yMax ?? this.yMax,
    zMin: zMin ?? this.zMin, zMax: zMax ?? this.zMax,
    label: label ?? this.label,
  );

  bool contains(double nx, double ny, double nz) =>
    nx >= xMin && nx <= xMax &&
    ny >= yMin && ny <= yMax &&
    nz >= zMin && nz <= zMax;
}

// ============================================================
// 탱크 설정 (X=폭, Y=깊이, Z=길이)
// ============================================================
class TankSettings {
  double width;        // X: 폭 (cm)
  double depth;        // Y: 깊이 (cm)
  double length;       // Z: 길이 (cm)
  double solutionLevel; // 용액 수위 (바닥으로부터 높이, cm)

  TankSettings({
    this.width = 100.0,
    this.depth = 80.0,
    this.length = 120.0,
    this.solutionLevel = 60.0,
  });

  TankSettings copyWith({
    double? width, double? depth, double? length, double? solutionLevel,
  }) => TankSettings(
    width: width ?? this.width,
    depth: depth ?? this.depth,
    length: length ?? this.length,
    solutionLevel: solutionLevel ?? this.solutionLevel,
  );
}

// ============================================================
// 양극(Anode) 설정 - X/Z 독립 위치 조정 지원
// ============================================================
class AnodeSettings {
  double width;             // X 두께 (cm)
  double depth;             // Y 높이 (cm)
  double length;            // Z 길이 (cm)
  int count;                // 개수 (양쪽 합계, 최대 20)
  double distFromProduct;   // 제품 중심에서 양극까지 거리 cm (양쪽 동일)
  double yOffset;           // 바닥에서 시작 높이 cm
  double anodeSpacing;      // 다수 양극 쌍 간의 Z 간격 (cm) — 0이면 자동(length×1.5)
  // 독립 위치 조정
  double posXOffset;        // X 오프셋: 기본 위치에서 추가 이동 (양쪽 동일하게 이동)
  double posZOffset;        // Z 오프셋: 양극 그룹 전체 Z 이동
  // 절대 위치 고정 (제품이 움직여도 양극은 고정)
  bool absolutePosition;    // true: 제품 위치 무관하게 고정된 X/Z 기준점 사용

  AnodeSettings({
    this.width = 5.0,
    this.depth = 50.0,
    this.length = 50.0,
    this.count = 2,
    this.distFromProduct = 30.0,
    this.yOffset = 5.0,
    this.anodeSpacing = 0.0,
    this.posXOffset = 0.0,
    this.posZOffset = 0.0,
    this.absolutePosition = false,
  });

  AnodeSettings copyWith({
    double? width, double? depth, double? length,
    int? count, double? distFromProduct, double? yOffset,
    double? anodeSpacing,
    double? posXOffset, double? posZOffset,
    bool? absolutePosition,
  }) => AnodeSettings(
    width: width ?? this.width,
    depth: depth ?? this.depth,
    length: length ?? this.length,
    count: count ?? this.count,
    distFromProduct: distFromProduct ?? this.distFromProduct,
    yOffset: yOffset ?? this.yOffset,
    anodeSpacing: anodeSpacing ?? this.anodeSpacing,
    posXOffset: posXOffset ?? this.posXOffset,
    posZOffset: posZOffset ?? this.posZOffset,
    absolutePosition: absolutePosition ?? this.absolutePosition,
  );
}

// ============================================================
// 제품(음극) 설정 - 다수 제품 지원
// ============================================================
enum BaseMaterial { cu, fe, al }

extension BaseMaterialExtension on BaseMaterial {
  String get label {
    switch (this) {
      case BaseMaterial.cu:
        return 'CU (구리)';
      case BaseMaterial.fe:
        return 'FE (철)';
      case BaseMaterial.al:
        return 'AL (알루미늄)';
    }
  }

  Color get color {
    switch (this) {
      case BaseMaterial.cu:
        return const Color(0xFFB87333);
      case BaseMaterial.fe:
        return const Color(0xFF8A8F98);
      case BaseMaterial.al:
        return const Color(0xFFC9D1D9);
    }
  }

  double get conductivityFactor {
    switch (this) {
      case BaseMaterial.cu:
        return 1.00;
      case BaseMaterial.fe:
        return 0.78;
      case BaseMaterial.al:
        return 0.92;
    }
  }

  double get shieldingFactor {
    switch (this) {
      case BaseMaterial.cu:
        return 1.00;
      case BaseMaterial.fe:
        return 0.88;
      case BaseMaterial.al:
        return 0.95;
    }
  }

  double get throwPowerFactor {
    switch (this) {
      case BaseMaterial.cu:
        return 1.00;
      case BaseMaterial.fe:
        return 0.90;
      case BaseMaterial.al:
        return 0.94;
    }
  }

  String get processNote {
    switch (this) {
      case BaseMaterial.cu:
        return '전도성이 높아 전류 분포가 안정적이며 기준 재질로 사용됩니다.';
      case BaseMaterial.fe:
        return '모서리 과전착 경향이 커 차폐/거리 조정의 영향이 더 크게 나타납니다.';
      case BaseMaterial.al:
        return '표면 산화막 영향을 고려해 throw power가 약간 저하된 조건으로 반영됩니다.';
    }
  }
}

class CadTriangle {
  final Vec3 a;
  final Vec3 b;
  final Vec3 c;
  final Vec3 normal;

  const CadTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.normal,
  });
}

class CadImportData {
  final String fileName;
  final String fileType;
  final bool isImported;
  final String summary;
  final DateTime? importedAt;
  final int triangleCount;
  final int vertexCount;
  final List<Vec3> previewVertices;
  final List<CadTriangle> triangles;
  final double? boundWidth;
  final double? boundDepth;
  final double? boundLength;

  const CadImportData({
    this.fileName = '',
    this.fileType = '',
    this.isImported = false,
    this.summary = 'CAD 파일이 아직 첨부되지 않았습니다.',
    this.importedAt,
    this.triangleCount = 0,
    this.vertexCount = 0,
    this.previewVertices = const [],
    this.triangles = const [],
    this.boundWidth,
    this.boundDepth,
    this.boundLength,
  });

  CadImportData copyWith({
    String? fileName,
    String? fileType,
    bool? isImported,
    String? summary,
    DateTime? importedAt,
    int? triangleCount,
    int? vertexCount,
    List<Vec3>? previewVertices,
    List<CadTriangle>? triangles,
    double? boundWidth,
    double? boundDepth,
    double? boundLength,
  }) => CadImportData(
    fileName: fileName ?? this.fileName,
    fileType: fileType ?? this.fileType,
    isImported: isImported ?? this.isImported,
    summary: summary ?? this.summary,
    importedAt: importedAt ?? this.importedAt,
    triangleCount: triangleCount ?? this.triangleCount,
    vertexCount: vertexCount ?? this.vertexCount,
    previewVertices: previewVertices ?? this.previewVertices,
    triangles: triangles ?? this.triangles,
    boundWidth: boundWidth ?? this.boundWidth,
    boundDepth: boundDepth ?? this.boundDepth,
    boundLength: boundLength ?? this.boundLength,
  );
}

class ProductSettings {
  final String id;
  double width;    // X 폭 (cm)
  double depth;    // Y 깊이 (cm)
  double length;   // Z 길이 (cm)
  double posX;     // 탱크 중심에서 X 오프셋
  double posY;     // 바닥에서 높이 (하단 기준)
  double posZ;     // 탱크 중심에서 Z 오프셋
  ProductShape shape;
  double wallThickness; // 속빈 박스/파이프 벽 두께
  BaseMaterial material;
  CadImportData cadImport;
  // 레고 복합 모델링
  bool useLegoMode;
  List<LegoPiece> legoPieces;

  ProductSettings({
    String? id,
    this.width = 20.0,
    this.depth = 30.0,
    this.length = 20.0,
    this.posX = 0.0,
    this.posY = 15.0,
    this.posZ = 0.0,
    this.shape = ProductShape.box,
    this.wallThickness = 3.0,
    this.material = BaseMaterial.cu,
    this.cadImport = const CadImportData(),
    this.useLegoMode = false,
    List<LegoPiece>? legoPieces,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       legoPieces = legoPieces ?? [];

  ProductSettings copyWith({
    double? width, double? depth, double? length,
    double? posX, double? posY, double? posZ,
    ProductShape? shape, double? wallThickness,
    BaseMaterial? material,
    CadImportData? cadImport,
    bool? useLegoMode, List<LegoPiece>? legoPieces,
  }) => ProductSettings(
    id: id,
    width: width ?? this.width,
    depth: depth ?? this.depth,
    length: length ?? this.length,
    posX: posX ?? this.posX,
    posY: posY ?? this.posY,
    posZ: posZ ?? this.posZ,
    shape: shape ?? this.shape,
    wallThickness: wallThickness ?? this.wallThickness,
    material: material ?? this.material,
    cadImport: cadImport ?? this.cadImport,
    useLegoMode: useLegoMode ?? this.useLegoMode,
    legoPieces: legoPieces ?? List.from(this.legoPieces),
  );

  // 제품 중심 Y 좌표
  double get centerY => posY + depth / 2;

  // 표면적 계산 (cm²) - 형상별
  double computeSurfaceArea() {
    if (useLegoMode && legoPieces.isNotEmpty) {
      // 레고 모드: 각 피스 표면적 합산 (겹침 무시)
      double total = 0;
      for (final piece in legoPieces) {
        switch (piece.shape) {
          case LegoPieceShape.box:
            total += 2 * (piece.width * piece.height +
                piece.height * piece.length + piece.width * piece.length);
            break;
          case LegoPieceShape.cylinder:
            final r = piece.width / 2;
            total += 2 * math.pi * r * piece.height +
                2 * math.pi * r * r;
            break;
          case LegoPieceShape.sphere:
            final r = piece.width / 2;
            total += 4 * math.pi * r * r;
            break;
        }
      }
      return total;
    }

    if (cadImport.isImported) {
      final type = cadImport.fileType.toLowerCase();
      if (type.contains('stl')) {
        return 1.18 * 2 * (width * depth + depth * length + width * length);
      }
      if (type.contains('step') || type.contains('stp')) {
        return 1.12 * 2 * (width * depth + depth * length + width * length);
      }
      if (type.contains('iges') || type.contains('igs')) {
        return 1.10 * 2 * (width * depth + depth * length + width * length);
      }
    }

    switch (shape) {
      case ProductShape.box:
        return 2 * (width * depth + depth * length + width * length);
      case ProductShape.cylinder:
        final r = width / 2;
        return 2 * math.pi * r * depth + 2 * math.pi * r * r;
      case ProductShape.dish:
        final r = width / 2;
        return math.pi * r * r + 2 * math.pi * r * (depth * 0.25);
      case ProductShape.hollowBox:
        final outer = 2 * (width * depth + depth * length + width * length);
        final wt = wallThickness;
        final inner = 2 * ((width-2*wt) * (depth-2*wt) +
            (depth-2*wt) * (length-2*wt) + (width-2*wt) * (length-2*wt));
        return outer + inner;
      case ProductShape.lShape:
        // 근사값: 전체 박스 × 0.75
        return 1.5 * (width * depth + depth * length + width * length);
      case ProductShape.pipe:
        final r = width / 2;
        final ri = r - wallThickness;
        return 2 * math.pi * r * depth + 2 * math.pi * ri * depth +
            2 * math.pi * (r * r - ri * ri);
      case ProductShape.bracket:
        return 1.72 * (width * depth + depth * length + width * length);
      case ProductShape.steppedBox:
        return 1.35 * 2 * (width * depth + depth * length + width * length);
    }
  }

  /// 표면적 (dm²)
  double get surfaceAreaDm2 => computeSurfaceArea() / 100.0;
}

// ============================================================
// 전기 설정
// ============================================================
class ElectricalSettings {
  double current;        // A
  double voltage;        // V
  double platingTime;    // min
  PlatingType platingType;
  bool autoVoltage;      // true: 전류→전압 자동계산
  bool autoCurrentFromArea; // true: 표면적에서 자동 전류 산출

  ElectricalSettings({
    this.current = 10.0,
    this.voltage = 6.0,
    this.platingTime = 30.0,
    this.platingType = PlatingType.nickelElectro,
    this.autoVoltage = true,
    this.autoCurrentFromArea = false,
  });

  ElectricalSettings copyWith({
    double? current, double? voltage, double? platingTime,
    PlatingType? platingType, bool? autoVoltage, bool? autoCurrentFromArea,
  }) => ElectricalSettings(
    current: current ?? this.current,
    voltage: voltage ?? this.voltage,
    platingTime: platingTime ?? this.platingTime,
    platingType: platingType ?? this.platingType,
    autoVoltage: autoVoltage ?? this.autoVoltage,
    autoCurrentFromArea: autoCurrentFromArea ?? this.autoCurrentFromArea,
  );

  // 전류 → 전압 자동 계산
  double computeVoltage(double anodeDist, double productAreaCm2) {
    final rho = platingType.electrolyteConductivity;
    final dist = anodeDist.clamp(1.0, 10000.0);
    final area = productAreaCm2.clamp(1.0, 1000000.0);
    final resistance = rho * dist / area;
    const overpotential = 0.5;
    return (current * resistance + overpotential).clamp(1.0, 30.0);
  }

  // 표면적에서 적정 전류 산출 (권장 전류밀도 중간값 사용)
  double computeCurrentFromArea(double areaDm2) {
    final cdRange = platingType.currentDensityRange;
    final targetCd = (cdRange.$1 + cdRange.$2) / 2.0;
    return (targetCd * areaDm2).clamp(0.1, 10000.0);
  }
}

// ============================================================
// 전기력선
// ============================================================
class FieldLine {
  final List<Vec3> points;
  final double intensity; // 0~1
  final int anodeIndex;   // 어떤 양극에서 출발했는지
  const FieldLine({
    required this.points,
    required this.intensity,
    this.anodeIndex = 0,
  });
}

// ============================================================
// 도금 두께 포인트
// ============================================================
class ThicknessPoint {
  final Vec3 position;
  final Vec3 normal;
  final double thickness;       // µm
  final double currentDensity;  // A/dm²
  final bool isMasked;
  final bool inSolution;
  final String productId;       // 어느 제품의 포인트인지
  const ThicknessPoint({
    required this.position,
    required this.normal,
    required this.thickness,
    required this.currentDensity,
    this.isMasked = false,
    this.inSolution = true,
    this.productId = '',
  });
}

// ============================================================
// 분석 결과
// ============================================================
class AnalysisResult {
  final double minThickness;
  final double maxThickness;
  final double avgThickness;
  final double uniformityIndex;
  final double avgCurrentDensity;
  final double totalCharge;
  final String overallGrade;
  final List<String> recommendations;
  final List<String> warnings;
  // 추가: 총 표면적 및 추천 전류 정보
  final double totalSurfaceAreaDm2;
  final double recommendedCurrent;
  final double recommendedVoltage;

  const AnalysisResult({
    required this.minThickness, required this.maxThickness,
    required this.avgThickness, required this.uniformityIndex,
    required this.avgCurrentDensity, required this.totalCharge,
    required this.overallGrade,
    required this.recommendations, required this.warnings,
    this.totalSurfaceAreaDm2 = 0.0,
    this.recommendedCurrent = 0.0,
    this.recommendedVoltage = 0.0,
  });
}
