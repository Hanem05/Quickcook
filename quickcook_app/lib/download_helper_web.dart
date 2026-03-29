import 'dart:convert';
import 'dart:html' as html;

void downloadCsv(String content) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes]);

  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute("download", "activity_logs.csv")
    ..click();

  html.Url.revokeObjectUrl(url);
}
