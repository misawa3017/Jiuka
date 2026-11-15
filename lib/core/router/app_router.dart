import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../features/admin/screens/admin_screen.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/home/screens/explore_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/member_management_screen.dart';
import '../../features/groups/screens/venues_screen.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/edit_event_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/events/screens/my_events_screen.dart';
import '../../features/profile/screens/user_profile_screen.dart';

// Keys for navigation
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter(AuthRepository auth) => GoRouter(
  navigatorKey: rootNavigatorKey,
  refreshListenable: auth,
  redirect: (context, state) => authRedirect(auth, state.uri),
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ExploreScreen()),
    GoRoute(path: '/groups', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/my-events',
      builder: (context, state) => const MyEventsScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/create-event',
      builder: (context, state) => const CreateEventScreen(),
    ),
    GoRoute(
      path: '/create-group',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CreateGroupScreen(),
    ),
    GoRoute(
      path: '/group/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          GroupDetailScreen(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/group/:id/members',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          MemberManagementScreen(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/group/:id/venues',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          VenuesScreen(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/group/:id/create-event',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          CreateEventScreen(groupId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/event/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          EventDetailScreen(eventId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/event/:id/edit',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          EditEventScreen(eventId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/admin',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const AdminScreen(),
    ),
    GoRoute(
      path: '/profile',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const UserProfileScreen(),
    ),
  ],
);

final _eventDetailPath = RegExp(r'^/event/[^/]+$');

String? authRedirect(AuthRepository auth, Uri uri) {
  final atLogin = uri.path == '/login';
  // 只有首頁與場次詳情（/event/:id）開放未登入瀏覽；編輯等子頁面需要登入。
  final publicPage = uri.path == '/' || _eventDetailPath.hasMatch(uri.path);
  if (!auth.isAuthenticated && !publicPage) {
    return atLogin
        ? null
        : Uri(
            path: '/login',
            queryParameters: {'from': uri.toString()},
          ).toString();
  }
  return atLogin ? safeReturnLocation(uri.queryParameters['from']) : null;
}

String safeReturnLocation(String? location) {
  final uri = Uri.tryParse(location ?? '/');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path.contains(String.fromCharCode(92)) ||
      uri.path == '/login') {
    return '/';
  }
  return uri.toString();
}
