// Basic Flutter widget test for Xen Words app

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xen_words/main.dart';

void main() {
  testWidgets('App initializes without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const XenWordsApp());

    // Verify the app builds successfully
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
