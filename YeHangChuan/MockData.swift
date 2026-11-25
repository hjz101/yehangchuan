import Foundation

enum MockData {
    // MARK: Books

    static let books: [Book] = [
        Book(
            id: "yehangchuan",
            title: "夜航船",
            author: "张岱",
            kind: .novel,
            coverStyle: 0,
            chapterCount: 4,
            progress: 0.37,
            lastPosition: "卷二 · 方物",
            pageCount: nil,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "changyexing",
            title: "长夜行",
            author: "沈砚",
            kind: .novel,
            coverStyle: 1,
            chapterCount: 9,
            progress: 0.12,
            lastPosition: "第三章 · 灯下",
            pageCount: nil,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "shanhaishiyi",
            title: "山海拾遗",
            author: "顾青",
            kind: .novel,
            coverStyle: 2,
            chapterCount: 14,
            progress: 0.68,
            lastPosition: "第七章 · 归墟",
            pageCount: nil,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "xingganglaixin",
            title: "星港来信",
            author: "木更",
            kind: .comic,
            coverStyle: 3,
            chapterCount: 6,
            progress: 0.44,
            lastPosition: "第 12 页 / 28",
            pageCount: 28,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "wuzhonglieche",
            title: "雾中列车",
            author: "阿迟",
            kind: .comic,
            coverStyle: 4,
            chapterCount: 4,
            progress: 0,
            lastPosition: "未开始",
            pageCount: 36,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "chaoxidianTai",
            title: "潮汐电台",
            author: "林岸",
            kind: .audio,
            coverStyle: 5,
            chapterCount: 8,
            progress: 0.22,
            lastPosition: "01:12 / 05:40",
            pageCount: nil,
            duration: "05:40",
            isFinished: false
        ),
        Book(
            id: "jiuchenghsouji",
            title: "旧城手记",
            author: "周引",
            kind: .audio,
            coverStyle: 1,
            chapterCount: 5,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: "03:28",
            isFinished: false
        ),
        Book(
            id: "beiwei30",
            title: "北纬三十度",
            author: "徐行",
            kind: .novel,
            coverStyle: 3,
            chapterCount: 11,
            progress: 1,
            lastPosition: "已读完",
            pageCount: nil,
            duration: nil,
            isFinished: true
        )
    ]

    // MARK: Sources

    static let sources: [BookSource] = [
        BookSource(
            id: "source-json",
            name: "示例书源",
            host: "demo.example.com",
            kind: .json,
            enabled: false,
            bookCount: 3,
            rule: """
            {
              "search": "https://demo.example.com/search?q={kw}",
              "detail": "https://demo.example.com/book/{id}",
              "chapter": "https://demo.example.com/chapter/{id}"
            }
            """
        ),
        BookSource(
            id: "source-js",
            name: "自建脚本源",
            host: "script.local",
            kind: .js,
            enabled: false,
            bookCount: 6,
            username: "demo-reader",
            rule: """
            {
              "search": "https://script.local/search?q={kw}",
              "chapter": "https://script.local/chapter/{id}"
            }
            """
        )
    ]

    // MARK: Search

    static let searchResults: [Book] = [
        Book(
            id: "dengxiacao",
            title: "灯下草",
            author: "顾青",
            kind: .novel,
            coverStyle: 2,
            chapterCount: 8,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "yuanshanlaixin",
            title: "远山来信",
            author: "木更",
            kind: .novel,
            coverStyle: 5,
            chapterCount: 6,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "haiwu",
            title: "海雾",
            author: "阿迟",
            kind: .comic,
            coverStyle: 4,
            chapterCount: 3,
            progress: 0,
            lastPosition: "未开始",
            pageCount: 24,
            duration: nil,
            isFinished: false
        ),
        Book(
            id: "tingyu",
            title: "听雨楼杂记",
            author: "陆玑",
            kind: .audio,
            coverStyle: 0,
            chapterCount: 5,
            progress: 0,
            lastPosition: "未开始",
            pageCount: nil,
            duration: "07:12",
            isFinished: false
        )
    ]

