enum PopularSection {
  all('综合热门'),
  weekly('每周必看'),
  precious('入站必刷'),
  ranking('排行榜');

  const PopularSection(this.label);
  final String label;

  static PopularSection fromLabel(String? label) =>
      values.where((value) => value.label == label).firstOrNull ?? all;
}

final class PopularWeek {
  const PopularWeek({
    required this.number,
    required this.name,
    this.subject = '',
  });

  final int number;
  final String name;
  final String subject;
}
