import 'package:flutter/material.dart';
import 'dart:math';

class PaletteBar extends StatelessWidget {
  const PaletteBar({super.key, required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final items = (colors.isEmpty ? List<Color>.filled(5, Colors.transparent) : colors)
        .take(5)
        .toList()
      ..addAll(List<Color>.filled(max(0, 5 - (colors.length)), Colors.transparent));

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.14,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: items.map((c) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.2),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
