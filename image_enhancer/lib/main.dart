// Flutter App: Ứng dụng nâng cao chất lượng ảnh
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'dart:convert';
import 'dart:math';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: ImageEnhancer(),
    );
  }
}

class ImageEnhancer extends StatefulWidget {
  const ImageEnhancer({super.key});

  @override
  ImageEnhancerState createState() => ImageEnhancerState();
}

class ImageEnhancerState extends State<ImageEnhancer> {
  File? _originalImage;
  File? _enhancedImage;
  bool _isLoading = false;
  String _selectedTask = 'derain';
  int _retryCount = 0;
  static const int _maxRetries = 3;
  final List<String> _tasks = [
    'derain',
    'gaussian_denoise',
    'real_denoise',
    'motion_deblur',
    'single_image_deblur',
  ];

  final Map<String, String> _taskEndpoints = {
    'derain': '/derain',
    'gaussian_denoise': '/gaussian-denoise',
    'real_denoise': '/real-denoise',
    // 'motion_deblur': '/motion-deblur',
    // 'single_image_deblur': '/single-image-deblur',
  };

  final String _baseUrl = 'http://localhost:8000';

  Future<void> _testConnection() async {
    final logger = Logger('TestConnection');
    _retryCount = 0;
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      dio.options.headers = {
        'Accept': 'application/json',
        'Connection': 'keep-alive',
      };
      
      logger.info('Testing connection to: $_baseUrl');
      
      final response = await dio.get(
        '$_baseUrl/',
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );
      
      logger.info('Connection test status: ${response.statusCode}');
      logger.info('Connection test response: ${response.data}');
      
      if (response.statusCode == 200 && response.data['status'] == 'ok') {
        logger.info('Connection test successful');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kết nối thành công!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        logger.severe('Server response indicates error: ${response.data}');
        throw Exception('Server response indicates error: ${response.data}');
      }
    } on DioException catch (e) {
      logger.severe('Connection test failed: ${e.message}');
      logger.severe('Error type: ${e.type}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể kết nối đến server: ${e.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _testConnection();
  }

  Future<void> _pickImage() async {
    if (Platform.isMacOS || Platform.isWindows || kIsWeb) {
      // Dùng file_picker cho macOS, Windows, hoặc web
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _originalImage = File(result.files.single.path!);
          _enhancedImage = null;
        });
      }
    } else {
      // Dùng image_picker cho iOS/Android
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        setState(() {
          _originalImage = File(pickedFile.path);
          _enhancedImage = null;
        });
      }
    }
  }

  Future<void> _enhanceImage() async {
    if (_originalImage == null) return;
    setState(() => _isLoading = true);
    _retryCount = 0;

    final logger = Logger('ImageEnhancer');
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Connection': 'keep-alive',
    };
    
    logger.info('Starting image enhancement...');
    logger.info('Base URL: $_baseUrl');
    logger.info('Headers: ${dio.options.headers}');
    
    // Add retry interceptor with limits
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          logger.info('Making request to: ${options.uri}');
          logger.info('Request method: ${options.method}');
          logger.info('Request headers: ${options.headers}');
          return handler.next(options);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) {
          logger.info('Received response:');
          logger.info('- Status code: ${response.statusCode}');
          logger.info('- Headers: ${response.headers}');
          logger.info('- Data: ${response.data}');
          return handler.next(response);
        },
        onError: (DioException e, ErrorInterceptorHandler handler) async {
          logger.warning('Error type: ${e.type}');
          logger.warning('Error message: ${e.message}');
          logger.warning('Request path: ${e.requestOptions.path}');
          logger.warning('Request method: ${e.requestOptions.method}');
          logger.warning('Request headers: ${e.requestOptions.headers}');
          
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.unknown) {
            if (_retryCount < _maxRetries) {
              _retryCount++;
              logger.warning('Connection failed, retrying... (Attempt $_retryCount/$_maxRetries)');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Đang thử kết nối lại... (Lần $_retryCount/$_maxRetries)'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              await Future.delayed(Duration(seconds: pow(2, _retryCount - 1).toInt())); // Exponential backoff
              try {
                final response = await dio.request(
                  e.requestOptions.path,
                  options: Options(
                    method: e.requestOptions.method,
                    headers: e.requestOptions.headers,
                    validateStatus: e.requestOptions.validateStatus,
                  ),
                  data: e.requestOptions.data,
                  queryParameters: e.requestOptions.queryParameters,
                );
                return handler.resolve(response);
              } catch (e) {
                return handler.next(e as DioException);
              }
            } else {
              logger.severe('Max retries reached. Connection failed.');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Không thể kết nối đến server sau nhiều lần thử. Vui lòng kiểm tra kết nối mạng và thử lại.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            }
          }
          return handler.next(e);
        },
      ),
    );
    
    try {
      final endpoint = _taskEndpoints[_selectedTask];
      if (endpoint == null) {
        throw Exception('Task chưa được hỗ trợ!');
      }
      final uri = '$_baseUrl$endpoint';
      logger.info('Sending request to: $uri');

      final file = _originalImage!;
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      logger.info('File info:');
      logger.info('- Path: ${file.path}');
      logger.info('- Size: ${bytes.length} bytes');
      logger.info('- Base64 length: ${base64Image.length}');

      try {
        final response = await dio.post(
          uri,
          data: {
            'image': base64Image,
            'task': _selectedTask,
          },
          options: Options(
            validateStatus: (status) => status! < 500,
            followRedirects: true,
            maxRedirects: 5,
          ),
        );

        logger.info('Response status code: ${response.statusCode}');
        logger.info('Response data: ${response.data}');

        if (response.statusCode == 200 && response.data['enhanced_image'] != null) {
          final responseData = response.data;
          final enhancedImageBase64 = responseData['enhanced_image'];
          final enhancedImageBytes = base64Decode(enhancedImageBase64);
          
          logger.info('Enhanced image info:');
          logger.info('- Base64 length: ${enhancedImageBase64.length}');
          logger.info('- Bytes length: ${enhancedImageBytes.length}');
          
          final dir = await getTemporaryDirectory();
          final enhancedFile = File('${dir.path}/enhanced_image.png');
          await enhancedFile.writeAsBytes(enhancedImageBytes);
          setState(() => _enhancedImage = enhancedFile);
        } else {
          logger.severe('Invalid response: ${response.data}');
          throw Exception('Failed to enhance image: ${response.statusCode} - ${response.data}');
        }
      } on DioException catch (e) {
        logger.severe('Network error: ${e.message}');
        logger.severe('Error type: ${e.type}');
        logger.severe('Request path: ${e.requestOptions.path}');
        logger.severe('Request method: ${e.requestOptions.method}');
        logger.severe('Request headers: ${e.requestOptions.headers}');
        throw Exception('Network error: ${e.message}');
      }
    } catch (e) {
      logger.severe('Error during image enhancement: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildImageSection() {
    if (_originalImage == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Chưa chọn ảnh',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      );
    }
    return Column(
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  'Ảnh gốc',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_originalImage!, height: 200),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        if (_enhancedImage != null)
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                    'Ảnh sau khi xử lý',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_enhancedImage!, height: 200),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI Nâng Cao Chất Lượng Ảnh'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(child: _buildImageSection()),
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Đang xử lý ảnh...'),
                    ],
                  ),
                ),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: Icon(Icons.image),
                            label: Text("Chọn ảnh"),
                            onPressed: _pickImage,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            icon: Icon(Icons.auto_fix_high),
                            label: Text("Xử lý ảnh"),
                            onPressed:
                                _originalImage == null ? null : _enhanceImage,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedTask,
                          items:
                              _tasks.map((task) {
                                return DropdownMenuItem(
                                  value: task,
                                  child: Text(
                                    task.replaceAll('_', ' ').toUpperCase(),
                                    style: TextStyle(fontSize: 16),
                                  ),
                                );
                              }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedTask = value!;
                            });
                          },
                          isExpanded: true,
                          underline: SizedBox(),
                          icon: Icon(Icons.arrow_drop_down),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
