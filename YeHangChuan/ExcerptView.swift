import SwiftUI

struct ExcerptView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var selectedBook: String?
    @State private var editing: Excerpt?
    @State private var showOnlyLiked = false

    private var filtered: [Excerpt] {
        store.excerpts.filter { excerpt in
            let bookMatches = selectedBook == nil || excerpt.bookID == selectedBook
            let likeMatches = !showOnlyLiked || excerpt.liked
            return bookMatches && likeMatches
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        overview
                        filterBar

                        if filtered.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filtered) { excerpt in
                                    ExcerptCard(excerpt: excerpt)
                                        .onTapGesture { editing = excerpt }
                                        .contextMenu {
                                            Button {
                                                store.toggleExcerptLike(excerpt.id)
                                            } label: {
                                                Label(excerpt.liked ? "取消收藏" : "收藏", systemImage: "heart")
                                            }

                                            Button {
                                                UIPasteboard.general.string = excerpt.text
                                                store.showToast("已复制摘录")
                                            } label: {
                                                Label("复制", systemImage: "doc.on.doc")
                                            }

                                            Button(role: .destructive) {
                                                store.removeExcerpt(excerpt.id)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("摘录")
            .navigationSubtitle("\(store.excerpts.count) 条 · 来自 \(store.excerptBooks.count) 本书")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showOnlyLiked.toggle()
                        }
                    } label: {
                        Image(systemName: showOnlyLiked ? "heart.fill" : "heart")
                    }
                    .tint(showOnlyLiked ? theme.accent : theme.text)
                    .accessibilityLabel("只看收藏")
                }
            }
        }
        .sheet(item: $editing) { excerpt in
            ExcerptDetailSheet(excerpt: excerpt)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.visible)
                .themedChrome(store)
        }
    }

    private var overview: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.excerpts.count)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)

                Text("条摘录 · \(store.excerpts.filter(\.liked).count) 条收藏")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiary)
            }

            Spacer()

            ZStack {
                ForEach(Array(store.excerptBooks.prefix(3).enumerated()), id: \.element.id) { index, item in
                    if let book = store.book(id: item.id) {
                        BookCover(book: book, cornerRadius: 6)
                            .frame(width: 26)
                            .offset(x: CGFloat(index) * 16 - 16)
                    }
                }
            }
            .frame(width: 60)
        }
        .padding(16)
        .glassSurface(cornerRadius: 24)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill("全部", selected: selectedBook == nil) {
                    selectedBook = nil
                }

                ForEach(store.excerptBooks, id: \.id) { item in
                    pill("\(item.title) \(item.count)", selected: selectedBook == item.id) {
                        selectedBook = item.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? theme.onAccent : theme.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    if selected { Capsule().fill(theme.accentSolid) }
                }
                .glassCapsule(tint: selected ? nil : theme.glassTint, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.tertiary)

            Text(showOnlyLiked ? "还没有收藏的摘录" : "还没有摘录")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.text)

            Text("阅读时长按段落即可摘录")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct ExcerptCard: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let excerpt: Excerpt

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.system(size: 9))
                Text(excerpt.bookTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                Text("·")
                    .font(.system(size: 9))
                Text(excerpt.chapterTitle)
                    .font(.system(size: 10))
                Spacer()
                Text(excerpt.relativeDate)
                    .font(.system(size: 9.5))
            }
            .foregroundStyle(theme.tertiary)

            Text(excerpt.text)
                .font(.system(size: 14.5, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            if !excerpt.note.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Rectangle()
                        .fill(theme.accent.opacity(0.5))
                        .frame(width: 2)
                    Text(excerpt.note)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                        .lineSpacing(3)
                }
                .padding(.top, 1)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        store.toggleExcerptLike(excerpt.id)
                    }
                } label: {
                    Image(systemName: excerpt.liked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(excerpt.liked ? theme.accent : theme.tertiary)
                }
                .buttonStyle(PressableStyle(scale: 0.9))

                Spacer()

                Text("编辑")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
        }
        .padding(14)
        .glassSurface(
            cornerRadius: 22,
            tint: excerpt.liked ? theme.accent.opacity(0.06) : nil
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ExcerptDetailSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let excerpt: Excerpt

    @State private var note = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text(excerpt.bookTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                Text("·")
                                Text(excerpt.chapterTitle)
                                    .font(.system(size: 10.5))
                                Spacer()
                                Text(excerpt.relativeDate)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(theme.tertiary)

                            Text(excerpt.text)
                                .font(.system(size: 17, design: .serif))
                                .lineSpacing(7)
                                .foregroundStyle(theme.text)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface(cornerRadius: 24)

                        VStack(alignment: .leading, spacing: 9) {
                            SectionHeading(text: "我的想法")

                            TextEditor(text: $note)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.text)
                                .scrollContentBackground(.hidden)
                                .frame(height: 120)
                                .padding(12)
                                .glassSurface(cornerRadius: 20)
                                .overlay(alignment: .topLeading) {
                                    if note.isEmpty {
                                        Text("写点什么…")
                                            .font(.system(size: 14))
                                            .foregroundStyle(theme.tertiary)
                                            .padding(.horizontal, 17)
                                            .padding(.top, 20)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }

                        HStack(spacing: 9) {
                            Button {
                                store.toggleExcerptLike(excerpt.id)
                                dismiss()
                            } label: {
                                Image(systemName: excerpt.liked ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(excerpt.liked ? theme.accent : theme.secondary)
                                    .glassCircle(diameter: 50)
                            }
                            .buttonStyle(PressableStyle())

                            Button {
                                UIPasteboard.general.string = excerpt.text
                                store.showToast("已复制摘录")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(theme.secondary)
                                    .glassCircle(diameter: 50)
                            }
                            .buttonStyle(PressableStyle())

                            Button {
                                store.updateNote(excerpt.id, note: note)
                                store.showToast("笔记已保存")
                                dismiss()
                            } label: {
                                Text("保存笔记")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(theme.accentSolid, in: Capsule())
                            }
                            .buttonStyle(PressableStyle(scale: 0.97))
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("摘录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        store.updateNote(excerpt.id, note: note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                note = excerpt.note
                didLoad = true
            }
        }
    }
}
