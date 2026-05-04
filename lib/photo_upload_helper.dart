import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PhotoUploadResult {
  final bool ok;
  final String message;

  const PhotoUploadResult({
    required this.ok,
    required this.message,
  });
}

class PhotoDocument {
  final String id;
  final String filePath;
  final String? description;
  final String? uploadedAt;
  final String? maintenanceEventId;

  const PhotoDocument({
    required this.id,
    required this.filePath,
    required this.description,
    required this.uploadedAt,
    required this.maintenanceEventId,
  });

  factory PhotoDocument.fromMap(Map<String, dynamic> map) {
    return PhotoDocument(
      id: map['id']?.toString() ?? '',
      filePath: map['file_path']?.toString() ?? '',
      description: map['description']?.toString(),
      uploadedAt: map['uploaded_at']?.toString(),
      maintenanceEventId: map['maintenance_event_id']?.toString(),
    );
  }
}

class AssignmentPhotoDocument {
  final String id;
  final String assignmentId;
  final String assetId;
  final String phase;
  final String filePath;
  final String? description;
  final String? createdAt;

  const AssignmentPhotoDocument({
    required this.id,
    required this.assignmentId,
    required this.assetId,
    required this.phase,
    required this.filePath,
    required this.description,
    required this.createdAt,
  });

  factory AssignmentPhotoDocument.fromMap(Map<String, dynamic> map) {
    return AssignmentPhotoDocument(
      id: map['id']?.toString() ?? '',
      assignmentId: map['assignment_id']?.toString() ?? '',
      assetId: map['asset_id']?.toString() ?? '',
      phase: map['phase']?.toString() ?? '',
      filePath: map['file_path']?.toString() ?? '',
      description: map['description']?.toString(),
      createdAt: map['created_at']?.toString(),
    );
  }
}

class DraftPhoto {
  final Uint8List bytes;
  final String fileName;

  const DraftPhoto({
    required this.bytes,
    required this.fileName,
  });
}

class PhotoUploadHelper {
  static const _assignmentBucket = 'assignments-photos';