    // MARK: Excerpts

    static let excerpts: [Excerpt] = [
        Excerpt(
            id: "ex-1",
            bookID: "yehangchuan",
            bookTitle: "夜航船",
            chapterTitle: "卷一 · 夜航",
            text: "所谓远行，不过是把熟悉的东西一件件留在身后。",
            note: "每次离家都会想起这句。",
            createdAt: Date().addingTimeInterval(-3_600 * 5),
            liked: true
        ),
        Excerpt(
            id: "ex-2",
            bookID: "yehangchuan",
            bookTitle: "夜航船",
            chapterTitle: "卷二 · 方物",
            text: "做布和读书一样，急不得。染缸里的颜色要等，纸上的意思也要等。",
            note: "",
            createdAt: Date().addingTimeInterval(-3_600 * 26),
            liked: false
        ),
        Excerpt(
            id: "ex-3",
            bookID: "yehangchuan",
            bookTitle: "夜航船",
            chapterTitle: "卷三 · 灯下",
            text: "夜里的许多事，天亮以后都不作数。",
            note: "适合写在扉页。",
            createdAt: Date().addingTimeInterval(-3_600 * 50),
            liked: true
        ),
        Excerpt(
            id: "ex-4",
            bookID: "shanhaishiyi",
            bookTitle: "山海拾遗",
            chapterTitle: "第七章 · 归墟",
            text: "海把所有的声音都收走了，只留下一层一层推上岸的白色。",
            note: "",
            createdAt: Date().addingTimeInterval(-3_600 * 74),
            liked: false
        ),
        Excerpt(
            id: "ex-5",
            bookID: "changyexing",
            bookTitle: "长夜行",
            chapterTitle: "第三章 · 灯下",
            text: "灯是给人看的，路是给船看的。",
            note: "结构很漂亮的对照。",
            createdAt: Date().addingTimeInterval(-3_600 * 96),
            liked: false
        )
    ]

    // MARK: Stats

    static var dayStats: [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let minutes: [Int] = [
            42, 18, 0, 65, 88, 24, 51, 37, 12, 0, 74, 96, 48, 31,
            0, 22, 58, 82, 44, 19, 67, 35, 0, 91, 63, 28, 47, 12,
            76, 54, 38, 0, 69, 45, 88, 26, 57, 71, 34, 0,
            48, 62, 91, 37, 55, 28, 0, 74, 66, 41, 83, 52, 29, 94,
            47, 0, 63, 38, 71, 44, 26, 0, 58, 92, 36, 0, 47, 61,
            82, 24, 0, 55, 71, 39, 0, 88, 64, 30, 0, 52, 76, 41,
            0, 68, 93, 35, 0, 47, 58, 22, 0, 72, 44
        ]

        return minutes.enumerated().map { offset, value in
            let date = calendar.date(byAdding: .day, value: offset - (minutes.count - 1), to: today) ?? today
            let key = ISO8601DateFormatter.dayFormatter.string(from: date)
            return DayStat(id: key, date: date, minutes: value)
        }
    }

    // MARK: Chapters

    static func chapters(for book: Book) -> [Chapter] {
        book.id == "yehangchuan" ? nightBoatChapters : genericChapters
    }

    static func audioScript(for book: Book) -> String {
        let passages = genericChapters.flatMap(\.paragraphs).map(\.text)
        let intro = "这里是潮汐电台。今晚为你读《\(book.title)》，作者\(book.author)。"
        return ([intro] + passages).joined(separator: "\n")
    }

