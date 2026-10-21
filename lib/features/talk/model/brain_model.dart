import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// An on-device AI model Buddy can download and run.
class BrainModel {
  final String id, name, url, purpose;
  final int sizeMb;
  final ModelType type;
  const BrainModel(this.id, this.name, this.url, this.sizeMb, this.type, this.purpose);
}

// The older community "mixed_int4" build answered every question with a refusal; this is the official build.
const fastBrain = BrainModel(
  'qwen3-0.6b-v2',
  'Fast brain · Qwen 3 0.6B',
  'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
  585,
  ModelType.qwen3,
  'Quick replies: talks, spiritual guidance, life & money',
);

// The "-gpu" build failed to load on this phone's GPU and CPU; the standard build runs on CPU too.
const smartBrain = BrainModel(
  'gemma4-e2b-v2',
  'Smart brain · Gemma 4 E2B',
  'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  2468,
  ModelType.gemma4,
  'Deeper, more natural Hinglish answers; slower',
);

const codeBrain = BrainModel(
  'qwen25-coder-1.5b-int4',
  'Qwen 2.5 Coder 1.5B',
  'https://huggingface.co/litert-community/Qwen2.5-Coder-1.5B-Instruct/resolve/main/Qwen2.5-Coder-1.5B-Instruct_int4.litertlm',
  1117,
  ModelType.qwen,
  'Coding help: Flutter, Cocos/TypeScript, Unity/C#',
);

const allBrains = [fastBrain, smartBrain, codeBrain];