  static Future<PhotoUploadResult> uploadPhotosFromPicker({
    required String assetId,
    String? maintenanceEventId,
    String? description,
  }) async {
    final client = Supabase.instance.client;

    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para subir fotos.',
      );
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: true,
      );
      final files = picked?.files.where((f) => f.bytes != null).toList() ?? [];
      if (files.isEmpty) {
        return const PhotoUploadResult(
          ok: false,
          message: 'No se seleccionaron fotos.',
        );
      }

      for (final file in files) {
        await _uploadSinglePhoto(
          assetId: assetId,
          maintenanceEventId: maintenanceEventId,
          description: description,
          bytes: file.bytes!,
          fileName: file.name,
        );
      }

      return PhotoUploadResult(
        ok: true,
        message: 'Fotos subidas: ${files.length}.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<PhotoUploadResult> captureAndUploadPhoto({
    required String assetId,
    String? maintenanceEventId,
    String? description,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para tomar fotos.',
      );
    }

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image == null) {
        return const PhotoUploadResult(
          ok: false,
          message: 'No se tomo ninguna foto.',
        );
      }

      final bytes = await image.readAsBytes();
      await _uploadSinglePhoto(
        assetId: assetId,
        maintenanceEventId: maintenanceEventId,
        description: description,
        bytes: bytes,
        fileName: image.name,
      );

      return const PhotoUploadResult(
        ok: true,
        message: 'Foto capturada y guardada.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<List<PhotoDocument>> fetchPhotos({
    required String assetId,
    String? maintenanceEventId,
  }) async {
    final client = Supabase.instance.client;
    var query = client
        .schema('sistema')
        .from('asset_documents')
        .select('id, file_path, description, uploaded_at, maintenance_event_id')
        .eq('asset_id', assetId)
        .eq('file_type', 'foto');

    if (maintenanceEventId == null) {
      query = query.isFilter('maintenance_event_id', null);
    } else {
      query = query.eq('maintenance_event_id', maintenanceEventId);
    }

    final rows = await query.order('uploaded_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => PhotoDocument.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String> getSignedPhotoUrl(String filePath) async {
    final client = Supabase.instance.client;
    return client.storage.from('assets-photos').createSignedUrl(filePath, 3600);
  }

  static Future<PhotoUploadResult> deletePhoto({
    required String documentId,
    required String filePath,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para eliminar fotos.',
      );
    }

    try {
      await client.storage.from('assets-photos').remove([filePath]);
      await client
          .schema('sistema')
          .from('asset_documents')
          .delete()
          .eq('id', documentId);
      return const PhotoUploadResult(
        ok: true,
        message: 'Foto eliminada correctamente.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<PhotoUploadResult> uploadDraftPhotos({
    required String assetId,
    String? maintenanceEventId,
    String? description,
    required List<DraftPhoto> photos,
    void Function(double)? onProgress,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para subir fotos.',
      );
    }
    if (photos.isEmpty) {
      return const PhotoUploadResult(
        ok: true,
        message: 'No hay fotos pendientes por subir.',
      );
    }

    try {
      for (int i = 0; i < photos.length; i++) {
        if (onProgress != null) {
          onProgress(i / photos.length);
        }
        await _uploadSinglePhoto(
          assetId: assetId,
          maintenanceEventId: maintenanceEventId,
          description: description,
          bytes: photos[i].bytes,
          fileName: photos[i].fileName,
        );
      }
      if (onProgress != null) onProgress(1.0);
      return PhotoUploadResult(
        ok: true,
        message: 'Archivos guardados: ${photos.length}.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<PhotoUploadResult> uploadAssignmentDraftPhotos({
    required String assignmentId,
    required String assetId,
    required String phase,
    String? description,
    required List<DraftPhoto> photos,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para subir fotos.',
      );
    }
    if (photos.isEmpty) {
      return const PhotoUploadResult(
        ok: true,
        message: 'No hay fotos pendientes por subir.',
      );
    }

    try {
      for (final photo in photos) {
        await _uploadSingleAssignmentPhoto(
          assignmentId: assignmentId,
          assetId: assetId,
          phase: phase,
          description: description,
          bytes: photo.bytes,
          fileName: photo.fileName,
        );
      }
      return PhotoUploadResult(
        ok: true,
        message: 'Fotos guardadas: ${photos.length}.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<List<AssignmentPhotoDocument>> fetchAssignmentPhotos({
    required String assignmentId,
    String? phase,
  }) async {
    final client = Supabase.instance.client;
    var query = client
        .schema('sistema')
        .from('assignment_photos')
        .select('id, assignment_id, asset_id, phase, file_path, description, created_at')
        .eq('assignment_id', assignmentId);
    if (phase != null && phase.trim().isNotEmpty) {
      query = query.eq('phase', phase.trim());
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => AssignmentPhotoDocument.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String> getSignedAssignmentPhotoUrl(String filePath) async {
    final client = Supabase.instance.client;
    return client.storage.from(_assignmentBucket).createSignedUrl(filePath, 3600);
  }

  static Future<PhotoUploadResult> deleteAssignmentPhoto({
    required String documentId,
    required String filePath,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      return const PhotoUploadResult(
        ok: false,
        message: 'Inicia sesion para eliminar fotos.',
      );
    }
    try {
      await client.storage.from(_assignmentBucket).remove([filePath]);
      await client
          .schema('sistema')
          .from('assignment_photos')
          .delete()
          .eq('id', documentId);
      return const PhotoUploadResult(
        ok: true,
        message: 'Foto eliminada correctamente.',
      );
    } on StorageException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error storage: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error BD: ${e.message}',
      );
    } catch (e) {
      return PhotoUploadResult(
        ok: false,
        message: 'Error inesperado: $e',
      );
    }
  }

  static Future<void> _uploadSinglePhoto({
    required String assetId,
    String? maintenanceEventId,
    required String? description,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final client = Supabase.instance.client;
    final safeName = (fileName.isEmpty ? 'foto.jpg' : fileName)
        .replaceAll(' ', '_')
        .replaceAll('/', '_')
        .replaceAll('\\', '_');
    final folder = maintenanceEventId == null
        ? 'assets/$assetId/photos'
        : 'assets/$assetId/maintenance/$maintenanceEventId/photos';
    final path = '$folder/${DateTime.now().microsecondsSinceEpoch}_$safeName';

    await client.storage.from('assets-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    await client.schema('sistema').from('asset_documents').insert({
      'asset_id': assetId,
      'maintenance_event_id': maintenanceEventId,
      'file_path': path,
      'file_type': 'foto',
      'description': (description == null || description.trim().isEmpty)
          ? null
          : description.trim(),
    });
  }

  static Future<void> _uploadSingleAssignmentPhoto({
    required String assignmentId,
    required String assetId,
    required String phase,
    required String? description,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final client = Supabase.instance.client;
    final safeName = (fileName.isEmpty ? 'foto.jpg' : fileName)
        .replaceAll(' ', '_')
        .replaceAll('/', '_')
        .replaceAll('\\', '_');
    final path =
        'assignment/$assignmentId/$phase/${DateTime.now().microsecondsSinceEpoch}_$safeName';

    await client.storage.from(_assignmentBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    await client.schema('sistema').from('assignment_photos').insert({
      'assignment_id': assignmentId,
      'asset_id': assetId,
      'phase': phase,
      'file_path': path,
      'description': (description == null || description.trim().isEmpty)
          ? null
          : description.trim(),
    });
  }
}
