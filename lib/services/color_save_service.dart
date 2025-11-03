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
      if (colors.isEmpty) {
        debugPrint('⚠️ Inga färger att spara.');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('❌ Ingen användare inloggad.');
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final timestamp = DateTime.now().toIso8601String();

      // 🔹 Konvertera Color-listan till RGB-listor
      final rgbList = colors.map((c) => [c.red, c.green, c.blue]).toList();

      // 🔹 Skapa JSON-struktur i samma format som du visade
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

      // 🔹 Spara till Firestore under användarens UID
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('palettes')
          .add(jsonData);

      debugPrint('✅ Färgpalett sparad till Firestore!');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Färgpalett sparad till Firestore!')),
        );
      }
    } catch (e) {
      debugPrint('❌ Fel vid uppladdning till Firestore: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fel vid uppladdning till Firestore')),
        );
      }
    }
  }
}
