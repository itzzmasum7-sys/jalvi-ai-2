import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(const JalviApp());

const _native = MethodChannel('com.jalvi.ai/native');

class JalviApp extends StatelessWidget {
  const JalviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JALVI AI 2.0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070B14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF35C8FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AssistantHome(),
    );
  }
}

class AssistantHome extends StatefulWidget {
  const AssistantHome({super.key});

  @override
  State<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantHomeState extends State<AssistantHome> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final Battery _battery = Battery();
  final TextEditingController _command = TextEditingController();
  final List<String> _history = <String>[];
  List<Map<String, dynamic>> _sms = <Map<String, dynamic>>[];
  int _smsIndex = 0;
  bool _listening = false;
  bool _speaking = false;
  bool _speechReady = false;
  String _latestSpeechText = '';
  bool _voiceResultHandled = false;
  String _status = 'Ready';
  String _lastReply = 'Namaste! Main Jarvis hoon. Aap kya karna chahenge?';
  String _language = 'hi-IN';
  String _voice = 'female';
  String _aiEndpoint = '';
  String _aiToken = '';
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _language = prefs.getString('language') ?? 'hi-IN';
      _voice = prefs.getString('voice') ?? 'female';
      _aiEndpoint = prefs.getString('ai_endpoint') ?? 'https://jalvi-ai-brain.itzzmasum7.workers.dev';
      _aiToken = prefs.getString('ai_token') ?? '';
      _tokenController.text = _aiToken;
      _endpointController.text = _aiEndpoint;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _language);
    await prefs.setString('voice', _voice);
    await prefs.setString('ai_endpoint', _aiEndpoint);
    await prefs.setString('ai_token', _aiToken);
  }

  Future<void> _initTts() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(_voice == 'male' ? 0.85 : 1.05);
    await _tts.setLanguage(_language);
    _tts.setStartHandler(() {
      if (mounted) setState(() {
        _speaking = true;
        _status = 'Speaking';
      });
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() {
        _speaking = false;
        _status = 'Ready';
      });
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() {
        _speaking = false;
        _status = 'Ready';
      });
    });
  }

  Future<void> _say(String text) async {
    _lastReply = text;
    if (!mounted) return;
    setState(() => _status = 'Speaking');
    await _tts.stop();
    await _tts.setLanguage(_language);
    await _tts.setPitch(_voice == 'male' ? 0.85 : 1.05);
    await _tts.speak(text);
  }

  Future<void> _listen() async {
    if (_listening) return;
    try {
      await _tts.stop();
      await _speech.cancel();
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        await _say('Microphone permission nahi mili. App settings mein allow karein.');
        return;
      }
      _speechReady = await _speech.initialize(
        debugLogging: true,
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            final text = _latestSpeechText.trim();
            setState(() {
              _listening = false;
              _status = text.isEmpty ? 'Ready - dobara mic dabayein' : 'Processing';
            });
            if (text.isNotEmpty && !_voiceResultHandled) {
              _voiceResultHandled = true;
              _handleCommand(text);
            }
          } else if (status == 'listening') {
            setState(() {
              _listening = true;
              _status = 'Listening... boliye';
            });
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _status = 'Voice error: ${error.errorMsg}';
          });
        },
      );
      if (!_speechReady) {
        await _say('Speech service available nahi hai. Google app mein Speech Recognition update ya enable karein.');
        return;
      }

      final locales = await _speech.locales();
      final ids = locales.map((locale) => locale.localeId.toLowerCase().replaceAll('_', '-')).toList();
      final preferred = _language.toLowerCase().replaceAll('_', '-');
      String? speechLocale;
      if (ids.contains(preferred)) {
        speechLocale = locales[ids.indexOf(preferred)].localeId;
      } else {
        final languagePrefix = preferred.split('-').first;
        final match = locales.indexWhere((locale) =>
            locale.localeId.toLowerCase().replaceAll('_', '-').startsWith('$languagePrefix-'));
        if (match >= 0) {
          speechLocale = locales[match].localeId;
        } else {
          final hindi = ids.indexOf('hi-in');
          final english = ids.indexOf('en-in');
          if (hindi >= 0) speechLocale = locales[hindi].localeId;
          else if (english >= 0) speechLocale = locales[english].localeId;
        }
      }

      _latestSpeechText = '';
      _voiceResultHandled = false;
      if (mounted) {
        setState(() {
          _listening = true;
          _status = 'Listening... ab boliye';
        });
      }
      await _speech.listen(
        localeId: speechLocale,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _latestSpeechText = words;
            _command.text = words;
          }
          if (result.finalResult && words.isNotEmpty && !_voiceResultHandled) {
            _voiceResultHandled = true;
            setState(() {
              _listening = false;
              _status = 'Processing: $words';
            });
            _handleCommand(words);
          }
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _status = 'Voice start failed: $error';
        });
      }
      await _say('Voice start nahi ho payi. Microphone permission aur Google speech service check karein.');
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _listening = false;
      _status = 'Ready';
    });
  }

  String _normal(String s) => s.toLowerCase().trim();

  Future<void> _handleCommand(String raw) async {
    final q = _normal(raw);
    if (q.isEmpty) return;
    setState(() {
      _history.insert(0, 'You: $raw');
      if (_history.length > 30) _history.removeLast();
    });

    if (q == 'ruko' || q.contains('chup') || q.contains('stop reading')) {
      await _tts.stop();
      await _stopListening();
      await _say('Theek hai, rok diya.');
      return;
    }
    if (q == 'agla' || q.contains('next message') || q.contains('agla message')) {
      await _readSmsAt(_smsIndex + 1);
      return;
    }
    if (q.contains('pichhla') || q.contains('previous message')) {
      await _readSmsAt(_smsIndex - 1);
      return;
    }
    if (q.contains('dobara') || q.contains('repeat')) {
      if (_sms.isNotEmpty) {
        await _readSmsAt(_smsIndex);
      } else {
        await _say(_lastReply);
      }
      return;
    }
    if (q == 'padho' || q.contains('sms padho') || q.contains('message padho')) {
      if (_sms.isEmpty) await _loadSms();
      if (_sms.isNotEmpty) await _readSmsAt(_smsIndex);
      return;
    }
    // Only explicit SMS-reading phrases open the inbox. Ordinary conversation
    // containing the word "message" must go to the AI assistant.
    if (q == 'sms' || q == 'read sms' || q.contains('sms padho') ||
        q.contains('sms dikhao') || q.contains('sms read') ||
        q.contains('message padho') || q.contains('messages padho') ||
        q.contains('मैसेज पढ़ो') || q.contains('एसएमएस पढ़ो') ||
        q.contains('inbox padho')) {
      await _loadSms();
      return;
    }
    final hasTorchWord = q.contains('torch') ||
        q.contains('torucg') ||
        q.contains('टॉर्च') ||
        q.contains('flashlight') ||
        q.contains('flash light') ||
        q.contains('flash');
    final wantsTorchOn = q.contains('on') ||
        q.contains('chalu') ||
        q.contains('चालू') ||
        q.contains('जलाओ') ||
        q.contains('जला दो') ||
        q.contains('ऑन');
    final wantsTorchOff = q.contains('off') ||
        q.contains('band') ||
        q.contains('बंद') ||
        q.contains('बुझा') ||
        q.contains('ऑफ');
    if (hasTorchWord && wantsTorchOn) {
      await _torch(true);
      return;
    }
    if (hasTorchWord && wantsTorchOff) {
      await _torch(false);
      return;
    }
    if (q.contains('notification access') || q.contains('notification permission') || q.contains('notification setting')) {
      try {
        await _native.invokeMethod('openNotificationAccess');
        await _say('Notification access settings khol raha hoon. JALVI ko list mein allow karein.');
      } on PlatformException {
        await _say('Notification access settings nahi khul payi.');
      }
      return;
    }
    if (q.contains('notification padho') || q.contains('notifications padho') ||
        q.contains('read notification') || q.contains('read notifications') ||
        q.contains('notification dikhao') || q.contains('सूचना पढ़ो') || q.contains('नोटिफिकेशन पढ़ो')) {
      try {
        final items = await _native.invokeMethod<List<dynamic>>('getRecentNotifications');
        final notices = (items ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (notices.isEmpty) {
          await _say('Koi notification available nahi hai. Pehle notification access settings mein JALVI ko allow karein.');
        } else {
          final lines = notices.take(5).map((n) => '${n['app']}: ${n['title']}. ${n['text']}').join('. ');
          await _say(lines);
        }
      } on PlatformException {
        await _say('Notification read nahi ho paya. Notification access settings mein JALVI ko allow karein.');
      }
      return;
    }
    if (q.contains('settings') || q.contains('setting') || q.contains('सेटिंग')) {
      try {
        await _native.invokeMethod('openSettings');
        await _say('Phone settings khol raha hoon.');
      } on PlatformException {
        await _say('Phone settings nahi khul payi.');
      }
      return;
    }
    if (q.contains('battery') || q.contains('बैटरी')) {
      final level = await _battery.batteryLevel;
      await _say('Aapke phone ki battery $level percent hai.');
      return;
    }
    // Search YouTube for explicit media requests instead of merely opening its home screen.
    final asksYoutube = ['youtube', 'you tube', 'यूट्यूब', 'यू ट्यूब'].any(q.contains);
    final asksToPlay = ['play', 'search', 'chalao', 'chala do', 'bajao', 'gaana',
      'song', 'music', 'movie', 'video', 'चलाओ', 'बजाओ', 'गाना', 'फिल्म', 'मूवी']
      .any(q.contains);
    if (asksYoutube && asksToPlay) {
      var searchTerm = raw
          .replaceAll(RegExp(r'youtube|you tube|यूट्यूब|यू ट्यूब', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\b(?:please|play|search|on|in|open|chalao|chala do|bajao|gaana|song|music|movie|video)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'चलाओ|बजाओ|गाना|फिल्म|मूवी|चलाओ'), ' ')
          .replaceAll(RegExp(r'\b(?:pe|par|mein|me|ko|karo|do)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (searchTerm.isEmpty) {
        await _say('YouTube par kya search karna hai?');
      } else {
        try {
          await _native.invokeMethod('searchYoutube', {'query': searchTerm});
          await _say('YouTube par $searchTerm search kar raha hoon. Video aap select kar sakte hain.');
        } on PlatformException {
          await _say('YouTube search open nahi ho paya.');
        }
      }
      return;
    }
    // Handle common app-opening commands locally.
    if (asksYoutube) {
      await _openApp('com.google.android.youtube', 'YouTube');
      return;
    }
    if (['whatsapp', 'whatapp', 'whats app', "what's app", 'व्हाट्सएप',
      'व्हाट्स ऐप', 'वाट्सएप', 'वाट्स ऐप'].any(q.contains)) {
      await _openApp('com.whatsapp', 'WhatsApp');
      return;
    }
    if (['instagram', 'insta gram', 'इंस्टाग्राम', 'इंस्टा ग्राम'].any(q.contains)) {
      await _openApp('com.instagram.android', 'Instagram');
      return;
    }
    if (['camera', 'कैमरा', 'कैमरा खोलो'].any(q.contains)) {
      await _openApp('com.sec.android.app.camera', 'Camera');
      return;
    }
    if (q.contains('call') || q.contains('phone karo') || q.contains('फोन करो') ||
        q.contains('number batao') || q.contains('number do') || q.contains('contact')) {
      final name = raw
          .replaceAll(RegExp(r'\b(call|phone|karo|karna|number|batao|bataiye|do|contact|ko|se|ka|ki|ke)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'फोन|करो|नंबर|बताओ|बताइए|कॉन्टैक्ट'), ' ')
          .trim();
      if (name.isEmpty) {
        await _say('Kis contact ka number chahiye? Naam bataiye.');
        return;
      }
      final permission = await Permission.contacts.request();
      if (!permission.isGranted) {
        await _say('Contact permission allow karna zaroori hai.');
        return;
      }
      try {
        final matches = await _native.invokeMethod<List<dynamic>>(
          'findContact', {'name': name});
        final contacts = (matches ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (contacts.isEmpty) {
          await _say('$name naam ka contact nahi mila.');
          return;
        }
        if (contacts.length > 1) {
          final options = contacts.take(3).map((c) => '${c['name']}: ${c['number']}').join('. ');
          await _say('Kai contacts mile. $options. Exact naam dobara boliye.');
          return;
        }
        final contact = contacts.first;
        final number = (contact['number'] ?? '').toString();
        await _say('${contact['name']}. Number $number. Dialer khol raha hoon. Call karne se pehle confirm karein.');
        await _native.invokeMethod('openDialer', {'number': number});
      } on PlatformException {
        await _say('Contact search nahi ho paya. Permission aur phone settings check karein.');
      }
      return;
    }
    if (q.contains('time') || q.contains('samay')) {
      final now = DateTime.now();
      await _say('Abhi ${now.hour} bajkar ${now.minute} minute hue hain.');
      return;
    }
    if (q.contains('hello') || q.contains('namaste') || q == 'jarvis') {
      await _say('Ji, main sun raha hoon. Bataiye.');
      return;
    }
    if (_aiEndpoint.trim().isNotEmpty) {
      await _askAi(raw);
    } else {
      await _say('AI brain connect nahi hai. Settings mein AI server URL add karein.');
    }
  }

  Future<void> _testAiConnection() async {
    final endpoint = _endpointController.text.trim();
    final token = _tokenController.text.trim();
    if (endpoint.isEmpty) {
      await _say('Pehle AI server URL enter karein.');
      return;
    }
    try {
      final uri = Uri.parse(endpoint);
      if (!uri.hasScheme || !uri.hasAuthority) {
        await _say('Server URL valid nahi hai.');
        return;
      }
      if (mounted) setState(() => _status = 'Testing AI connection');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'X-App-Token': token,
        },
        body: jsonEncode({
          'message': 'Reply exactly: JALVI AI connection successful.',
          'language': _language,
          'history': <String>[],
        }),
      ).timeout(const Duration(seconds: 35));
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          await _say('Server response JSON object nahi hai.');
          return;
        }
        data = decoded;
      } catch (_) {
        await _say('Server ne JSON response nahi diya. HTTP ${response.statusCode}.');
        return;
      }
      if (response.statusCode == 200 && data['reply'] != null) {
        await _say('Gemini AI connection successful. Server aur AI dono reply kar rahe hain.');
      } else {
        final error = (data['error'] ?? 'Unknown server error').toString();
        await _say('Connection test failed. HTTP ${response.statusCode}: $error');
      }
    } on Exception catch (e) {
      await _say('Connection test nahi hua. Internet, URL aur server check karein. $e');
    }
  }

  Future<void> _askAi(String prompt) async {
    try {
      final uri = Uri.parse(_aiEndpoint.trim());
      if (!uri.hasScheme || !uri.hasAuthority) {
        await _say('AI server URL sahi nahi hai. Settings check karein.');
        return;
      }
      if (mounted) setState(() => _status = 'Thinking');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (_aiToken.isNotEmpty) 'X-App-Token': _aiToken,
        },
        body: jsonEncode({
          'message': prompt,
          'language': _language,
          'history': _history.take(8).toList().reversed.toList(),
          'research': RegExp(r'\b(research|latest|news|today|current|search|find|who is|what happened)\b', caseSensitive: false).hasMatch(prompt) || ['research karo', 'internet par dekho', 'web par search', 'aaj ka', 'abhi ka', 'kya latest'].any(prompt.toLowerCase().contains),
        }),
      ).timeout(const Duration(seconds: 35));
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          await _say('AI server ka response format sahi nahi hai.');
          return;
        }
        data = decoded;
      } catch (_) {
        await _say('AI server ne readable JSON response nahi bheja. Worker code check karein.');
        return;
      }
      if (response.statusCode != 200) {
        final serverError = (data['error'] ?? 'Unknown server error').toString();
        await _say('AI server error ${response.statusCode}: $serverError');
        return;
      }
      final reply = (data['reply'] ?? 'Ji, bataiye.').toString();
      final action = (data['action'] ?? 'none').toString();
      final target = (data['target'] ?? '').toString();
      if (action != 'none') {
        await _executeAiAction(action, target, reply);
      } else {
        await _say(reply);
      }
    } on FormatException {
      await _say('AI server ka jawab samajh nahi aaya. Server response check karein.');
    } catch (e) {
      await _say('AI se connection nahi ho paya. Internet aur AI server URL check karein.');
    }
  }

  Future<void> _executeAiAction(String action, String target, String reply) async {
    switch (action) {
      case 'torch_on':
        await _torch(true);
        return;
      case 'torch_off':
        await _torch(false);
        return;
      case 'battery':
        final level = await _battery.batteryLevel;
        await _say('Aapke phone ki battery $level percent hai.');
        return;
      case 'time':
        final now = DateTime.now();
        await _say('Abhi ${now.hour} bajkar ${now.minute} minute hue hain.');
        return;
      case 'sms_read':
        if (_sms.isEmpty) await _loadSms();
        if (_sms.isNotEmpty) await _readSmsAt(_smsIndex);
        return;
      case 'open_app':
        const apps = <String, String>{
          'whatsapp': 'com.whatsapp',
          'youtube': 'com.google.android.youtube',
          'instagram': 'com.instagram.android',
          'camera': 'com.sec.android.app.camera',
        };
        final package = apps[target.toLowerCase()];
        if (package == null) {
          await _say('Is app ko kholne ki permission list mein nahi hai.');
        } else {
          await _openApp(package, target);
        }
        return;
      case 'open_settings':
        await _native.invokeMethod('openSettings');
        await _say(reply.isEmpty ? 'Phone settings khol raha hoon.' : reply);
        return;
      case 'open_dialer':
        await _say(reply.isEmpty ? 'Dialer khol raha hoon. Call aap khud confirm karein.' : reply);
        await _native.invokeMethod('openDialer', {'number': ''});
        return;
      default:
        await _say(reply);
    }
  }

  Future<void> _loadSms() async {
    final permission = await Permission.sms.request();
    if (!permission.isGranted) {
      await _say('SMS permission nahi mili. Aap Android settings se permission de sakte hain.');
      return;
    }
    try {
      final result = await _native.invokeMethod<List<dynamic>>('getRecentSms');
      _sms = (result ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _smsIndex = 0;
      if (_sms.isEmpty) {
        await _say('Inbox mein koi SMS available nahi mila.');
      } else {
        await _say('Aapke ${_sms.length} recent messages mile hain. Padhne ke liye Padho boliye.');
      }
      if (mounted) setState(() {});
    } on PlatformException catch (e) {
      await _say('SMS read nahi ho paya: ${e.message ?? 'unknown error'}');
    }
  }

  Future<void> _readSmsAt(int index) async {
    if (_sms.isEmpty) {
      await _loadSms();
      if (_sms.isEmpty) return;
      index = 0;
    }
    if (index < 0 || index >= _sms.length) {
      await _say('Aur koi message nahi hai.');
      return;
    }
    _smsIndex = index;
    final m = _sms[index];
    final sender = (m['name'] ?? '').toString().trim().isNotEmpty
        ? m['name'].toString()
        : (m['address'] ?? 'Unknown sender').toString();
    final body = (m['body'] ?? '').toString();
    final date = (m['date'] ?? '').toString();
    await _say('Message ${index + 1}. $sender. $body. $date');
  }

  Future<void> _torch(bool enabled) async {
    try {
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        await _say('Flashlight control ke liye camera permission allow karein.');
        return;
      }
      final changed = await _native.invokeMethod<bool>(
        'setTorch',
        {'enabled': enabled},
      );
      if (changed == true) {
        await _say(enabled ? 'Torch on kar diya.' : 'Torch off kar diya.');
      } else {
        await _say('Is phone ke camera mein flashlight available nahi mili.');
      }
    } on PlatformException catch (e) {
      await _say('Torch control nahi ho paya: ' + (e.message ?? 'camera error'));
    }
  }

  Future<void> _openApp(String package, String name) async {
    try {
      final ok = await _native.invokeMethod<bool>('openApp', {'package': package});
      await _say(ok == true ? '$name open kar raha hoon.' : '$name app nahi mili.');
    } catch (_) {
      await _say('$name open nahi ho paya.');
    }
  }

  Future<void> _submitText() async {
    final value = _command.text.trim();
    if (value.isEmpty) return;
    _command.clear();
    await _handleCommand(value);
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _command.dispose();
    _endpointController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JALVI AI 2.0', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _showSettings,
            icon: const Icon(Icons.tune_rounded),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(
              width: 184, height: 184,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xFF164D72), Color(0xFF07111F), Color(0xFF070B14)]),
                border: Border.all(color: const Color(0xFF35C8FF), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x5535C8FF), blurRadius: 35, spreadRadius: 3)],
              ),
              child: Icon(_listening ? Icons.graphic_eq : (_speaking ? Icons.volume_up_rounded : Icons.auto_awesome),
                size: 76, color: const Color(0xFF8CE5FF)),
            ),
            const SizedBox(height: 14),
            const Text('JARVIS', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, letterSpacing: 5)),
            Text(_status.toUpperCase(), style: const TextStyle(color: Color(0xFF7EDFFF), letterSpacing: 2, fontSize: 11)),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(child: TextField(
                    controller: _command,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitText(),
                    decoration: InputDecoration(
                      hintText: 'Jarvis ko command dein...',
                      filled: true,
                      fillColor: const Color(0xFF101A2A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    ),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _submitText,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(
                onPressed: _listening ? _stopListening : _listen,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(_listening ? 'Stop Listening' : 'Talk to Jarvis'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _say(_lastReply),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Repeat'),
              ),
            ]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                _quickAction(Icons.sms_rounded, 'SMS', () => _loadSms()),
                _quickAction(Icons.battery_charging_full, 'Battery', () async {
                  final b = await _battery.batteryLevel;
                  await _say('Battery $b percent hai.');
                }),
                _quickAction(Icons.flashlight_on_rounded, 'Torch', () => _torch(true)),
                _quickAction(Icons.apps_rounded, 'YouTube', () => _openApp('com.google.android.youtube', 'YouTube')),
              ]),
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFF1D2B3D)),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('RECENT ACTIVITY', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.white60))),
            ),
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text('Your commands will appear here.', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: _history.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.bolt_rounded, color: Color(0xFF69D9FF)),
                        title: Text(_history[i], style: const TextStyle(fontSize: 13)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback action) {
    return Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
        child: Column(children: [Icon(icon, size: 19), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10))]),
      ),
    ));
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101A2A),
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Assistant Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          const Text('Language'),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _language,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'hi-IN', child: Text('Hindi')),
              DropdownMenuItem(value: 'en-IN', child: Text('English (India)')),
              DropdownMenuItem(value: 'ur-PK', child: Text('Urdu')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _language = v);
              setSheet(() {});
              await _saveSettings();
              await _tts.setLanguage(v);
            },
          ),
          const SizedBox(height: 12),
          const Text('Voice preference'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'female', label: Text('Female'), icon: Icon(Icons.female)),
              ButtonSegment(value: 'male', label: Text('Male'), icon: Icon(Icons.male)),
            ],
            selected: {_voice},
            onSelectionChanged: (s) async {
              setState(() => _voice = s.first);
              setSheet(() {});
              await _saveSettings();
              await _tts.setPitch(_voice == 'male' ? 0.85 : 1.05);
            },
          ),
          const SizedBox(height: 16),
          const Text('AI brain server URL'),
          const SizedBox(height: 8),
          TextField(
            controller: _endpointController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://your-worker.example.workers.dev',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _aiEndpoint = v.trim(),
          ),
          const SizedBox(height: 8),
          const Text('App access token (provided by setup admin)'),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'App access token',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _aiToken = v.trim(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              _aiEndpoint = _endpointController.text.trim();
              _aiToken = _tokenController.text.trim();
              await _saveSettings();
              if (ctx.mounted) Navigator.pop(ctx);
              await _say(_aiEndpoint.isEmpty
                  ? 'AI server URL hata diya gaya.'
                  : 'AI server URL save ho gaya.');
            },
            child: const Text('Save AI Server URL'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testAiConnection,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Test Gemini Connection'),
          ),
          const SizedBox(height: 8),
          const Text('Wake word “Jarvis” background listening is not enabled yet.'),
          const SizedBox(height: 12),
        ]),
      )),
    );
  }
}
