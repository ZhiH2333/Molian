import 'package:flutter/material.dart';

/// 布局与视觉设计常量，全项目统一使用。
class LayoutConstants {
  LayoutConstants._();

  /// Dashboard 列宽、窄内容区最大宽度。
  static const double kContentMaxWidthNarrow = 400;

  /// Realms 列表项等中等内容区最大宽度。
  static const double kContentMaxWidthMedium = 540;

  /// 帖子详情、回复、快捷回复等宽内容区最大宽度。
  static const double kContentMaxWidthWide = 680;

  static const double kSpacingXSmall = 4;
  static const double kSpacingSmall = 8;
  static const double kSpacingMedium = 12;
  static const double kSpacingLarge = 16;
  static const double kSpacingXLarge = 24;

  static const double kRadiusSmall = 8;
  static const double kRadiusMedium = 12;
  static const double kRadiusLarge = 16;

  static const double kListTileContentPaddingLeft = 24;
  static const double kListTileContentPaddingRight = 17;
  static const double kListTileMinLeadingWidth = 48;

  static const double kIconSizeSmall = 20;
  static const double kIconSizeMedium = 24;

  /// 底部导航栏高度。
  static const double kBottomNavHeight = 56;

  /// 壳内首页 FAB 与底部导航栏顶边的间距（调小则更贴导航栏，调大则更高）。
  static const double kFabMarginAboveBottomNav = 1.5;

  static const EdgeInsets kListTileContentPadding = EdgeInsets.only(
    left: kListTileContentPaddingLeft,
    right: kListTileContentPaddingRight,
  );

  static BorderRadius get kRadiusSmallBR => BorderRadius.circular(kRadiusSmall);
  static BorderRadius get kRadiusMediumBR =>
      BorderRadius.circular(kRadiusMedium);
  static BorderRadius get kRadiusLargeBR => BorderRadius.circular(kRadiusLarge);
}
