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
import 'package:http_parser/http_parser.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'dart:typed_data';

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
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const ImageEnhancer(),
    );
  }
}

class ImageEnhancer extends StatefulWidget {
  const ImageEnhancer({super.key});

  @override
  ImageEnhancerState createState() => ImageEnhancerState();
}

class ImageEnhancerState extends State<ImageEnhancer> with SingleTickerProviderStateMixin {
  File? _originalImage;
  File? _enhancedImage;
  bool _isLoading = false;
  String _selectedTask = 'derain';
  double _progress = 0.0;
  late AnimationController _comparisonController;
  Map<String, dynamic>? _imageInfo;
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
    _comparisonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _comparisonController.dispose();
    super.dispose();
  }

  Future<Directory> _getUserDocumentsDirectory() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/Users';
      return Directory('$home/Documents');
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users';
      return Directory('$userProfile\\Documents');
    } else {
      // fallback: app's document dir
      return await getApplicationDocumentsDirectory();
    }
  }

  Future<void> _saveEnhancedImage() async {
    if (_enhancedImage == null) return;

    try {
      if (kIsWeb) {
        // Handle web platform
        return;
      }

      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu ảnh',
        fileName: 'enhanced_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (savePath == null) return; // User cancelled

      final savedFile = await _enhancedImage!.copy(savePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu ảnh tại: ${savedFile.path}'),
            action: SnackBarAction(
              label: 'Chia sẻ',
              onPressed: () => Share.shareXFiles([XFile(savedFile.path)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu ảnh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _getImageInfo(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final size = bytes.length;
      final extension = path.extension(file.path).toLowerCase();
      
      setState(() {
        _imageInfo = {
          'size': size,
          'format': extension.replaceAll('.', ''),
          'dimensions': 'Đang tải...',
        };
      });

      // Get image dimensions
      final image = await decodeImageFromList(bytes);
      setState(() {
        _imageInfo = {
          'size': size,
          'format': extension.replaceAll('.', ''),
          'dimensions': '${image.width}x${image.height}',
        };
      });
    } catch (e) {
      print('Error getting image info: $e');
    }
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
          _imageInfo = null;
        });
        _getImageInfo(tempFile);
      }
    } else if (Platform.isMacOS || Platform.isWindows) {
      // Desktop platforms
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() {
          _originalImage = file;
          _enhancedImage = null;
          _imageInfo = null;
        });
        _getImageInfo(file);
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
          _imageInfo = null;
        });
        _getImageInfo(File(pickedFile.path));
      }
    }
  }

  Future<File> _createUniqueTempImageFile(Uint8List bytes) async {
    final dir = await _getUserDocumentsDirectory();
    final uniqueName = 'enhanced_image_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$uniqueName');
    await file.writeAsBytes(bytes);
    print('Đã lưu ảnh tạm tại: ${file.path}');
    return file;
  }

  Future<void> _enhanceImage() async {
    if (_originalImage == null) return;
    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _enhancedImage = null;
    });

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
      final fileExtension = file.path.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFilename = 'image_$timestamp.$fileExtension';
      print('Đang gửi file: ${file.path} với tên mới: $uniqueFilename');
      
      // Ensure file is an image and has proper extension
      if (!['jpg', 'jpeg', 'png', 'gif'].contains(fileExtension)) {
        throw Exception('File phải là ảnh (jpg, jpeg, png, hoặc gif)');
      }

      // Check file size (limit to 10MB)
      final fileSize = await file.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('File quá lớn. Kích thước tối đa là 10MB');
      }

      logger.info('File info:');
      logger.info('- Path: ${file.path}');
      logger.info('- Extension: $fileExtension');
      logger.info('- Size: $fileSize bytes');

      // Gửi file đúng định dạng như Postman
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: uniqueFilename,
          contentType: MediaType('image', fileExtension == 'jpg' ? 'jpeg' : fileExtension),
        ),
      });

      logger.info('Sending form data with fields: ${formData.fields}');
      logger.info('Sending form data with files: ${formData.files}');

      // Simulate progress updates
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_progress < 0.9) {
          setState(() {
            _progress += 0.1;
          });
        }
      });

      final response = await dio.post(
        uri,
        data: formData,
        options: Options(
          validateStatus: (status) => status! < 500,
          headers: {
            'Accept': 'image/png',
          },
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      
      if (response.statusCode == 200) {
        print('Đã nhận ảnh xử lý mới từ server!');
        final enhancedFile = await _createUniqueTempImageFile(response.data);
        setState(() {
          _enhancedImage = enhancedFile;
          _progress = 1.0;
        });
        _getImageInfo(enhancedFile);
      } else {
        final errorMessage = response.data is List 
            ? String.fromCharCodes(response.data)
            : response.data.toString();
        logger.severe('Server error: $errorMessage');
        throw Exception('Lỗi server: ${response.statusCode} - $errorMessage');
      }
    } on DioException catch (e) {
      logger.severe('Network error: ${e.message}');
      logger.severe('Error type: ${e.type}');
      if (e.response != null) {
        logger.severe('Response data: ${e.response?.data}');
        logger.severe('Response status: ${e.response?.statusCode}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi kết nối: ${e.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
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

  Widget _buildImageInfo() {
    if (_imageInfo == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông tin ảnh',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text('Kích thước: ${(_imageInfo!['size'] / 1024).toStringAsFixed(1)} KB'),
            Text('Định dạng: ${_imageInfo!['format'].toUpperCase()}'),
            Text('Kích thước: ${_imageInfo!['dimensions']}'),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    if (_originalImage == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Chưa chọn ảnh',
            style: TextStyle(fontSize: 20, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Hãy chọn một ảnh để bắt đầu',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildImageInfo(),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                elevation: 4,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue.shade50, Colors.white],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Ảnh gốc',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Hero(
                        tag: 'original_image',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(_originalImage!, height: 250),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_enhancedImage != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  elevation: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.green.shade50, Colors.white],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Ảnh sau khi xử lý',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Hero(
                          tag: 'enhanced_image',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_enhancedImage!, height: 250),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_enhancedImage != null) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Lưu ảnh'),
            onPressed: _saveEnhancedImage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Nâng Cao Chất Lượng Ảnh',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_enhancedImage != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.shareXFiles([XFile(_enhancedImage!.path)]),
              tooltip: 'Chia sẻ ảnh',
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: _buildImageSection(),
                    ),
                  ),
                ),
                if (_isLoading)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                value: _progress,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                              ),
                            ),
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Đang xử lý ảnh...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.white, Colors.blue.shade50],
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Tooltip(
                              message: 'Chọn ảnh từ thư viện',
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.image),
                                label: const Text(
                                  "Chọn ảnh",
                                  style: TextStyle(fontSize: 16),
                                ),
                                onPressed: _pickImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2196F3),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Xử lý ảnh với AI',
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.auto_fix_high),
                                label: const Text(
                                  "Xử lý ảnh",
                                  style: TextStyle(fontSize: 16),
                                ),
                                onPressed: _originalImage == null ? null : _enhanceImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2196F3),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Tooltip(
                          message: 'Chọn loại xử lý ảnh',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButton<String>(
                              value: _selectedTask,
                              items: _tasks.map((task) {
                                return DropdownMenuItem(
                                  value: task,
                                  child: Text(
                                    task.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedTask = value!;
                                });
                              },
                              isExpanded: true,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down),
                              dropdownColor: Colors.white,
                            ),
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
      ),
    );
  }
}
