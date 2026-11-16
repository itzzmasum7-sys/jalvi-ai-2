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
  String _status = 'Ready';
  String _lastReply = 'Namaste! Main Jarvis hoon. Aap kya karna chahenge?';
  String _language = 'hi-IN';
  String _voice = 'female';
  String _aiEndpoint = '';
  final TextEditingController _endpointController = TextEditingController();

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
      _aiEndpoint = prefs.getString('ai_endpoint') ?? '';
      _endpointController.text = _aiEndpoint;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', _language);
    await prefs.setString('voice', _voice);
    await prefs.setString('ai_endpoint', _aiEndpoint);
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
    await _tts.stop();
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      await _say('Microphone permission nahi mili. Settings mein permission allow karein.');
      return;
    }
    try {
      _speechReady = await _speech.initialize(
        debugLogging: true,
        onStatus: (s) {
          if (!mounted) return;
          setState(() {
            _listening = s == 'listening';
            _status = (s == 'done' || s == 'notListening') ? 'Ready' : s;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _status = 'Voice error: ' + e.errorMsg;
          });
        },
      );
    } catch (e) {
      if (mounted) setState(() {
        _listening = false;
        _status = 'Voice unavailable';
      });
      await _say('Voice recognition start nahi ho paya. Google speech service aur microphone permission check karein.');
      return;
    }
    if (!_speechReady) {
      await _say('Speech recognition is device par available nahi hai.');
      return;
    }
    final available = await _speech.locales();
    final ids = available.map((e) => e.localeId).toSet();
    final speechLocale = ids.contains(_language)
        ? _language
        : (ids.contains('hi-IN') ? 'hi-IN' : (ids.contains('en-IN') ? 'en-IN' : null));
    setState(() {
      _listening = true;
      _status = 'Listening';
    });
    await _speech.listen(
      localeId: speechLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          _command.text = result.recognizedWords;
        }
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          setState(() {
            _listening = false;
            _status = 'Processing';
          });
          _handleCommand(result.recognizedWords);
        }
      },
    );
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
    if (q.contains('sms') || q.contains('message') || q.contains('मैसेज')) {
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
    if (q.contains('battery') || q.contains('बैटरी')) {
      final level = await _battery.batteryLevel;
      await _say('Aapke phone ki battery $level percent hai.');
      return;
    }
    if (q.contains('youtube')) {
      await _openApp('com.google.android.youtube', 'YouTube');
      return;
    }
    if (q.contains('whatsapp')) {
      await _openApp('com.whatsapp', 'WhatsApp');
      return;
    }
    if (q.contains('instagram')) {
      await _openApp('com.instagram.android', 'Instagram');
      return;
    }
    if (q.contains('camera')) {
      await _openApp('com.sec.android.app.camera', 'Camera');
      return;
    }
    if (q.contains('call') || q.contains('phone karo') || q.contains('फोन करो')) {
      await _say('Main dialer khol raha hoon. Contact select karke call confirm karein.');
      await _native.invokeMethod('openDialer', {'number': ''});
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': prompt,
          'language': _language,
          'history': _history.take(8).toList().reversed.toList(),
        }),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        await _say('AI server se response nahi mila. Thodi der baad try karein.');
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = (data['reply'] ?? 'Ji, bataiye.').toString();
      final action = (data['action'] ?? 'none').toString();
      final target = (data['target'] ?? '').toString();
      if (action != 'none') {
        await _executeAiAction(action, target, reply);
      } else {
        await _say(reply);
      }
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
        await _say('Abhi \${now.hour} bajkar \${now.minute} minute hue hain.');
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
          FilledButton(
            onPressed: () async {
              _aiEndpoint = _endpointController.text.trim();
              await _saveSettings();
              if (ctx.mounted) Navigator.pop(ctx);
              await _say(_aiEndpoint.isEmpty
                  ? 'AI server URL hata diya gaya.'
                  : 'AI server URL save ho gaya.');
            },
            child: const Text('Save AI Server URL'),
          ),
          const SizedBox(height: 8),
          const Text('Wake word “Jarvis” background listening is not enabled yet.'),
          const SizedBox(height: 12),
        ]),
      )),
    );
  }
}
