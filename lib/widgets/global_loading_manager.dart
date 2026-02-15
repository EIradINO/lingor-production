import 'package:flutter/material.dart';

class GlobalLoadingManager {
  static final GlobalLoadingManager _instance = GlobalLoadingManager._internal();
  factory GlobalLoadingManager() => _instance;
  GlobalLoadingManager._internal();

  ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  ValueNotifier<String?> _loadingMessage = ValueNotifier<String?>(null);

  ValueNotifier<bool> get isLoadingNotifier => _isLoading;
  ValueNotifier<String?> get loadingMessageNotifier => _loadingMessage;

  bool get isLoading => _isLoading.value;
  String? get loadingMessage => _loadingMessage.value;

  void showLoading({String? message}) {
    _loadingMessage.value = message;
    _isLoading.value = true;
  }

  void hideLoading() {
    _isLoading.value = false;
    _loadingMessage.value = null;
  }
} 