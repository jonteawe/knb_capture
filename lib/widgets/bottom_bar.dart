import 'package:flutter/material.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    this.onCapture,
    this.onReset,
    this.onToggleFlash,
    this.isFlashOn = false,
  });

  final VoidCallback? onCapture;
  final VoidCallback? onReset;
  final VoidCallback? onToggleFlash;
  final bool isFlashOn;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.16,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.only(bottom: 28),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔦 Flash toggle button
              IconButton(
                onPressed: onToggleFlash,
                icon: Icon(
                  isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),

              // 📸 Capture button
              ElevatedButton(
                onPressed: onCapture,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Capture Colors',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 18),

              // 🔁 Reset button
              if (onReset != null)
                ElevatedButton(
                  onPressed: onReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
