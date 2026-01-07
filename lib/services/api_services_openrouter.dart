import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiOpenRouterService {
  late Dio _dio;

  ApiOpenRouterService() {
    final apiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_openrouter_api_key_here') {
      print('Warning: OpenRouter API key not configured. Please set OPENROUTER_API_KEY in .env file.');
    }
    
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://openrouter.ai/api/v1',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  Future<String> sendChatRequest(String question) async {
    final data = {
      "model": "meta-llama/llama-4-maverick:free",
      "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": question}
      ],
    };
    print("sendChatRequest------data----------$data--------");

    try {
      final response = await _dio.post('/chat/completions', data: data);

      if (response.statusCode == 200) {
          print("Response: ${response.data}");

          final data = response.data;
          final content = data['choices']?[0]?['message']?['content'] ?? "Unable to answer the question";
          return content;
      } else {
        print("Request failed with status: ${response.statusCode}");
        return "Request failed with status: ${response.statusCode}";
      }
    } on DioException catch (e) {
      if (e.response != null) {
        print("Error: ${e.response?.statusCode}, ${e.response?.data}");
        return "AI request error: ${e.response?.statusCode}, ${e.response?.data}";
      } else {
        print("Error: ${e.message}");
        return "AI request error: ${e.message}";
      }
    }
  }
}