    static let nightBoatChapters: [Chapter] = [
        Chapter(
            id: "nb-1",
            title: "卷一 · 夜航",
            paragraphs: [
                Paragraph(
                    id: "nb-1-1",
                    text: "船是傍晚开的。码头上还留着白日晒过的热气，脚踩上去，鞋底微微发软。我拎着一只旧藤箱，箱子里只有两本书、一件换洗衣裳，和母亲临行前塞进来的一包桂花糖。"
                ),
                Paragraph(
                    id: "nb-1-2",
                    text: "同船的人不多。一个卖布的老人，一个抱着孩子的妇人，还有一个总在甲板上踱步的年轻人。他不与人说话，只在暮色里一遍遍数着岸边的灯。",
                    comments: [
                        SegmentComment(id: "c1", author: "临江客", text: "数灯的人，像是舍不得岸。", likes: 128, minutesAgo: 12),
                        SegmentComment(id: "c2", author: "晚风", text: "这一段很有夜船的感觉，水汽都从字里冒出来了。", likes: 74, minutesAgo: 46),
                        SegmentComment(id: "c3", author: "阿七", text: "后面还会再出现吗？总觉得他是个引子。", likes: 22, minutesAgo: 130)
                    ]
                ),
                Paragraph(
                    id: "nb-1-3",
                    text: "船离岸时，城里的钟正好敲了七下。水声漫上来，把钟声推得很远。我忽然觉得，所谓远行，不过是把熟悉的东西一件件留在身后。"
                ),
                Paragraph(
                    id: "nb-1-4",
                    text: "舱里没有别的消遣。邻座的孩子趴在窗边，用手指在玻璃上画一艘船，画完又抹掉，再画一艘。他母亲低声说，到了口岸就能看见真的船。"
                ),
                Paragraph(
                    id: "nb-1-5",
                    text: "我打开书，却半天没有翻页。船身轻轻地晃，灯影也跟着晃，字句像浮在水面上。"
                )
            ]
        ),
        Chapter(
            id: "nb-2",
            title: "卷二 · 方物",
            paragraphs: [
                Paragraph(
                    id: "nb-2-1",
                    text: "张岱写方物，写的其实不是物。一柄剑、一盏灯、一方砚，落到纸上，都沾了人的脾气。夜里读这些条目，像在旧货铺里翻抽屉，每一样都带着前人的手温。"
                ),
                Paragraph(
                    id: "nb-2-2",
                    text: "船到半程，卖布的老人打开包袱，取出几块靛蓝的布样子给我看。他说这是山里染的，颜色深浅全凭天气。我摸着那块布，竟想起书里写的“雨过天青”。"
                ),
                Paragraph(
                    id: "nb-2-3",
                    text: "老人说，做布和读书一样，急不得。染缸里的颜色要等，纸上的意思也要等。等到了，才算你的。",
                    comments: [
                        SegmentComment(id: "c4", author: "青苔", text: "染布与读书，这个比喻真好。", likes: 96, minutesAgo: 62),
                        SegmentComment(id: "c5", author: "半盏", text: "颜色要等，意思也要等。这半句我抄下来了。", likes: 51, minutesAgo: 175)
                    ]
                ),
                Paragraph(
                    id: "nb-2-4",
                    text: "我把这句话记在本子上。写完抬头，窗外已经没有了岸，只有水，和比水更黑的天。"
                )
            ]
        ),
        Chapter(
            id: "nb-3",
            title: "卷三 · 灯下",
            paragraphs: [
                Paragraph(
                    id: "nb-3-1",
                    text: "入夜以后，船上只剩两盏灯。一盏挂在船头，一盏在舱里。船头的灯给路看，舱里的灯给人看。"
                ),
                Paragraph(
                    id: "nb-3-2",
                    text: "我借那点光翻书。纸页发黄，边角卷起，翻动时有很轻的响声，像有人在隔壁低声说话。读着读着，字迹便有些游移，眼皮也沉。"
                ),
                Paragraph(
                    id: "nb-3-3",
                    text: "朦胧间听见那年轻人在甲板上念诗。声音不高，被风一吹就散了。我只听清一句：此身合是诗人未。",
                    comments: [
                        SegmentComment(id: "c6", author: "夜航人", text: "这一句忽然把整章点亮了。", likes: 214, minutesAgo: 8),
                        SegmentComment(id: "c7", author: "小满", text: "被风吹散的诗，很妙。", likes: 63, minutesAgo: 92),
                        SegmentComment(id: "c8", author: "山月", text: "所以昨夜他到底念没念？", likes: 37, minutesAgo: 210),
                        SegmentComment(id: "c9", author: "听雨", text: "天亮以后都不作数。", likes: 148, minutesAgo: 320)
                    ]
                ),
                Paragraph(
                    id: "nb-3-4",
                    text: "第二天问起，他却说昨夜早早睡了。我便不再问。夜里的许多事，天亮以后都不作数。"
                ),
                Paragraph(
                    id: "nb-3-5",
                    text: "后半夜风小了，船走得很慢。我合上书，听见船底的水声变得细密，像有人用指甲轻轻刮着木板。"
                ),
                Paragraph(
                    id: "nb-3-6",
                    text: "灯芯短下去，舱里暗了一截。我索性不看，只把书抱在胸前，任那些句子在黑暗里自己走。"
                )
            ]
        ),
        Chapter(
            id: "nb-4",
            title: "卷四 · 抵达",
            paragraphs: [
                Paragraph(
                    id: "nb-4-1",
                    text: "船靠岸是在清晨。雾很低，岸上的屋脊一层层浮在雾里，像没有落笔的画。"
                ),
                Paragraph(
                    id: "nb-4-2",
                    text: "卖布的老人先下了船，回头朝我点了点头。抱孩子的妇人还在睡，孩子醒了，睁着眼看舱顶。那个年轻人不知什么时候已经走了。"
                ),
                Paragraph(
                    id: "nb-4-3",
                    text: "我拎着藤箱走上石阶。回头看，船已经空了，船夫正在收缆。一夜的水路，像一场做得很短的梦。"
                ),
                Paragraph(
                    id: "nb-4-4",
                    text: "后来我常想，人这一生要坐很多次夜船。有的船到岸了，有的船一直开着。书大概就是后一种，你合上它，它还在往前走。"
                )
            ]
        )
    ]

