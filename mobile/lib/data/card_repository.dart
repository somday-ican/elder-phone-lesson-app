import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/skill_card.dart';

class CardRepository {
  const CardRepository();

  static const _filename = 'skill_cards.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_filename');
  }

  Future<List<SkillCard>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      return SkillCard.decodeList(content);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<SkillCard> cards) async {
    final file = await _getFile();
    await file.writeAsString(SkillCard.encodeList(cards));
  }

  Future<void> add(SkillCard card) async {
    final cards = await loadAll();
    cards.insert(0, card); // newest first
    await saveAll(cards);
  }

  Future<void> remove(String id) async {
    final cards = await loadAll();
    cards.removeWhere((c) => c.id == id);
    await saveAll(cards);
  }

  Future<void> rename(String id, String newTitle) async {
    final cards = await loadAll();
    final index = cards.indexWhere((c) => c.id == id);
    if (index == -1) return;
    cards[index] = cards[index].copyWith(title: newTitle);
    await saveAll(cards);
  }

  Future<void> incrementPractice(String id) async {
    final cards = await loadAll();
    final index = cards.indexWhere((c) => c.id == id);
    if (index == -1) return;
    cards[index] = cards[index].copyWith(
      timesPracticed: cards[index].timesPracticed + 1,
    );
    await saveAll(cards);
  }
}
