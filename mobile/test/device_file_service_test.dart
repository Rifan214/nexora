import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/media_download_type.dart';
import 'package:nexora/services/device_file_service.dart';

void main() {
  const service = DeviceFileService();

  test('uses the public Video directory for video downloads', () {
    expect(
      service.publicDownloadsRelativePathFor(MediaDownloadType.video),
      'Download/Nexora/Video',
    );
  });

  test('uses the public Audio directory for audio downloads', () {
    expect(
      service.publicDownloadsRelativePathFor(MediaDownloadType.audio),
      'Download/Nexora/Audio',
    );
  });
}
