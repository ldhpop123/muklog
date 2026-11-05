import 'package:flutter/widgets.dart';

import '../../../models/place.dart';
import 'muk_map_types.dart';

Future<void> initMapSdk() => throw UnsupportedError('지원하지 않는 플랫폼입니다.');

Widget buildPlatformMap(List<MukMapPin> pins, PinTapCallback onPinTap, LatLng center, LatLng? me) =>
    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
