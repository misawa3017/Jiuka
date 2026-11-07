import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:mocktail/mocktail.dart';
import 'package:jiuka/features/auth/models/user_model.dart';
import 'package:jiuka/features/auth/repositories/auth_repository.dart';

class MockAuth extends Mock implements fb.FirebaseAuth {}

class MockStore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockTransaction extends Mock implements Transaction {}

class MockUser extends Mock implements fb.User {}

class MockUserInfo extends Mock implements fb.UserInfo {}

class MockCredential extends Mock implements fb.UserCredential {}

class AuthFixture {
  final auth = MockAuth();
  final store = MockStore();
  final collection = MockCollection();
  final document = MockDocument();
  final snapshot = MockSnapshot();
  final transaction = MockTransaction();
  final user = MockUser();
  final credential = MockCredential();
  final userInfo = MockUserInfo();
  final changes = StreamController<fb.User?>.broadcast();
  Map<String, dynamic>? saved;
  Object? loginError;
  Object? storeError;
  int writes = 0;
  late final AuthRepository repository;

  AuthFixture() {
    when(() => auth.authStateChanges()).thenAnswer((_) => changes.stream);
    when(() => auth.signOut()).thenAnswer((_) async {
      changes.add(null);
    });
    when(() => user.uid).thenReturn('google-user');
    when(() => user.displayName).thenReturn('Google Name');
    when(() => user.email).thenReturn('player@example.com');
    when(() => user.photoURL).thenReturn(null);
    when(() => userInfo.providerId).thenReturn('google.com');
    when(() => user.providerData).thenReturn([userInfo]);
    when(() => credential.user).thenReturn(user);
    when(() => store.collection('users')).thenReturn(collection);
    when(() => collection.doc('google-user')).thenReturn(document);
    when(() => transaction.get(document)).thenAnswer((_) async => snapshot);
    when(() => snapshot.exists).thenAnswer((_) => saved != null);
    when(() => snapshot.data()).thenAnswer((_) => saved);
    when(
      () => transaction.set<Map<String, dynamic>>(document, any()),
    ).thenAnswer((invocation) {
      saved = Map<String, dynamic>.from(
        invocation.positionalArguments[1] as Map,
      );
      writes++;
      return transaction;
    });
    when(() => store.runTransaction<User>(any())).thenAnswer((
      invocation,
    ) async {
      if (storeError != null) throw storeError!;
      final callback =
          invocation.positionalArguments.first
              as Future<User> Function(Transaction);
      return callback(transaction);
    });
    repository = AuthRepository(
      firebaseAuth: auth,
      firestore: store,
      googleLogin: () async {
        if (loginError != null) throw loginError!;
        changes.add(user);
        return credential;
      },
    );
  }

  Future<void> ready() async {
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    repository.dispose();
    await changes.close();
  }
}
