import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'recipe_detail_screen.dart';

class ChatAssistantScreen extends StatefulWidget {
  final List<int>? initialIngredientIds;

  const ChatAssistantScreen({super.key, this.initialIngredientIds});

  @override
  State<ChatAssistantScreen> createState() => _ChatAssistantScreenState();
}

class _ChatAssistantScreenState extends State<ChatAssistantScreen> {
  static const String _chatStorageKey = 'quickcook_assistant_chat_v1';
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  bool _sending = false;
  Timer? _typingTimer;

  static const List<String> _quickPrompts = <String>[
    "What can I cook now?",
    "Trending recipes",
    "Substitute for milk",
    "How many recipes do we have?",
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_restoreChatHistory());
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatStorageKey);
    if (raw == null || raw.isEmpty) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
                "Hi! I am your QuickCook assistant. Ask me what to cook, substitutions, trending recipes, or recipe ingredients.",
            isUser: false,
          ),
        );
      });
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final restored = list
          .map((e) => _ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(restored);
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(
            _ChatMessage(
              text:
                  "Hi! I am your QuickCook assistant. Ask me what to cook, substitutions, trending recipes, or recipe ingredients.",
              isUser: false,
            ),
          );
      });
    }
  }

  Future<void> _persistChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encodable = _messages
        .where((m) => !m.typing)
        .map((m) => m.toJson())
        .toList(growable: false);
    await prefs.setString(_chatStorageKey, jsonEncode(encodable));
  }

  Future<void> _animateAssistantReply({
    required String reply,
    required List<Map<String, dynamic>> suggestions,
  }) async {
    _typingTimer?.cancel();
    setState(() {
      _messages.add(
        _ChatMessage(
          text: "",
          isUser: false,
          suggestions: suggestions,
          typing: true,
        ),
      );
    });
    _scrollToBottom();

    final completer = Completer<void>();
    var index = 0;
    _typingTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      index = (index + 2).clamp(0, reply.length);
      final partial = reply.substring(0, index);
      setState(() {
        final last = _messages.last;
        _messages[_messages.length - 1] = last.copyWith(text: partial);
      });
      _scrollToBottom();
      if (index >= reply.length) {
        timer.cancel();
        setState(() {
          final last = _messages.last;
          _messages[_messages.length - 1] = last.copyWith(
            text: reply,
            typing: false,
          );
        });
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;
    await _persistChatHistory();
  }

  Future<void> _sendMessage(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _sending = true;
    });
    unawaited(_persistChatHistory());
    _messageController.clear();
    _scrollToBottom();

    try {
      final conversation = _messages
          .where((m) => !m.typing)
          .take(_messages.length - 1)
          .map((m) {
            final base = m.text.trim();
            if (!m.isUser && m.suggestions.isNotEmpty) {
              final names = m.suggestions
                  .map((s) => s['name']?.toString().trim() ?? '')
                  .where((n) => n.isNotEmpty)
                  .join(' | ');
              return <String, String>{
                'role': 'assistant',
                'content': names.isEmpty ? base : '$base\nSuggested recipes: $names',
              };
            }
            return <String, String>{
              'role': m.isUser ? 'user' : 'assistant',
              'content': base,
            };
          })
          .toList();
      final response = await ApiService.askCookingAssistant(
        message: text,
        ingredientIds: widget.initialIngredientIds,
        conversation: conversation.length > 12
            ? conversation.sublist(conversation.length - 12)
            : conversation,
      );
      final reply = (response['reply']?.toString().trim().isNotEmpty ?? false)
          ? response['reply'].toString().trim()
          : "I could not generate a reply right now.";
      final suggestions = (response['suggestions'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      if (!mounted) return;
      await _animateAssistantReply(reply: reply, suggestions: suggestions);
    } catch (e) {
      if (!mounted) return;
      await _animateAssistantReply(
        reply: e.toString().replaceFirst('Exception: ', ''),
        suggestions: const <Map<String, dynamic>>[],
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  List<InlineSpan> _markdownSpans(String text, Color color) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var isBullet = false;
      if (line.trimLeft().startsWith('- ')) {
        line = line.trimLeft().substring(2);
        isBullet = true;
      }
      if (isBullet) {
        spans.add(
          TextSpan(
            text: '• ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }
      final regex = RegExp(r'\*\*(.+?)\*\*');
      var start = 0;
      for (final match in regex.allMatches(line)) {
        if (match.start > start) {
          spans.add(
            TextSpan(
              text: line.substring(start, match.start),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: match.group(1),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        );
        start = match.end;
      }
      if (start < line.length) {
        spans.add(
          TextSpan(
            text: line.substring(start),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        );
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text("QuickCook Assistant"),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              scrollDirection: Axis.horizontal,
              itemCount: _quickPrompts.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final prompt = _quickPrompts[index];
                return ActionChip(
                  label: Text(prompt),
                  onPressed: () => _sendMessage(prompt),
                );
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment:
                      message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: message.isUser
                            ? cs.primary
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: message.isUser
                              ? cs.primary
                              : cs.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: _markdownSpans(
                                message.text,
                                message.isUser ? Colors.white : cs.onSurface,
                              ),
                            ),
                          ),
                          if (message.typing) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "typing...",
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (!message.isUser && message.suggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: message.suggestions.map((suggestion) {
                                final id =
                                    int.tryParse(suggestion['id']?.toString() ?? '') ??
                                        0;
                                final name =
                                    suggestion['name']?.toString() ?? 'Recipe';
                                return InkWell(
                                  onTap: id <= 0
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RecipeDetailScreen(recipeId: id),
                                            ),
                                          );
                                        },
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.restaurant_menu_rounded,
                                          size: 13,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          name,
                                          style: TextStyle(
                                            color: cs.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                      decoration: const InputDecoration(
                        hintText: 'Ask anything about recipes...',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: FilledButton(
                      onPressed: _sending
                          ? null
                          : () => _sendMessage(_messageController.text),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _sending
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Icon(Icons.send_rounded, color: cs.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool typing;
  final List<Map<String, dynamic>> suggestions;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.typing = false,
    this.suggestions = const <Map<String, dynamic>>[],
  });

  _ChatMessage copyWith({
    String? text,
    bool? isUser,
    bool? typing,
    List<Map<String, dynamic>>? suggestions,
  }) {
    return _ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      typing: typing ?? this.typing,
      suggestions: suggestions ?? this.suggestions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'is_user': isUser,
        'suggestions': suggestions,
      };

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    return _ChatMessage(
      text: json['text']?.toString() ?? '',
      isUser: json['is_user'] == true,
      suggestions: (json['suggestions'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const <Map<String, dynamic>>[],
    );
  }
}
