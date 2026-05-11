import 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

sealed class UpdateProgress {
  const UpdateProgress();
}

class Preparing extends UpdateProgress {
  const Preparing();
}

class WaitingForCapture extends UpdateProgress {
  const WaitingForCapture({this.isFallback = false});
  final bool isFallback;
}

class FetchingBanner extends UpdateProgress {
  const FetchingBanner({
    required this.gachaType,
    required this.displayName,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final String displayName;
  final int pageIndex;
  final int newRecordsSoFar;
}

class UpdateCompleted extends UpdateProgress {
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
  });
  final int totalNewRecords;
  final List<String> failedBanners;
  final DateTime updatedAt;
}

class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.error);
  final UpdateError error;
}
