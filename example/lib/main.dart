import 'package:flutter/material.dart';
import 'package:hailbell/hailbell.dart';

/// The platform's App ID from the Hailbell dashboard. Pass it when you run the example:
///
///     flutter run --dart-define=HAILBELL_APP_ID=app_...
const appId = String.fromEnvironment('HAILBELL_APP_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (appId.isNotEmpty) await HailbellSupport.configure();
  runApp(const ExampleApp());
}

/// Every Hailbell call in one place, so an empty App ID turns the chat off and hides its entry points.
class HailbellSupport {
  static bool get isEnabled => appId.isNotEmpty;

  static Future<void> configure() async {
    // Set before configure, so a tap that launched the app reaches it.
    HailbellPush.onOpen = (notification) {
      debugPrint('Hailbell push tapped: ${notification.url}');
      return false; // false: Hailbell opens the link
    };
    await Hailbell.configure(appId: appId);
    await Hailbell.setMetadata({'plan': 'free', 'appVersion': '1.0.0 (1)'});
    await Hailbell.setPaywallPlacements(['support_offer', 'winback']);
    Hailbell.onPaywall = (placement, purchased) {
      // Open your paywall for `placement` here, and call purchased() if they buy.
      debugPrint('Hailbell offer tapped: $placement');
    };
  }

  /// `source` names the button, so the dashboard shows where people find the chat.
  static Future<void> open(String source) async {
    await Hailbell.track('chat_opened', properties: {'source': source});
    await Hailbell.open();
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hailbell example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B5BDB)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF3B5BDB), brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool? _canNotify;
  bool _marketing = false;
  bool? _dark = Hailbell.darkMode;

  @override
  void initState() {
    super.initState();
    if (HailbellSupport.isEnabled) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final allowed = await HailbellPush.canNotify();
    if (mounted) setState(() => _canNotify = allowed);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on HailbellException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hailbell: ${e.message ?? e.code}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!HailbellSupport.isEnabled) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Run with --dart-define=HAILBELL_APP_ID=app_... to try the chat.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [SupportButton(onPressed: () => HailbellSupport.open('profile_header'))],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Chat with us'),
            onTap: () => HailbellSupport.open('profile_row'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Sign in as a test user'),
            subtitle: const Text('identify with a name and email, no token'),
            onTap: () => _run(
              () => Hailbell.identify(userId: 'test-user', name: 'Test User', email: 'test@example.com'),
              'Identified',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('reset'),
            onTap: () => _run(Hailbell.reset, 'Back to the anonymous chat'),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Become Pro'),
            subtitle: const Text('setMetadata and push tags'),
            onTap: () => _run(() async {
              await Hailbell.setMetadata({'plan': 'pro'});
              await HailbellPush.setTags({'plan': 'pro'});
            }, 'Plan set to pro'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Close a paywall'),
            subtitle: const Text('track paywall_decline'),
            onTap: () => _run(
              () => Hailbell.track('paywall_decline', properties: {'placement': 'onboarding'}),
              'Signal sent',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(switch (_canNotify) {
              null => 'Checking…',
              true => 'Allowed',
              false => 'Not allowed. Tap to ask.',
            }),
            onTap: () async {
              await HailbellPush.requestPermission();
              await _refreshPermission();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_offer_outlined),
            title: const Text('Offers and updates'),
            subtitle: const Text('setMarketing'),
            value: _marketing,
            onChanged: (on) {
              setState(() => _marketing = on);
              HailbellPush.setMarketing(on);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Chat look'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<bool?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Phone')),
                  ButtonSegment(value: false, label: Text('Light')),
                  ButtonSegment(value: true, label: Text('Dark')),
                ],
                selected: {_dark},
                onSelectionChanged: (choice) {
                  setState(() => _dark = choice.single);
                  Hailbell.darkMode = choice.single;
                },
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: const Text('Delete my account'),
            subtitle: const Text('deleteData'),
            onTap: () => _run(Hailbell.deleteData, 'Chat deleted from Hailbell'),
          ),
        ],
      ),
    );
  }
}

/// A headset button with a red dot while there are unread replies.
class SupportButton extends StatelessWidget {
  const SupportButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Hailbell.unreadCount,
      builder: (context, unread, _) => IconButton(
        tooltip: unread > 0 ? 'Chat with us, $unread unread' : 'Chat with us',
        onPressed: onPressed,
        icon: Badge(isLabelVisible: unread > 0, smallSize: 9, child: const Icon(Icons.headset_mic_outlined)),
      ),
    );
  }
}
