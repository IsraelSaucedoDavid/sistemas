import 'dart:convert';

import 'package:http/http.dart' as http;

class ExternalPerson {
  final String? externalId;
  final String fullName;
  final String? email;
  final String? department;
  final String? employeeCode;

  const ExternalPerson({
    required this.externalId,
    required this.fullName,
    required this.email,
    required this.department,
    required this.employeeCode,
  });

  factory ExternalPerson.fromMap(Map<String, dynamic> map) {
    final nombreContacto = _clean(map['nombrecontacto']);
    final apellidoPaterno = _clean(map['apellido_paterno']);
    final apellidoMaterno = _clean(map['apellido_materno']);
    final nombreCompuesto = [
      nombreContacto,
      apellidoPaterno,
      apellidoMaterno,
    ].where((p) => p.isNotEmpty).join(' ').trim();

    final fallbackNombre =
        _clean(map['nombre']).isNotEmpty ? _clean(map['nombre']) : _clean(map['name']);

    return ExternalPerson(
      externalId: map['id']?.toString(),
      fullName: nombreCompuesto.isNotEmpty
          ? nombreCompuesto
          : (fallbackNombre.isNotEmpty ? fallbackNombre : 'Sin nombre'),
      email: _clean(map['correo']).isNotEmpty
          ? _clean(map['correo'])
          : (_clean(map['email']).isNotEmpty ? _clean(map['email']) : null),
      department: _clean(map['departamento']).isNotEmpty
          ? _clean(map['departamento'])
          : (_clean(map['department']).isNotEmpty
              ? _clean(map['department'])
              : (_clean(map['nombre_planta']).isNotEmpty ? _clean(map['nombre_planta']) : null)),
      employeeCode:
          _clean(map['numero_empleado']).isNotEmpty
              ? _clean(map['numero_empleado'])
              : (_clean(map['employee_code']).isNotEmpty
                  ? _clean(map['employee_code'])
                  : map['id']?.toString()),
    );
  }

  static String _clean(dynamic value) => value?.toString().trim() ?? '';
}

class PersonDirectoryService {
  static String get _baseUrl =>
      const String.fromEnvironment('CONTACTO_API_URL', defaultValue: '');
  static String get _token =>
      const String.fromEnvironment('CONTACTO_API_TOKEN', defaultValue: '');

  static Future<List<ExternalPerson>> searchPeople(String query) async {
    final q = query.trim();
    if (_baseUrl.isEmpty) {
      throw Exception(
        'CONTACTO_API_URL no configurada. Usa --dart-define=CONTACTO_API_URL=...',
      );
    }
    if (q.length < 2) return const [];

    final tokens = _tokenize(q);
    final mapByKey = <String, ExternalPerson>{};

    for (final person in await _fetchPeople(q)) {
      mapByKey[_personKey(person)] = person;
    }

    // Fallback: cuando la búsqueda compuesta no retorna suficientes filas,
    // consultamos por token para cubrir escenarios con LIMIT en backend.
    if (tokens.length > 1) {
      for (final token in tokens.take(3)) {
        for (final person in await _fetchPeople(token)) {
          mapByKey[_personKey(person)] = person;
        }
      }
    }

    final people = mapByKey.values.toList();
    final filtered = people.where((person) {
      if (tokens.isEmpty) return true;
      final haystack = _normalize(
        '${person.externalId ?? ''} ${person.fullName} ${person.email ?? ''} ${person.employeeCode ?? ''} ${person.department ?? ''}',
      );
      return tokens.every(haystack.contains);
    }).toList();

    filtered.sort((a, b) {
      final sa = _scorePerson(a, tokens);
      final sb = _scorePerson(b, tokens);
      if (sb != sa) return sb.compareTo(sa);
      return _normalize(a.fullName).compareTo(_normalize(b.fullName));
    });
    return filtered;
  }

  static Future<List<ExternalPerson>> _fetchPeople(String query) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'q': query,
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (_token.isNotEmpty) 'X-API-KEY': _token,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Error API contacto (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    List<dynamic> rows;
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final success = decoded['success'];
      if (success == false) {
        throw Exception(decoded['error']?.toString() ?? 'API contacto devolvio error.');
      }
      final data = decoded['data'];
      if (data is List) {
        rows = data;
      } else {
        throw Exception('Respuesta inesperada del API de contacto.');
      }
    } else {
      throw Exception('Respuesta inesperada del API de contacto.');
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(ExternalPerson.fromMap)
        .toList();
  }

  static String _personKey(ExternalPerson person) {
    if (person.externalId != null && person.externalId!.trim().isNotEmpty) {
      return 'id:${person.externalId!.trim()}';
    }
    return 'name:${_normalize(person.fullName)}|email:${_normalize(person.email ?? '')}';
  }

  static int _scorePerson(ExternalPerson person, List<String> tokens) {
    final fullName = _normalize(person.fullName);
    final text = _normalize(
      '${person.externalId ?? ''} ${person.fullName} ${person.email ?? ''} ${person.employeeCode ?? ''} ${person.department ?? ''}',
    );
    final q = tokens.join(' ').trim();
    var score = 0;
    if (q.isNotEmpty) {
      if (fullName == q) score += 140;
      if (fullName.startsWith(q)) score += 90;
      if (fullName.contains(q)) score += 55;
    }
    for (final token in tokens) {
      if (_normalize(person.externalId ?? '') == token) {
        score += 120;
      } else if (_normalize(person.externalId ?? '').contains(token)) {
        score += 40;
      }
      if (fullName.startsWith(token)) {
        score += 22;
      } else if (fullName.contains(token)) {
        score += 14;
      } else if (text.contains(token)) {
        score += 6;
      }
    }
    return score;
  }

  static List<String> _tokenize(String value) {
    return _normalize(value).split(' ').where((p) => p.isNotEmpty).toList();
  }

  static String _normalize(String value) {
    final lower = value.toLowerCase().trim();
    const withAccent = 'áéíóúäëïöüàèìòùñ';
    const withoutAccent = 'aeiouaeiouaeioun';
    final sb = StringBuffer();
    for (final ch in lower.runes) {
      final c = String.fromCharCode(ch);
      final idx = withAccent.indexOf(c);
      sb.write(idx >= 0 ? withoutAccent[idx] : c);
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ');
  }
}
