class User {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final List<String> joinedGroups;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.joinedGroups = const [],
  });

  // Factory for creating a dummy user
  factory User.dummy() {
    return User(
      id: 'user_123',
      name: 'Jason',
      email: 'jason@example.com',
      joinedGroups: [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'joinedGroups': joinedGroups,
    };
  }

  factory User.fromMap(Map<String, dynamic> map, String id) {
    return User(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      avatarUrl: map['avatarUrl'],
      joinedGroups: List<String>.from(map['joinedGroups'] ?? []),
    );
  }
}
