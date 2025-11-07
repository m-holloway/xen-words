import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// Utility to replace embedded texture in GLB files at runtime
/// 
/// GLB Format:
/// - 12-byte header: magic (4), version (4), length (4)
/// - Chunks:
///   - JSON chunk: length (4), type (4), data
///   - BIN chunk: length (4), type (4), data (contains buffers including textures)
class GlbTextureReplacer {
  static const int _glbMagic = 0x46546C67; // 'glTF' in little-endian
  static const int _jsonChunkType = 0x4E4F534A; // 'JSON'
  static const int _binChunkType = 0x004E4942; // 'BIN\0'

  /// Replace the first PNG texture in a GLB file with a new PNG
  /// 
  /// Args:
  ///   templateAssetPath: Asset path to template GLB file (e.g., 'assets/models/library/Rug.glb')
  ///   newTexturePng: PNG image data as bytes
  ///   outputPath: Where to save modified GLB
  /// 
  /// Returns:
  ///   true if successful, false otherwise
  static Future<bool> replaceTexture({
    required String templateAssetPath,
    required Uint8List newTexturePng,
    required String outputPath,
  }) async {
    try {
      print('📂 Loading template GLB from assets: $templateAssetPath');
      
      // Load template GLB from asset bundle
      final ByteData byteData = await rootBundle.load(templateAssetPath);
      final glbBytes = byteData.buffer.asUint8List();
      
      print('✅ Loaded template: ${glbBytes.length} bytes');
      final buffer = ByteData.sublistView(glbBytes);
      
      // Parse GLB header
      final magic = buffer.getUint32(0, Endian.little);
      if (magic != _glbMagic) {
        print('❌ Invalid GLB magic number');
        return false;
      }
      
      final version = buffer.getUint32(4, Endian.little);
      final totalLength = buffer.getUint32(8, Endian.little);
      
      print('✅ GLB Header: version=$version, length=$totalLength');
      
      // Parse JSON chunk
      int offset = 12;
      final jsonChunkLength = buffer.getUint32(offset, Endian.little);
      final jsonChunkType = buffer.getUint32(offset + 4, Endian.little);
      
      if (jsonChunkType != _jsonChunkType) {
        print('❌ Expected JSON chunk at offset $offset');
        return false;
      }
      
      final jsonBytes = glbBytes.sublist(offset + 8, offset + 8 + jsonChunkLength);
      final jsonString = utf8.decode(jsonBytes);
      final gltf = json.decode(jsonString) as Map<String, dynamic>;
      
      print('✅ Parsed JSON chunk: ${jsonChunkLength} bytes');
      
      offset += 8 + jsonChunkLength;
      
      // Parse BIN chunk
      final binChunkLength = buffer.getUint32(offset, Endian.little);
      final binChunkType = buffer.getUint32(offset + 4, Endian.little);
      
      if (binChunkType != _binChunkType) {
        print('❌ Expected BIN chunk at offset $offset');
        return false;
      }
      
      final binData = glbBytes.sublist(offset + 8, offset + 8 + binChunkLength);
      
      print('✅ Parsed BIN chunk: ${binChunkLength} bytes');
      
      // Find the texture (image) in the glTF JSON
      final images = gltf['images'] as List?;
      if (images == null || images.isEmpty) {
        print('❌ No images found in glTF');
        return false;
      }
      
      final firstImage = images[0] as Map<String, dynamic>;
      final bufferViewIndex = firstImage['bufferView'] as int?;
      
      if (bufferViewIndex == null) {
        print('❌ Image does not reference a bufferView');
        return false;
      }
      
      // Get bufferView info
      final bufferViews = gltf['bufferViews'] as List;
      final imageBufferView = bufferViews[bufferViewIndex] as Map<String, dynamic>;
      
      final oldTextureOffset = imageBufferView['byteOffset'] as int? ?? 0;
      final oldTextureLength = imageBufferView['byteLength'] as int;
      
      print('📸 Found texture: offset=$oldTextureOffset, length=$oldTextureLength bytes');
      
      // Create new binary data with replaced texture
      final newBinData = _replaceBinaryData(
        binData,
        oldTextureOffset,
        oldTextureLength,
        newTexturePng,
      );
      
      // Update bufferView in glTF JSON
      imageBufferView['byteLength'] = newTexturePng.length;
      
      // Update buffer total size
      final buffers = gltf['buffers'] as List;
      final buffer0 = buffers[0] as Map<String, dynamic>;
      buffer0['byteLength'] = newBinData.length;
      
      print('✅ Updated texture: new length=${newTexturePng.length} bytes');
      
      // Rebuild GLB file
      final newJsonString = json.encode(gltf);
      final newJsonBytes = utf8.encode(newJsonString);
      
      // JSON chunk must be padded to 4-byte alignment with spaces
      final jsonPadding = (4 - (newJsonBytes.length % 4)) % 4;
      final paddedJsonLength = newJsonBytes.length + jsonPadding;
      
      // BIN chunk must be padded to 4-byte alignment with zeros
      final binPadding = (4 - (newBinData.length % 4)) % 4;
      final paddedBinLength = newBinData.length + binPadding;
      
      final newTotalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
      
      // Build new GLB
      final output = BytesBuilder();
      
      // Header
      final header = ByteData(12);
      header.setUint32(0, _glbMagic, Endian.little);
      header.setUint32(4, version, Endian.little);
      header.setUint32(8, newTotalLength, Endian.little);
      output.add(header.buffer.asUint8List());
      
      // JSON chunk
      final jsonChunkHeader = ByteData(8);
      jsonChunkHeader.setUint32(0, paddedJsonLength, Endian.little);
      jsonChunkHeader.setUint32(4, _jsonChunkType, Endian.little);
      output.add(jsonChunkHeader.buffer.asUint8List());
      output.add(newJsonBytes);
      if (jsonPadding > 0) {
        output.add(List.filled(jsonPadding, 0x20)); // Space padding
      }
      
      // BIN chunk
      final binChunkHeader = ByteData(8);
      binChunkHeader.setUint32(0, paddedBinLength, Endian.little);
      binChunkHeader.setUint32(4, _binChunkType, Endian.little);
      output.add(binChunkHeader.buffer.asUint8List());
      output.add(newBinData);
      if (binPadding > 0) {
        output.add(List.filled(binPadding, 0x00)); // Zero padding
      }
      
      // Write output file
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(output.toBytes());
      
      print('✅ Modified GLB saved: $outputPath (${newTotalLength} bytes)');
      
      return true;
    } catch (e, stackTrace) {
      print('❌ Error replacing texture: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Replace a section of binary data with new data
  /// If new data is different size, adjust buffer accordingly
  static Uint8List _replaceBinaryData(
    Uint8List original,
    int replaceOffset,
    int replaceLength,
    Uint8List newData,
  ) {
    final output = BytesBuilder();
    
    // Copy data before the replaced section
    if (replaceOffset > 0) {
      output.add(original.sublist(0, replaceOffset));
    }
    
    // Insert new data
    output.add(newData);
    
    // Copy data after the replaced section
    final afterOffset = replaceOffset + replaceLength;
    if (afterOffset < original.length) {
      output.add(original.sublist(afterOffset));
    }
    
    return output.toBytes();
  }
}