    static let genericChapters: [Chapter] = [
        Chapter(
            id: "g-1",
            title: "第一章 · 起程",
            paragraphs: [
                Paragraph(
                    id: "g-1-1",
                    text: "雨是从午后开始下的。起初只是零零落落几滴，落在窗台上，很快就干了。到了傍晚，雨声连成一片，街上的灯一盏一盏亮起来。"
                ),
                Paragraph(
                    id: "g-1-2",
                    text: "他把书翻到夹着书签的那一页，却没有立刻读下去。窗外的雨、桌上的茶、远处隐约的车声，都比书里的句子更先抵达。",
                    comments: [
                        SegmentComment(id: "g1", author: "读者甲", text: "这个开头很安静。", likes: 31, minutesAgo: 24),
                        SegmentComment(id: "g2", author: "读者乙", text: "像是要发生什么，又什么都没有发生。", likes: 18, minutesAgo: 88)
                    ]
                ),
                Paragraph(
                    id: "g-1-3",
                    text: "有些夜晚适合读完一章，有些夜晚只适合坐着。等到茶凉了，他才发现自己在同一行字上停了很久。"
                )
            ]
        ),
        Chapter(
            id: "g-2",
            title: "第二章 · 回信",
            paragraphs: [
                Paragraph(
                    id: "g-2-1",
                    text: "信是第三天到的。信封很薄，边角被雨水洇出一圈浅褐色的印子。他把它放在桌上，先去烧了一壶水。"
                ),
                Paragraph(
                    id: "g-2-2",
                    text: "水开的时候，他才拆信。里面只有一页纸，写了三行字：山里的桂花开了，路还是老样子，你什么时候回来。"
                ),
                Paragraph(
                    id: "g-2-3",
                    text: "他把信折好，夹进那本书里。窗外的雨已经停了，屋檐下还在滴水，一滴一滴，像在替谁数着日子。"
                )
            ]
        )
    ]
}

extension ISO8601DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
