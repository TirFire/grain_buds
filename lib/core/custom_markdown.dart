import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// ================= 💡 新版极简颜色解析器 [red]...[/] =================
class ColorTextSyntax extends md.InlineSyntax {
  ColorTextSyntax() : super(r'\[(red|blue|green|orange|purple)\](.*?)\[/\]');
  
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // 💡 必须用纯小写的 colortext，因为 flutter_markdown 底层会强制转小写匹配！
    final el = md.Element.text('colortext', match.group(2)!);
    el.attributes['color'] = match.group(1)!;
    parser.addNode(el);
    return true;
  }
}

// ================= 💡 老版本兼容颜色解析器 <font>...</font> =================
class OldColorTextSyntax extends md.InlineSyntax {
  OldColorTextSyntax() : super(r'<font color="(red|blue|green|orange|purple)">(.*?)</font>');
  
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('colortext', match.group(2)!);
    el.attributes['color'] = match.group(1)!;
    parser.addNode(el);
    return true;
  }
}

class ColorTextBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Color c = Colors.blue;
    switch(element.attributes['color']) {
      case 'red': c = Colors.redAccent; break;
      case 'green': c = Colors.teal; break;
      case 'orange': c = Colors.orange; break;
      case 'purple': c = Colors.purpleAccent; break;
    }
    // 💡 命门修复：提供默认 TextStyle 兜底，绝不让样式变为 null！
    return Text(element.textContent, style: (preferredStyle ?? const TextStyle()).copyWith(color: c));
  }
}

// ================= 💡 背景高亮解析器 =================
class HighlightTextSyntax extends md.InlineSyntax {
  HighlightTextSyntax() : super(r'\[bg_(yellow|red|green|blue|purple)\](.*?)\[/bg\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('highlighttext', match.group(2)!);
    el.attributes['color'] = match.group(1)!;
    parser.addNode(el);
    return true;
  }
}

class HighlightTextBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Color c = Colors.yellow.withOpacity(0.4);
    switch(element.attributes['color']) {
      case 'red': c = Colors.redAccent.withOpacity(0.3); break;
      case 'green': c = Colors.teal.withOpacity(0.3); break;
      case 'blue': c = Colors.blueAccent.withOpacity(0.3); break;
      case 'purple': c = Colors.purpleAccent.withOpacity(0.3); break;
    }
    // 💡 命门修复：提供默认 TextStyle 兜底！
    return Text(element.textContent, style: (preferredStyle ?? const TextStyle()).copyWith(backgroundColor: c));
  }
}