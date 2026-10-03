import 'package:flutter/material.dart';

import '../core/theme/ergos_theme.dart';

Widget field(TextEditingController c, String label, {int lines = 1, TextInputType? type, String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 6,
        keyboardType: type ?? (lines > 1 ? TextInputType.multiline : null),
        decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: true),
      ),
    );

Widget sectionTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Ergos.glow)),
    );
