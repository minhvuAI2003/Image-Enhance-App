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
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Model cho lịch sử xử lý ảnh
class HistoryItem {
  final String id;
  final String taskName;
  final String originalImagePath;
  final String enhancedImagePath;
  final DateTime timestamp;
  final Map<String, dynamic> imageInfo;

  HistoryItem({
    required this.id,
    required this.taskName,
    required this.originalImagePath,
    required this.enhancedImagePath,
    required this.timestamp,
    required this.imageInfo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskName': taskName,
        'originalImagePath': originalImagePath,
        'enhancedImagePath': enhancedImagePath,
        'timestamp': timestamp.toIso8601String(),
        'imageInfo': imageInfo,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'],
        taskName: json['taskName'],
        originalImagePath: json['originalImagePath'],
        enhancedImagePath: json['enhancedImagePath'],
        timestamp: DateTime.parse(json['timestamp']),
        imageInfo: json['imageInfo'],
      );
}

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

class ImageEnhancerState extends State<ImageEnhancer>
    with SingleTickerProviderStateMixin {
  File? _originalImage; // Current image (may be noised)
  File? _originalImageRaw; // Always the original, never-noised image
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
    'motion_deblur': '/motion-deblur',
    'single_image_deblur': '/single-image-deblur',
  };

  final String _baseUrl = Platform.isMacOS
      ? 'https://b068-99-28-52-217.ngrok-free.app' // Local development
      : 'https://b068-99-28-52-217.ngrok-free.app    '; // Production

  List<HistoryItem> _history = [];
  bool _showHistory = false;
  double _gaussianSigma = 25;
  final TextEditingController _urlController = TextEditingController();
  bool _isUrlLoading = false;

