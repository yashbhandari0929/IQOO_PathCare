import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';

class GeminiRAGService {
  late final GenerativeModel _chatModel;
  late final GenerativeModel _embeddingModel;
  final _supabase = Supabase.instance.client;

  GeminiRAGService() {
    final apiKey = EnvConfig.geminiApiKey;
    if (apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in EnvConfig');
    }

    _chatModel = GenerativeModel(model: 'gemini-3.6-flash', apiKey: apiKey);

    _embeddingModel = GenerativeModel(
      model: 'text-embedding-004',
      apiKey: apiKey,
    );
  }

  /// Split text into chunks of approx 600 characters
  List<String> _chunkText(String text, {int chunkSize = 600}) {
    final words = text.split(RegExp(r'\s+'));
    final List<String> chunks = [];
    String currentChunk = '';

    for (var word in words) {
      if ((currentChunk.length + word.length) > chunkSize) {
        chunks.add(currentChunk.trim());
        currentChunk = '$word ';
      } else {
        currentChunk += '$word ';
      }
    }
    if (currentChunk.trim().isNotEmpty) {
      chunks.add(currentChunk.trim());
    }
    return chunks;
  }

  /// Process an uploaded document: Chunk, Embed, and Store in Supabase
  Future<void> processDocument(
    String patientId,
    String text,
    String reportId,
  ) async {
    final chunks = _chunkText(text);

    for (int i = 0; i < chunks.length; i++) {
      final chunkText = chunks[i];
      try {
        final content = Content.text(chunkText);
        final result = await _embeddingModel.embedContent(content);
        final embedding = result.embedding.values;

        await _supabase.from('report_embeddings').insert({
          'patient_id': patientId,
          'report_id': reportId,
          'chunk_index': i,
          'chunk_text': chunkText,
          'embedding': embedding,
        });
      } catch (e) {}
    }
  }

  /// Retrieve context using vector similarity search
  Future<String> _retrieveContext(String query, String patientId) async {
    try {
      final content = Content.text(query);
      final result = await _embeddingModel.embedContent(content);
      final queryEmbedding = result.embedding.values;

      final response = await _supabase.rpc(
        'match_report_chunks',
        params: {
          'query_embedding': queryEmbedding,
          'match_threshold': 0.7,
          'match_count': 5,
          'p_patient_id': patientId,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final List<String> contexts = [];
        for (var row in response) {
          contexts.add(row['chunk_text'] as String);
        }
        return contexts.join('\n\n');
      }
    } catch (e) {}
    return '';
  }

  /// Generate RAG response based on Role and retrieved Context
  Future<String> generateResponse({
    required String userId,
    required String userRole,
    required String userMessage,
    String? currentDocumentText,
  }) async {
    // Base System Prompt based on role and whether a document was uploaded
    String systemPrompt =
        "You are an expert, professional healthcare AI assistant.\n\n"
        "MEDICATION SAFETY RULES:\n"
        "- Allowed: General medication information, side effects, precautions, when medicines are commonly used, and home care advice.\n"
        "- STRICTLY FORBIDDEN: NEVER prescribe medicines, NEVER give dosages, NEVER diagnose diseases, and NEVER recommend antibiotics or prescription drugs.\n"
        "- Always advise consulting a healthcare professional for a formal diagnosis or prescription.\n\n"
        "CONVERSATION STYLE:\n"
        "- Use beautifully structured Markdown.\n"
        "- Use short paragraphs, bullet points, and headings.\n"
        "- Use emojis ONLY for section headers (do not overuse them).\n"
        "- Keep responses friendly and professional. Avoid long walls of text.\n\n";

    if (currentDocumentText != null && currentDocumentText.isNotEmpty) {
      // Prompt for Medical Report Analysis
      systemPrompt +=
          "A MEDICAL REPORT HAS BEEN UPLOADED. You MUST return your response in EXACTLY this Markdown format. DO NOT USE HTML:\n\n"
          "# 🩺 Report Analysis\n\n"
          "## Overall Summary\n"
          "Short 2–3 sentence explanation in simple English.\n\n"
          "---\n\n"
          "## Key Findings\n"
          "Render as a Markdown table (DO NOT use HTML tags):\n"
          "| Test | Result | Normal | Status |\n"
          "| --- | --- | --- | --- |\n"
          "| (Test Name) | **(Value)** | (Range) | 🔶 (Status) |\n"
          "Values must appear bold. Use emojis like 🔶 for abnormal and ✅ for normal in the Status column.\n\n"
          "---\n\n"
          "## Easy Explanation\n"
          "Explain every abnormal value individually using ### for headings.\n\n"
          "---\n\n"
          "## What's Normal\n"
          "List as bullet points.\n"
          "Show only healthy parameters.\n\n"
          "---\n\n"
          "## General Health Tips\n"
          "List as bullet points.\n"
          "General advice only.\n\n"
          "---\n\n"
          "## Disclaimer\n"
          "Educational use only. Consult a qualified healthcare professional for diagnosis.\n\n";
    } else {
      // Prompt for Generic Health Queries
      systemPrompt +=
          "NO REPORT UPLOADED. You are acting as a Smart Medical Assistant responding to a general health query.\n"
          "Answer normal health questions (e.g., Headache remedies, Fever care, Diabetes info, Diet, Mental wellness, First aid).\n"
          "Structure your response nicely with valid GitHub Markdown (headings, bullet points, tables if necessary). DO NOT output HTML.\n\n";
    }

    if (userRole == 'doctor') {
      systemPrompt +=
          "ROLE MODIFIER (DOCTOR): Provide a clinical summary, trend comparison with past reports, and concise overview using medical terminology.\n";
    } else if (userRole == 'admin') {
      systemPrompt +=
          "ROLE MODIFIER (ADMIN): Provide operational analytics only. Do not provide unauthorized patient medical data.\n";
    } else {
      systemPrompt +=
          "ROLE MODIFIER (PATIENT): Use simple language, easy explanations, and lifestyle guidance. Avoid overly complex medical jargon.\n";
    }

    // Retrieve historical context
    String retrievedContext = await _retrieveContext(userMessage, userId);

    String finalPrompt = "System Instructions:\n$systemPrompt\n\n";

    if (currentDocumentText != null && currentDocumentText.isNotEmpty) {
      finalPrompt +=
          "Current Uploaded Document Text:\n$currentDocumentText\n\n";
    }

    if (retrievedContext.isNotEmpty) {
      finalPrompt +=
          "Previous Relevant Patient Records:\n$retrievedContext\n\n";
    }

    finalPrompt += "User Question:\n$userMessage";

    try {
      final response = await _chatModel.generateContent([
        Content.text(finalPrompt),
      ]);
      return response.text ?? 'No response generated.';
    } catch (e) {
      throw Exception('Unable to generate AI response. Please try again.');
    }
  }
}
