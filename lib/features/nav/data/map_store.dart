import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/arch/repository.dart';
import '../../../core/store.dart';
import '../model/region.dart';

/// Downloaded maps (list in prefs, map files under app support /maps).
class MapStore {
  static final regions = PrefsRepository<String, Region>(
    Store.raw,
    'nav_maps',
    JsonCodec(encode: (r) => r.toJson(), decode: (j) => Region.fromJson(j as Map)),
    (r) => r.id,
  );

  static String? get lastRegionId => Store.raw.getString('nav_last_region');
  static Future<void> setLastRegion(String id) => Store.raw.setString('nav_last_region', id);

  static Future<String> _dir() async => '${(await getApplicationSupportDirectory()).path}/maps';
  static Future<String> pathFor(String id) async => '${await _dir()}/$id.brg';
  static Future<String> tileDir() async => '${await _dir()}/tiles';

  static Future<void> delete(String id) async {
    final f = File(await pathFor(id));
    if (f.existsSync()) await f.delete();
    await regions.remove(id);
  }
}
