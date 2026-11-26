import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 正文排版参数。所有间距单位都是点，不随字号缩放；
/// App 层的「行距倍数」由调用方换算成这里的绝对值。
///
/// 不标 `Sendable`：里面装着 `CTFont`，而 CoreText 的字体对象不是线程无关的。
/// 排版只在主线程或单一后台队列上做，跨线程传递没有意义。
public struct PageTextStyle {
    public var font: CTFont
    /// 行与行之间额外增加的间距。
    public var extraLineSpacing: CGFloat
    /// 段与段之间额外增加的间距。
    public var paragraphSpacing: CGFloat
    /// 段首缩进。
    public var firstLineIndent: CGFloat

    public init(
        font: CTFont,
        extraLineSpacing: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        firstLineIndent: CGFloat = 0
    ) {
        self.font = font
        self.extraLineSpacing = extraLineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.firstLineIndent = firstLineIndent
    }

    /// 段首缩进可以按需覆盖：跨页的续行必须传 0，否则每页开头都会空两格。
    public func paragraphStyle(firstLineIndent indent: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(0, extraLineSpacing)
        style.paragraphSpacing = max(0, paragraphSpacing)
        style.firstLineHeadIndent = max(0, indent ?? firstLineIndent)
        style.lineBreakMode = .byWordWrapping
        return style
    }

    public var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle()]
    }

    /// 一行的名义高度，用于测试与调试验收（实际行高由字体决定）。
    public var nominalLineHeight: CGFloat {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return ascent + descent + leading + max(0, extraLineSpacing)
    }
}
