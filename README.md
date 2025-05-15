# Image-Enhance-App

Ứng dụng nâng cao chất lượng ảnh sử dụng AI, được xây dựng bằng Flutter.

## Mô tả

Image-Enhance-App là một ứng dụng desktop/mobile cho phép người dùng tải lên ảnh và áp dụng các thuật toán AI để nâng cao chất lượng ảnh. Ứng dụng hỗ trợ nhiều tác vụ xử lý ảnh như:
- Xóa mưa (derain)
- Khử nhiễu Gaussian (gaussian denoise)
- Khử nhiễu thực tế (real denoise)
- Khử mờ chuyển động (motion deblur)
- Khử mờ ảnh đơn (single image deblur)

## Cài đặt

### Yêu cầu
- Flutter SDK (phiên bản mới nhất)
- Dart SDK
- Các package Flutter: dio, path_provider, image_picker, file_picker, logging, http_parser, share_plus, path

### Các bước cài đặt
1. Clone repository:
   ```bash
   git clone https://github.com/yourusername/Image-Enhance-App.git
   cd Image-Enhance-App
   cd image_enhancer
   ```
2. Cài đặt các dependencies:
   ```bash
   flutter pub get
   ```
3. Chạy ứng dụng:
   ```bash
   flutter run
   ```

## Cách sử dụng
1. Mở ứng dụng và nhấn nút "Chọn ảnh" để tải lên ảnh cần xử lý.
2. Chọn loại xử lý ảnh từ dropdown menu (ví dụ: derain, gaussian denoise, ...).
3. Nhấn nút "Xử lý ảnh" để bắt đầu quá trình nâng cao chất lượng ảnh.
4. Sau khi xử lý xong, nhấn nút "Lưu ảnh" để lưu ảnh đã xử lý vào thư mục bạn chọn.

## Tính năng chính
- Tải lên ảnh từ thư viện hoặc chọn file từ máy tính.
- Xử lý ảnh với nhiều thuật toán AI khác nhau.
- Hiển thị thông tin ảnh (kích thước, định dạng, kích thước pixel).
- Lưu ảnh đã xử lý vào thư mục tùy chọn.
- Chia sẻ ảnh đã xử lý.

## Lưu ý
- Ứng dụng yêu cầu kết nối đến server xử lý ảnh (mặc định: http://localhost:8000).
- Kích thước file ảnh tối đa: 10MB.

## Giấy phép
MIT License
