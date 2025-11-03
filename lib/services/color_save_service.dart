import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ColorSaveService {
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

      // 🔹 Konvertera Color → Firestore-kompatibel struktur
      final colorMaps = colors.map((c) => {
        'r': c.red,
        'g': c.green,
        'b': c.blue,
      }).toList();

      final jsonData = {
        'LatestColors': colorMaps,
        'Collections': {
          'Theme_${timestamp.substring(11, 19).replaceAll(":", "_")}': colorMaps,
          'LatestColors': colorMaps,
        },
        'Metadata': {
          'LatestFile': 'Theme_${timestamp.substring(11, 19)}.json',
          'ExportTime': timestamp,
        },
      };

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
    } catch (e, st) {
      debugPrint('❌ Fel vid uppladdning: $e');
      debugPrint(st.toString());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fel vid uppladdning: $e')),
        );
      }
    }
  }
}