  Future<void> _testConnection() async {
    final logger = Logger('TestConnection');
    try {
      final dio = Dio();

      logger.info('Testing connection to: $_baseUrl');

      final response = await dio.get(
        '$_baseUrl/',
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200) {
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
        throw Exception('Server response indicates error: ${response.data}');
      }
    } on DioException catch (e) {
      logger.severe('Connection test failed: ${e.message}');
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
    _loadHistory();
  }

  @override
  void dispose() {
    _comparisonController.dispose();
    _urlController.dispose();
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
          _originalImageRaw = tempFile;
          _originalImage = tempFile;
          _enhancedImage = null;
          _imageInfo = null;
        });
        _getImageInfo(tempFile);
        if (_selectedTask == 'gaussian_denoise' && _originalImageRaw != null) {
          _addNoiseToImage();
        }
      }
    } else if (Platform.isMacOS || Platform.isWindows) {
      // Desktop platforms
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() {
          _originalImageRaw = file;
          _originalImage = file;
          _enhancedImage = null;
          _imageInfo = null;
        });
        _getImageInfo(file);
        if (_selectedTask == 'gaussian_denoise' && _originalImageRaw != null) {
          _addNoiseToImage();
        }
      }
    } else {
      // Mobile platforms
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        setState(() {
          _originalImageRaw = file;
          _originalImage = file;
          _enhancedImage = null;
          _imageInfo = null;
        });
        _getImageInfo(file);
        if (_selectedTask == 'gaussian_denoise' && _originalImageRaw != null) {
          _addNoiseToImage();
        }
      }
    }
  }

  Future<File> _createUniqueTempImageFile(Uint8List bytes) async {
    final dir = await _getUserDocumentsDirectory();
    final uniqueName =
        'enhanced_image_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$uniqueName');
    await file.writeAsBytes(bytes);
    print('Đã lưu ảnh tạm tại: ${file.path}');
    return file;
  }

  // Thêm hàm mới để xử lý khi thay đổi task
  void _onTaskChanged(String? newTask) {
    if (newTask == null) return;
    setState(() {
      _selectedTask = newTask;
      if (newTask != 'gaussian_denoise' && _originalImageRaw != null) {
        _originalImage = _originalImageRaw;
        _enhancedImage = null;
        _getImageInfo(_originalImageRaw!);
      }
    });
    if (newTask == 'gaussian_denoise' && _originalImageRaw != null) {
      _addNoiseToImage();
    }
  }

  // Hàm mới để thêm nhiễu vào ảnh
  Future<void> _addNoiseToImage() async {
    if (_originalImageRaw == null) return;
    setState(() {
      _isLoading = true;
      _progress = 0.0;
    });
    final logger = Logger('ImageEnhancer');
    final dio = Dio();
    try {
      final addNoiseResponse = await dio.post(
        '$_baseUrl/add-noise?level=${_gaussianSigma.toInt()}',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _originalImageRaw!.path,
            filename: 'image.${path.extension(_originalImageRaw!.path).toLowerCase()}',
            contentType: MediaType('image', path.extension(_originalImageRaw!.path).toLowerCase() == '.jpg' ? 'jpeg' : path.extension(_originalImageRaw!.path).toLowerCase().replaceAll('.', '')),
          ),
        }),
        options: Options(
          validateStatus: (status) => status! < 500,
          headers: {'Accept': 'image/png'},
          responseType: ResponseType.bytes,
        ),
      );
      if (addNoiseResponse.statusCode != 200) {
        throw Exception('Lỗi khi thêm nhiễu: ${addNoiseResponse.statusCode}');
      }
      final tempDir = await getTemporaryDirectory();
      final noisyFile = File('${tempDir.path}/noisy_${DateTime.now().millisecondsSinceEpoch}_${path.basename(_originalImageRaw!.path)}');
      await noisyFile.writeAsBytes(addNoiseResponse.data);
      setState(() {
        _originalImage = noisyFile;
        _enhancedImage = null;
      });
      _getImageInfo(noisyFile);
      logger.info('Received noisy image from server');
    } catch (e) {
      logger.severe('Error adding noise: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi thêm nhiễu: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
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
    
    try {
      final endpoint = _taskEndpoints[_selectedTask];
      if (endpoint == null) {
        throw Exception('Task chưa được hỗ trợ!');
      }
      final uri = '$_baseUrl$endpoint';
      logger.info('Sending request to: $uri');

      File fileToProcess = _originalImage!;
      
      // Check file size (limit to 10MB)
      final fileSize = await fileToProcess.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('File quá lớn. Kích thước tối đa là 10MB');
      }

      // Create form data
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          fileToProcess.path,
          filename: 'image.${path.extension(fileToProcess.path).toLowerCase()}',
          contentType: MediaType('image', path.extension(fileToProcess.path).toLowerCase() == '.jpg' ? 'jpeg' : path.extension(fileToProcess.path).toLowerCase().replaceAll('.', '')),
        ),
      });

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
        final enhancedFile = await _createUniqueTempImageFile(response.data);
        setState(() {
          _enhancedImage = enhancedFile;
          _progress = 1.0;
        });
        _getImageInfo(enhancedFile);
        await _saveToHistory(_originalImage!, enhancedFile);
      } else {
        final errorMessage = response.data is List 
            ? String.fromCharCodes(response.data)
            : response.data.toString();
        throw Exception('Lỗi server: ${response.statusCode} - $errorMessage');
      }
    } on DioException catch (e) {
      logger.severe('Network error: ${e.message}');
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

  // Thêm hàm lưu lịch sử
  Future<void> _saveToHistory(File originalFile, File enhancedFile) async {
    final historyItem = HistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      taskName: _selectedTask,
      originalImagePath: originalFile.path,
      enhancedImagePath: enhancedFile.path,
      timestamp: DateTime.now(),
      imageInfo: _imageInfo ?? {},
    );

    setState(() {
      _history.insert(0, historyItem);
    });

    // Lưu lịch sử vào local storage
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _history.map((item) => item.toJson()).toList();
    await prefs.setString('image_history', jsonEncode(historyJson));
  }

  // Thêm hàm load lịch sử
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyString = prefs.getString('image_history');
    if (historyString != null) {
      final List<dynamic> historyJson = jsonDecode(historyString);
      setState(() {
        _history =
            historyJson.map((json) => HistoryItem.fromJson(json)).toList();
      });
    }
  }

  Future<void> _loadImageFromUrl() async {
    if (_urlController.text.isEmpty) return;

    setState(() {
      _isUrlLoading = true;
    });

    try {
      // Validate URL format
      final uri = Uri.parse(_urlController.text);
      if (!uri.hasScheme || !uri.hasAuthority) {
        throw Exception('URL không hợp lệ');
      }

      // Download image with timeout
      final response = await Dio().get(
        _urlController.text,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (status) => status! < 500,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('Không thể tải ảnh: ${response.statusCode}');
      }

      final bytes = response.data as List<int>;
      if (bytes.isEmpty) {
        throw Exception('Không nhận được dữ liệu ảnh');
      }

      // Validate image data
      try {
        await decodeImageFromList(Uint8List.fromList(bytes));
      } catch (e) {
        throw Exception('Dữ liệu ảnh không hợp lệ');
      }

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);

      setState(() {
        _originalImageRaw = tempFile;
        _originalImage = tempFile;
        _enhancedImage = null;
        _imageInfo = null;
      });

      await _getImageInfo(tempFile);
      if (_selectedTask == 'gaussian_denoise' && _originalImageRaw != null) {
        await _addNoiseToImage();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tải ảnh thành công'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on DioException catch (e) {
      String errorMessage = 'Lỗi khi tải ảnh';
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Hết thời gian chờ kết nối';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Hết thời gian chờ tải ảnh';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'Không thể kết nối đến URL';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUrlLoading = false;
        _urlController.clear();
      });
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
            Text(
                'Kích thước: ${(_imageInfo!['size'] / 1024).toStringAsFixed(1)} KB'),
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
            style: TextStyle(
                fontSize: 20,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500),
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

  Widget _buildHistorySection() {
    return Card(
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lịch sử xử lý',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[700],
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _showHistory ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _showHistory = !_showHistory;
                    });
                  },
                ),
              ],
            ),
            if (_showHistory) ...[
              const SizedBox(height: 12),
              if (_history.isEmpty)
                Center(
                  child: Text(
                    'Chưa có lịch sử xử lý',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(item.originalImagePath),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          item.taskName.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.timestamp.day}/${item.timestamp.month}/${item.timestamp.year} ${item.timestamp.hour}:${item.timestamp.minute}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: () {
                                setState(() {
                                  _originalImage = File(item.originalImagePath);
                                  _enhancedImage = File(item.enhancedImagePath);
                                  _selectedTask = item.taskName;
                                  _imageInfo = item.imageInfo;
                                });
                              },
                              tooltip: 'Xem chi tiết',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                setState(() {
                                  _history.removeAt(index);
                                });
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final historyJson = _history
                                    .map((item) => item.toJson())
                                    .toList();
                                await prefs.setString(
                                    'image_history', jsonEncode(historyJson));
                              },
                              tooltip: 'Xóa',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
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
                      child: Column(
                        children: [
                          _buildImageSection(),
                          const SizedBox(height: 20),
                          if (_selectedTask == 'gaussian_denoise')
                            Column(
                              children: [
                                const Text(
                                  'Mức độ nhiễu Gaussian',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Slider(
                                  value: _gaussianSigma,
                                  min: 1,
                                  max: 75,
                                  divisions: 74,
                                  label: _gaussianSigma.round().toString(),
                                  onChanged: (value) {
                                    setState(() {
                                      _gaussianSigma = value;
                                    });
                                  },
                                  onChangeEnd: (value) async {
                                    await _addNoiseToImage();
                                  },
                                ),
                              ],
                            ),
                          _buildHistorySection(),
                        ],
                      ),
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
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2196F3)),
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
                                onPressed: _isLoading ? null : _pickImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2196F3),
                                  disabledBackgroundColor: Colors.grey.shade200,
                                  disabledForegroundColor: Colors.grey,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Tải ảnh từ URL',
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.link),
                                label: const Text(
                                  "Tải từ URL",
                                  style: TextStyle(fontSize: 16),
                                ),
                                onPressed: _isLoading ? null : () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Tải ảnh từ URL'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: _urlController,
                                            decoration: const InputDecoration(
                                              hintText: 'Nhập URL ảnh',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          if (_isUrlLoading)
                                            const CircularProgressIndicator()
                                          else
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _loadImageFromUrl();
                                              },
                                              child: const Text('Tải ảnh'),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2196F3),
                                  disabledBackgroundColor: Colors.grey.shade200,
                                  disabledForegroundColor: Colors.grey,
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
                                onPressed:
                                    (_originalImage == null || _isLoading)
                                        ? null
                                        : _enhanceImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isLoading
                                      ? Colors.grey
                                      : const Color(0xFF2196F3),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey,
                                  disabledForegroundColor: Colors.white70,
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
                              onChanged: _isLoading ? null : _onTaskChanged,
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
