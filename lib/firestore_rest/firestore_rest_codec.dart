/// Marshaling between plain JSON (what `RoutineTask.toJson()`/`BlockedApp.toJson()`
/// produce) and the Firestore REST API's typed value wire format
/// (`{"fields": {"key": {"stringValue": ...}}}`), shared by the REST
/// implementations of [RoutineRepositoryService] and
/// [BlockedAppsRepositoryService] — the native `cloud_firestore` SDK does
/// this same conversion internally, but plain REST calls have to do it by
/// hand.
library;

Map<String, dynamic> encodeFirestoreFields(Map<String, dynamic> json) {
  return json.map((key, value) => MapEntry(key, encodeFirestoreValue(value)));
}

Map<String, dynamic> encodeFirestoreValue(dynamic value) {
  return switch (value) {
    null => {'nullValue': null},
    bool b => {'booleanValue': b},
    int i => {'integerValue': i.toString()},
    double d => {'doubleValue': d},
    String s => {'stringValue': s},
    List<dynamic> list => {
      'arrayValue': {'values': list.map(encodeFirestoreValue).toList()},
    },
    Map<String, dynamic> map => {
      'mapValue': {'fields': encodeFirestoreFields(map)},
    },
    _ => {'stringValue': value.toString()},
  };
}

Map<String, dynamic> decodeFirestoreFields(Map<String, dynamic> doc) {
  final fields = doc['fields'] as Map<String, dynamic>? ?? const {};
  return fields.map((key, value) => MapEntry(key, decodeFirestoreValue(value)));
}

dynamic decodeFirestoreValue(dynamic wrapped) {
  final map = wrapped as Map<String, dynamic>;
  if (map.containsKey('nullValue')) return null;
  if (map.containsKey('booleanValue')) return map['booleanValue'] as bool;
  if (map.containsKey('integerValue')) {
    return int.parse(map['integerValue'] as String);
  }
  if (map.containsKey('doubleValue')) {
    return (map['doubleValue'] as num).toDouble();
  }
  if (map.containsKey('stringValue')) return map['stringValue'] as String;
  if (map.containsKey('arrayValue')) {
    final values =
        (map['arrayValue'] as Map<String, dynamic>)['values'] as List<dynamic>? ??
        const [];
    return values.map(decodeFirestoreValue).toList();
  }
  if (map.containsKey('mapValue')) {
    final fields =
        (map['mapValue'] as Map<String, dynamic>)['fields'] as Map<String, dynamic>? ??
        const {};
    return fields.map((key, value) => MapEntry(key, decodeFirestoreValue(value)));
  }
  // timestampValue, geoPointValue, referenceValue, bytesValue: not produced
  // by this SDK's own writes (dates are already ISO-8601 strings via
  // toJson()), but decode to a string rather than throwing if ever
  // encountered from data written some other way.
  return map.values.first;
}
