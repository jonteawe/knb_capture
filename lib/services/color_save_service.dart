import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ColorSaveService {
  /// 🔹 Sparar en lista av färger till Firestore som JSON-struktur.
  static Future<void> saveColorsToFirebase(
    BuildContext context,
    List<Color> colors,
  ) async {
    try {
      debugPrint('🟢 Startar sparning till Firestore...');
      if (colors.isEmpty) {
        debugPrint('⚠️ Inga färger att spara.');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('❌ Ingen användare inloggad.');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingen användare inloggad!')),
          );
        }
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final timestamp = DateTime.now().toIso8601String();
      final rgbList = colors.map((c) => [c.red, c.green, c.blue]).toList();

      final jsonData = {
        "LatestColors": rgbList,
        "Collections": {
          "Färgtema ${timestamp.substring(11, 19)}": rgbList,
          "LatestColors": rgbList,
        },
        "Metadata": {
          "LatestFile": "Färgtema ${timestamp.substring(11, 19)}.txt",
          "ExportTime": timestamp,
        }
      };

      debugPrint('📦 JSON-data redo: ${jsonEncode(jsonData)}');

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('palettes')
          .add(jsonData);

      debugPrint('✅ Färgpalett sparad till Firestore för ${user.uid}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Färgpalett sparad till Firestore!')),
        );
      }
    } catch (e, st) {
      debugPrint('❌ Fel vid uppladdning till Firestore: $e');
      debugPrint('Stacktrace: $st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fel vid uppladdning: $e')),
        );
      }
    }
  }
}
