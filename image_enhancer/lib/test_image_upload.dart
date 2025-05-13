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
import 'package:http_parser/http_parser.dart';

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

  final String _baseUrl = Platform.isMacOS 
      ? 'http://127.0.0.1:8000'  // Use IP instead of localhost for macOS
      : 'http://localhost:8000';

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
    if (kIsWeb) {
      // Web platform
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_image.jpg');
        await tempFile.writeAsBytes(bytes);
        setState(() {
          _originalImage = tempFile;
          _enhancedImage = null;
        });
      }
    } else if (Platform.isMacOS || Platform.isWindows) {
      // Desktop platforms
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
      // Mobile platforms
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
    dio.options.connectTimeout = const Duration(seconds: 60);
    dio.options.receiveTimeout = const Duration(seconds: 60);
    dio.options.sendTimeout = const Duration(seconds: 60);
    
    try {
      final endpoint = _taskEndpoints[_selectedTask];
      if (endpoint == null) {
        throw Exception('Task chưa được hỗ trợ!');
      }
      final uri = '$_baseUrl$endpoint';
      logger.info('Sending request to: $uri');

      final file = _originalImage!;
      
      // Ensure file is an image and has proper extension
      final fileExtension = file.path.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'gif'].contains(fileExtension)) {
        throw Exception('File phải là ảnh (jpg, jpeg, png, hoặc gif)');
      }

      logger.info('File info:');
      logger.info('- Path: ${file.path}');
      logger.info('- Extension: $fileExtension');
      logger.info('- Size: ${await file.length()} bytes');

      // Read file as bytes
      final bytes = await file.readAsBytes();
      
      // Send file directly using multipart/form-data for all platforms
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'image.$fileExtension',
          contentType: MediaType('image', fileExtension == 'jpg' ? 'jpeg' : fileExtension),
        ),
      });

      logger.info('Sending form data with fields: ${formData.fields}');
      logger.info('Sending form data with files: ${formData.files}');

      final response = await dio.post(
        uri,
        data: formData,
        options: Options(
          validateStatus: (status) => status! < 500,
          headers: {
            'Accept': 'image/png',  // Expect PNG response
          },
          responseType: ResponseType.bytes,  // Expect binary response
        ),
      );
      
      if (response.statusCode == 200) {
        // Save the response bytes as an image file
        final dir = await getTemporaryDirectory();
        final enhancedFile = File('${dir.path}/enhanced_image.png');
        await enhancedFile.writeAsBytes(response.data);
        setState(() => _enhancedImage = enhancedFile);
      } else {
        final errorMessage = response.data is List 
            ? String.fromCharCodes(response.data)
            : response.data.toString();
        throw Exception('Failed to enhance image: ${response.statusCode} - $errorMessage');
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
        title: const Text('AI Nâng Cao Chất Lượng Ảnh'),
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
