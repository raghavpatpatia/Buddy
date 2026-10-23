import 'dart:math';

/// A downloaded map: the rectangle the user picked, and which weekly build of the tiles it came from.
class Region {
  final String id, name;
  final double south, west, north, east;
  final int bytes, nodes, roads;
  final DateTime? downloadedAt;

  /// Manifest build time the map was made from (compared to spot updates) and the OSM data date.
  final String built, dataDate;

  const Region({
    required this.id,
    required this.name,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    this.bytes = 0,
    this.nodes = 0,
    this.roads = 0,
    this.downloadedAt,
    this.built = '',
    this.dataDate = '',
  });

  double get centerLat => (south + north) / 2;
  double get centerLon => (west + east) / 2;
  bool contains(double la, double lo) => la >= south && la <= north && lo >= west && lo <= east;

  /// Roughly how far (km) a point is outside the box; 0 inside.
  double kmOutside(double la, double lo) {
    final dy = la < south ? south - la : la > north ? la - north : 0.0;
    final dx = lo < west ? west - lo : lo > east ? lo - east : 0.0;
    return sqrt(pow(dy * 111.2, 2) + pow(dx * 111.2 * cos(la * pi / 180), 2));
  }
  (double, double, double, double) get box => (south, west, north, east);
  double get km2 => areaKm2(box);

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'box': [south, west, north, east], 'bytes': bytes, 'nodes': nodes, 'roads': roads,
        'at': downloadedAt?.millisecondsSinceEpoch, 'built': built, 'data': dataDate,
      };

  factory Region.fromJson(Map j) {
    final box = (j['box'] as List).cast<num>();
    return Region(
      id: j['id'], name: j['name'],
      south: box[0].toDouble(), west: box[1].toDouble(), north: box[2].toDouble(), east: box[3].toDouble(),
      bytes: j['bytes'] ?? 0, nodes: j['nodes'] ?? 0, roads: j['roads'] ?? 0,
      downloadedAt: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at']),
      built: j['built'] ?? '', dataDate: j['data'] ?? '',
    );
  }
}

/// Area of a (south, west, north, east) box in km².
double areaKm2((double, double, double, double) b) => (b.$3 - b.$1) * 111.2 * (b.$4 - b.$2) * 111.2 * cos((b.$1 + b.$3) / 2 * pi / 180);

/// What the map server has: one entry per 1° tile.
class MapManifest {
  final int format, tileDeg;
  final String country, built, dataDate, license;
  final Map<String, (int bytes, int nodes)> tiles;
  const MapManifest(this.format, this.tileDeg, this.country, this.built, this.dataDate, this.license, this.tiles);

  factory MapManifest.fromJson(Map j) => MapManifest(
        j['format'] as int,
        (j['tileDeg'] as num?)?.toInt() ?? 1,
        j['country'] ?? '',
        j['built'] ?? '',
        j['data'] ?? '',
        j['license'] ?? '',
        {for (final e in (j['tiles'] as Map).entries) e.key as String: ((e.value['bytes'] as num).toInt(), (e.value['nodes'] as num).toInt())},
      );

  /// Tiles under a box: (name, overlap share 0..1).
  List<(String, double)> tilesIn((double, double, double, double) b) => [
        for (var y = b.$1.floor(); y <= (b.$3 - 1e-9).floor(); y++)
          for (var x = b.$2.floor(); x <= (b.$4 - 1e-9).floor(); x++)
            if (tiles.containsKey('${y}_$x'))
              ('${y}_$x', (min(b.$3, y + 1.0) - max(b.$1, y.toDouble())) * (min(b.$4, x + 1.0) - max(b.$2, x.toDouble()))),
      ];

  /// (bytes to download, estimated road points inside the box).
  (int, int) estimate((double, double, double, double) b) {
    var bytes = 0, nodes = 0.0;
    for (final (t, share) in tilesIn(b)) {
      bytes += tiles[t]!.$1;
      nodes += tiles[t]!.$2 * share;
    }
    return (bytes, nodes.round());
  }
}

/// A searched point: a street, address or landmark.
class Place {
  final String name, detail;
  final double lat, lon;
  const Place(this.name, this.detail, this.lat, this.lon);

  String get coords => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}
