// Flutter App: Ứng dụng nâng cao chất lượng ảnh
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ImageEnhancer(),
    );
  }
}

class ImageEnhancer extends StatefulWidget {
  const ImageEnhancer({super.key});

  @override
  _ImageEnhancerState createState() => _ImageEnhancerState();
}

class _ImageEnhancerState extends State<ImageEnhancer> {
  File? _originalImage;
  File? _enhancedImage;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    if (Platform.isMacOS || Platform.isWindows || kIsWeb) {
      // Dùng file_picker cho macOS, Windows, hoặc web
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _originalImage = File(result.files.single.path!);
          _enhancedImage = null;
        });
      }
    } else {
      // Dùng image_picker cho iOS/Android
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
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

    final uri = Uri.parse('http://<YOUR_LOCAL_IP>:8000/enhance');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', _originalImage!.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final bytes = await response.stream.toBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/enhanced_image.png');
      await file.writeAsBytes(bytes);
      setState(() => _enhancedImage = file);
    }

    setState(() => _isLoading = false);
  }

  Widget _buildImageSection() {
    if (_originalImage == null) {
      return Text('Chưa chọn ảnh.');
    }
    return Column(
      children: [
        Text('Ảnh gốc'),
        Image.file(_originalImage!, height: 180),
        SizedBox(height: 10),
        _enhancedImage != null
            ? Column(
                children: [
                  Text('Ảnh sau khi xử lý'),
                  Image.file(_enhancedImage!, height: 180),
                ],
              )
            : Container(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Nâng Cao Chất Lượng Ảnh')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: Center(child: _buildImageSection())),
            if (_isLoading) CircularProgressIndicator(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.image),
                  label: Text("Chọn ảnh"),
                  onPressed: _pickImage,
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.auto_fix_high),
                  label: Text("Xử lý ảnh"),
                  onPressed: _originalImage == null ? null : _enhanceImage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
