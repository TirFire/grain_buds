import 'package:flutter/material.dart';

class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle defaultStyle = style ?? const TextStyle();
    final TextStyle markerStyle = defaultStyle.copyWith(color: Colors.grey.withOpacity(0.3), fontSize: 10);
    final List<InlineSpan> spans = [];

    // 💡 恢复最精简的正则
    final RegExp markdownRegex = RegExp(
      r'\*\*(.*?)\*\*|\*(.*?)\*|~~(.*?)~~|`(.*?)`|^(#{1,6})(\s+)(.*)|\[(red|blue|green|orange|purple)\]([\s\S]*?)\[/\]|<font color="(red|blue|green|orange|purple)">([\s\S]*?)</font>|\[bg_(yellow|red|green|blue|purple)\]([\s\S]*?)\[/bg\]',
      multiLine: true,
    );

    text.splitMapJoin(
      markdownRegex,
      onMatch: (Match match) {
        if (match.group(1) != null) {
          spans.add(TextSpan(text: '**', style: markerStyle));
          spans.add(TextSpan(text: match.group(1), style: defaultStyle.copyWith(fontWeight: FontWeight.bold)));
          spans.add(TextSpan(text: '**', style: markerStyle));
        } else if (match.group(2) != null) {
          spans.add(TextSpan(text: '*', style: markerStyle));
          spans.add(TextSpan(text: match.group(2), style: defaultStyle.copyWith(fontStyle: FontStyle.italic)));
          spans.add(TextSpan(text: '*', style: markerStyle));
        } else if (match.group(3) != null) {
          spans.add(TextSpan(text: '~~', style: markerStyle));
          spans.add(TextSpan(text: match.group(3), style: defaultStyle.copyWith(decoration: TextDecoration.lineThrough)));
          spans.add(TextSpan(text: '~~', style: markerStyle));
        } else if (match.group(4) != null) {
          spans.add(TextSpan(text: '`', style: markerStyle));
          spans.add(TextSpan(text: match.group(4), style: defaultStyle.copyWith(backgroundColor: Colors.grey.withOpacity(0.2), color: Colors.blueAccent)));
          spans.add(TextSpan(text: '`', style: markerStyle));
        } else if (match.group(5) != null) {
          double headingScale = [1.6, 1.4, 1.2][(match.group(5)!.length - 1).clamp(0, 2)];
          spans.add(TextSpan(text: match.group(5)! + match.group(6)!, style: markerStyle));
          spans.add(TextSpan(text: match.group(7), style: defaultStyle.copyWith(fontWeight: FontWeight.bold, fontSize: (defaultStyle.fontSize ?? 14) * headingScale)));
        } else if (match.group(8) != null || match.group(10) != null) {
          String cName = match.group(8) ?? match.group(10)!;
          String contentText = match.group(9) ?? match.group(11)!;
          bool isOldSyntax = match.group(10) != null;

          Color tColor = Colors.blue;
          if (cName == 'red') tColor = Colors.redAccent;
          else if (cName == 'green') tColor = Colors.teal;
          else if (cName == 'orange') tColor = Colors.orange;
          else if (cName == 'purple') tColor = Colors.purpleAccent;

          spans.add(TextSpan(text: isOldSyntax ? '<font color="$cName">' : '[$cName]', style: markerStyle.copyWith(fontSize: isOldSyntax ? 8 : 10)));
          spans.add(TextSpan(text: contentText, style: defaultStyle.copyWith(color: tColor)));
          spans.add(TextSpan(text: isOldSyntax ? '</font>' : '[/]', style: markerStyle.copyWith(fontSize: isOldSyntax ? 8 : 10)));
        } else if (match.group(12) != null) {
          String bgName = match.group(12)!;
          String contentText = match.group(13)!;

          Color bgColor = Colors.yellow.withOpacity(0.4);
          if (bgName == 'red') bgColor = Colors.redAccent.withOpacity(0.3);
          else if (bgName == 'green') bgColor = Colors.teal.withOpacity(0.3);
          else if (bgName == 'blue') bgColor = Colors.blueAccent.withOpacity(0.3);
          else if (bgName == 'purple') bgColor = Colors.purpleAccent.withOpacity(0.3);

          spans.add(TextSpan(text: '[bg_$bgName]', style: markerStyle));
          spans.add(TextSpan(text: contentText, style: defaultStyle.copyWith(backgroundColor: bgColor)));
          spans.add(TextSpan(text: '[/bg]', style: markerStyle));
        }
        return '';
      },
      onNonMatch: (String text) {
        spans.add(TextSpan(text: text, style: defaultStyle));
        return '';
      },
    );

    return TextSpan(style: defaultStyle, children: spans);
  }
}