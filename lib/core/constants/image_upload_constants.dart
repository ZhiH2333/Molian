/// 图片上传与压缩相关常量。
class ImageUploadConstants {
  ImageUploadConstants._();

  /// 所有上传图片统一目标体积（KB），约 200KB。
  static const int imageMaxKb = 200;

  /// 帖子图片目标体积（KB）。
  static const int postImageMaxKb = 200;

  /// 头像目标体积（KB）。
  static const int avatarMaxKb = 200;

  /// 帖子图片最大边长（像素），避免超分辨率。
  static const int postImageMaxDimension = 1920;

  /// 头像最大边长（像素）。
  static const int avatarMaxDimension = 512;

  /// 单帖最多图片张数。
  static const int maxPostImages = 9;
}
