import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  try {
    final notices = await FirebaseFirestore.instance.collection('notices').get();
    print('Total notices found: \${notices.docs.length}');
    for (var doc in notices.docs) {
      print('Notice ID: \${doc.id} | Title: \${doc.data()['title']}');
    }
  } catch (e) {
    print('Error: \$e');
  }
}
