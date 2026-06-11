import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class WeatherInfo {
  final String emoji;
  final String temperature;
  final String message;

  WeatherInfo({
    required this.emoji,
    required this.temperature,
    required this.message,
  });
}

class WeatherService {
  static Future<WeatherInfo?> fetchCurrentWeather() async {
    try {
      double lat = 37.5665; // Seoul default
      double lon = 126.9780;

      // Try to get last known position silently without requesting permission
      try {
        final position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          lat = position.latitude;
          lon = position.longitude;
        }
      } catch (e) {
        // Ignore location errors and use default
      }

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true');
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final temp = current['temperature'].toString();
        final code = current['weathercode'] as int;

        return _parseWeatherCode(code, temp);
      }
    } catch (e) {
      // Ignore errors to not block UI
    }
    return null;
  }

  static WeatherInfo _parseWeatherCode(int code, String temp) {
    // WMO Weather interpretation codes
    if (code == 0 || code == 1) {
      return WeatherInfo(
        emoji: '☀️',
        temperature: temp,
        message: '오늘도 맑은 하루네요! 기분 좋은 안전운행 하세요 ☀️',
      );
    } else if (code == 2 || code == 3 || code == 45 || code == 48) {
      return WeatherInfo(
        emoji: '☁️',
        temperature: temp,
        message: '잔뜩 흐린 날씨입니다. 혹시 모르니 우산을 챙겨주세요 ☁️',
      );
    } else if (code >= 51 && code <= 67 || code >= 80 && code <= 82) {
      return WeatherInfo(
        emoji: '☔',
        temperature: temp,
        message: '비가 내립니다! 콜 단가와 수요가 폭발하는 날 ☔ 안전운전은 필수!',
      );
    } else if (code >= 71 && code <= 77 || code == 85 || code == 86) {
      return WeatherInfo(
        emoji: '❄️',
        temperature: temp,
        message: '눈이 오네요 ⛄ 빙판길이 미끄러우니 무리한 콜은 피하고 안전 최우선!',
      );
    } else if (code >= 95 && code <= 99) {
      return WeatherInfo(
        emoji: '⚡',
        temperature: temp,
        message: '천둥번개가 칩니다 ⚡ 기상 악화 시에는 시야 확보에 각별히 주의하세요.',
      );
    } else {
      return WeatherInfo(
        emoji: '🌤️',
        temperature: temp,
        message: '안전하고 행복한 운행 되세요!',
      );
    }
  }
}
