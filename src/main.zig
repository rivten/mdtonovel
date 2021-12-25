const std = @import("std");

// TODO
// * scene break
// * templating
// * fix rendering text that come after dialogues but on the same line
// * fix bug where separate paragraphs are concatenated in the output

const Token = struct {
    tag: Tag,
    loc: Loc,

    const Loc = struct {
        start: usize,
        end: usize,
    };

    const Tag = enum {
        hashtag,
        dashDialogStart,
        text,
        quotationMark,
        underscore,
        newline,
        eof,
    };
};

const Tokenizer = struct {
    buffer: []const u8,
    index: usize,

    pub fn init(buffer: []const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum {
        start,
        newline,
        text,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        while (self.index < self.buffer.len) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => break,
                    '\n' => {
                        state = .newline;
                        result.loc.start = self.index + 1;
                    },
                    '#' => {
                        result.tag = .hashtag;
                        self.index += 1;
                        break;
                    },
                    '_' => {
                        result.tag = .underscore;
                        self.index += 1;
                        break;
                    },
                    '"' => {
                        result.tag = .quotationMark;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .text;
                        state = .text;
                    },
                },
                .newline => switch (c) {
                    '-' => {
                        result.tag = .dashDialogStart;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .newline;
                        break;
                    },
                },
                .text => switch (c) {
                    '\n', '_', '"' => {
                        break;
                    },
                    else => {
                        if (self.index == self.buffer.len) {
                            break;
                        }
                    },
                },
            }
        }

        if (result.tag == .eof) {
            result.loc.start = self.index;
        }
        result.loc.end = self.index;
        return result;
    }
};

const Node = struct {
    const Tag = union(enum) {
        root: Root,
        novelTitle: NovelTitle,
        simpleText: SimpleText,
        emphText: EmphText,
        text: Text,
        dialog: Dialog,
        dialogLine: DialogLine,
    };

    const Root = struct {
        title: ?NovelTitle,
        chapters: []Chapter,
    };

    const Chapter = struct {
        title: ?ChapterTitle,
        texts: []Text,
    };

    const ChapterTitle = struct {
        text: SimpleText,
    };

    const NovelTitle = struct {
        title: SimpleText,
    };

    const SimpleText = struct {
        token: Token,
    };

    const EmphText = struct {
        simpleText: SimpleText,
    };

    const SimpleOrEmpthText = union(enum) {
        simpleText: SimpleText,
        emphText: EmphText,
    };

    const EnrichedText = struct {
        texts: []SimpleOrEmpthText,
        endWithNewline: bool,
    };

    const Text = union(enum) {
        enrichedText: EnrichedText,
        dialog: Dialog,
    };

    const Dialog = struct {
        paragraphs: []DialogParagraph,
        endWithNewline: bool,
    };

    const DialogParagraph = union(enum) {
        dialogNewSpeaker: DialogNewSpeaker,
        dialogSameSpeaker: DialogSameSpeaker,
    };

    const DialogNewSpeaker = struct {
        text: EnrichedText,
    };

    const DialogSameSpeaker = struct {
        text: EnrichedText,
    };
};

// GRAMMAR
// Root <- NovelTitle? [Chapter]
// ChapterTitle <- ## EnrichedText
// Chapter <- ChapterTitle [Text]
// Text <- EnrichedText | Dialog
// EnrichedText <- [SimpleText | EmphText]
// SimpleText <- a..zA..Z
// EmphText <- _ SimpleText _
// Dialog <- " [DialogParagraph] "
// DialogParagraph <- DialogNewSpeak | EmphText
// DialogNewSpeak <- - EmphText

const Parser = struct {
    gpa: *std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    token_index: usize,

    fn parseRoot(p: *Parser) !Node.Root {
        //std.log.info("parseRoot", .{});
        var title = try p.parseNovelTitle();
        var chapters = std.ArrayList(Node.Chapter).init(p.gpa);
        while (p.token_index < p.tokens.len) {
            while (p.tokens[p.token_index].tag == .newline) p.token_index += 1;
            try chapters.append(try p.parseChapter());
        }
        return Node.Root{
            .title = title,
            .chapters = chapters.items,
        };
    }

    fn parseChapter(p: *Parser) !Node.Chapter {
        //std.log.info("parseChapter", .{});
        return Node.Chapter{
            .title = try p.parseChapterTitle(),
            .texts = try p.parseTextBlock(),
        };
    }

    fn parseChapterTitle(p: *Parser) !?Node.ChapterTitle {
        //std.log.info("parseChapterTitle", .{});
        if (p.tokens[p.token_index].tag == .hashtag) {
            p.token_index += 1;
            if (p.tokens[p.token_index].tag == .hashtag) {
                p.token_index += 1;
                return Node.ChapterTitle{
                    .text = try p.parseSimpleText(),
                };
            } else {
                return null;
            }
        } else {
            return null;
        }
    }

    fn parseNovelTitle(p: *Parser) !?Node.NovelTitle {
        //std.log.info("parseNovelTitle", .{});
        if (p.tokens[p.token_index].tag == .hashtag) {
            p.token_index += 1;
            return Node.NovelTitle{
                .title = try p.parseSimpleText(),
            };
        } else {
            return null;
        }
    }

    fn parseSimpleText(p: *Parser) !Node.SimpleText {
        //std.log.info("parseSimpleText", .{});
        if (p.tokens[p.token_index].tag != .text) return error.ParseError;
        p.token_index += 1;
        return Node.SimpleText{
            .token = p.tokens[p.token_index - 1],
        };
    }

    fn parseTextBlock(p: *Parser) ![]Node.Text {
        //std.log.info("parseTextBlock {}", .{p.tokens[p.token_index]});

        var texts = std.ArrayList(Node.Text).init(p.gpa);
        while (p.token_index < p.tokens.len and (p.tokens[p.token_index].tag == .quotationMark or p.tokens[p.token_index].tag == .text or p.tokens[p.token_index].tag == .newline)) {
            if (p.tokens[p.token_index].tag == .quotationMark) {
                try texts.append(.{
                    .dialog = try p.parseDialog(),
                });
            } else if (p.tokens[p.token_index].tag == .text) {
                try texts.append(.{
                    .enrichedText = try p.parseEnrichedText(),
                });
            } else {
                p.token_index += 1;
            }
        }

        return texts.items;
    }

    fn parseEmphText(p: *Parser) !Node.EmphText {
        //std.log.info("parseEmphText", .{});
        if (p.tokens[p.token_index].tag != .underscore) return error.ParseError;
        p.token_index += 1;

        var simpleText = try p.parseSimpleText();

        if (p.tokens[p.token_index].tag != .underscore) return error.ParseError;
        p.token_index += 1;

        return Node.EmphText{
            .simpleText = simpleText,
        };
    }

    fn parseSimpleOrEmphText(p: *Parser) !Node.SimpleOrEmpthText {
        //std.log.info("parseSimpleOrEmphText", .{});
        if (p.tokens[p.token_index].tag == .underscore) {
            return Node.SimpleOrEmpthText{
                .emphText = try p.parseEmphText(),
            };
        } else {
            return Node.SimpleOrEmpthText{
                .simpleText = try p.parseSimpleText(),
            };
        }
    }

    fn parseEnrichedText(p: *Parser) !Node.EnrichedText {
        //std.log.info("parseEnrichedText", .{});
        var texts = std.ArrayList(Node.SimpleOrEmpthText).init(p.gpa);
        while (p.token_index < p.tokens.len and (p.tokens[p.token_index].tag == .underscore or p.tokens[p.token_index].tag == .text or p.tokens[p.token_index].tag == .newline)) {
            if (p.tokens[p.token_index].tag == .newline) {
                p.token_index += 1;
                break;
            }
            try texts.append(try p.parseSimpleOrEmphText());
            if (p.tokens[p.token_index - 1].tag == .text and p.token_index < p.tokens.len and p.tokens[p.token_index].tag == .text) break;
        }
        return Node.EnrichedText{
            .texts = texts.items,
            .endWithNewline = p.tokens[p.token_index - 1].tag == .newline,
        };
    }

    fn parseDialogSameSpeaker(p: *Parser) !Node.DialogSameSpeaker {
        //std.log.info("parseDialogSameSpeaker", .{});
        return Node.DialogSameSpeaker{
            .text = try p.parseEnrichedText(),
        };
    }

    fn parseDialogNewSpeaker(p: *Parser) !Node.DialogNewSpeaker {
        //std.log.info("parseDialogNewSpeaker", .{});
        if (p.tokens[p.token_index].tag != .dashDialogStart) return error.ParseError;
        p.token_index += 1;
        return Node.DialogNewSpeaker{
            .text = try p.parseEnrichedText(),
        };
    }

    fn parseDialogParagraph(p: *Parser) !Node.DialogParagraph {
        //std.log.info("parseDialogParagraph", .{});
        if (p.tokens[p.token_index].tag == .dashDialogStart) {
            return Node.DialogParagraph{
                .dialogNewSpeaker = try p.parseDialogNewSpeaker(),
            };
        } else {
            return Node.DialogParagraph{
                .dialogSameSpeaker = try p.parseDialogSameSpeaker(),
            };
        }
    }

    fn parseDialog(p: *Parser) !Node.Dialog {
        //std.log.info("parseDialog", .{});
        if (p.tokens[p.token_index].tag != .quotationMark) return error.ParseError;
        p.token_index += 1;

        var paragraphs = std.ArrayList(Node.DialogParagraph).init(p.gpa);
        try paragraphs.append(.{
            .dialogSameSpeaker = try p.parseDialogSameSpeaker(),
        });
        while (p.tokens[p.token_index].tag != .quotationMark) {
            try paragraphs.append(try p.parseDialogParagraph());
        }
        p.token_index += 1;
        var endWithNewline = false;
        if (p.token_index < p.tokens.len and p.tokens[p.token_index].tag == .newline) {
            endWithNewline = true;
            p.token_index += 1;
        }
        return Node.Dialog{
            .paragraphs = paragraphs.items,
            .endWithNewline = endWithNewline,
        };
    }
};

fn parse(gpa: *std.mem.Allocator, source: []const u8) !Node.Root {
    var tokens = std.ArrayList(Token).init(gpa);
    var tokenizer = Tokenizer.init(source);

    var token = tokenizer.next();
    while (token.tag != .eof) : (token = tokenizer.next()) {
        try tokens.append(token);
    }

    var parser = Parser{
        .gpa = gpa,
        .source = source,
        .tokens = tokens.items,
        .token_index = 0,
    };

    return try parser.parseRoot();
}

const Renderer = struct {
    source: []const u8,

    fn renderSimpleText(renderer: *const Renderer, text: Node.SimpleText) void {
        std.debug.print("{s}", .{renderer.source[text.token.loc.start..text.token.loc.end]});
    }

    fn renderNovelTitle(renderer: *const Renderer, title: Node.NovelTitle) void {
        std.debug.print("## ", .{});
        renderer.renderSimpleText(title.title);
        std.debug.print("\n\n\n", .{});
    }

    fn renderEmphText(renderer: *const Renderer, emph: Node.EmphText) void {
        std.debug.print("\\emph{{", .{});
        renderer.renderSimpleText(emph.simpleText);
        std.debug.print("}}", .{});
    }

    fn renderSimpleOrEmph(renderer: *const Renderer, simpleOrEmph: Node.SimpleOrEmpthText) void {
        switch (simpleOrEmph) {
            .simpleText => |simple| renderer.renderSimpleText(simple),
            .emphText => |emph| renderer.renderEmphText(emph),
        }
    }

    fn renderEnrichedText(renderer: *const Renderer, enrichedText: Node.EnrichedText) void {
        for (enrichedText.texts) |simpleOrEmph| {
            renderer.renderSimpleOrEmph(simpleOrEmph);
        }
        if (enrichedText.endWithNewline) {
            std.debug.print("\n", .{});
        }
    }

    fn renderDialogNewSpeaker(renderer: *const Renderer, dialogNewSpeaker: Node.DialogNewSpeaker) void {
        std.debug.print("— ", .{});
        renderer.renderEnrichedText(dialogNewSpeaker.text);
    }

    fn renderDialogSameSpeaker(renderer: *const Renderer, dialogSameSpeaker: Node.DialogSameSpeaker) void {
        renderer.renderEnrichedText(dialogSameSpeaker.text);
    }

    fn renderDialogParagraph(renderer: *const Renderer, dialogParagraph: Node.DialogParagraph) void {
        switch (dialogParagraph) {
            .dialogNewSpeaker => |dialogNewSpeaker| renderer.renderDialogNewSpeaker(dialogNewSpeaker),
            .dialogSameSpeaker => |dialogSameSpeaker| renderer.renderDialogSameSpeaker(dialogSameSpeaker),
        }
    }

    fn renderDialog(renderer: *const Renderer, dialog: Node.Dialog) void {
        if (dialog.paragraphs.len > 0) {
            std.debug.print("«", .{});
            renderer.renderDialogParagraph(dialog.paragraphs[0]);
            if (dialog.paragraphs.len > 1) {
                std.debug.print("\n\n", .{});
                for (dialog.paragraphs[1 .. dialog.paragraphs.len - 1]) |p| {
                    renderer.renderDialogParagraph(p);
                    std.debug.print("\n\n", .{});
                }
                renderer.renderDialogParagraph(dialog.paragraphs[dialog.paragraphs.len - 1]);
            }
            std.debug.print("»", .{});
        }
        if (dialog.endWithNewline) {
            std.debug.print("\n\n", .{});
        }
    }

    fn renderText(renderer: *const Renderer, text: Node.Text) void {
        switch (text) {
            .enrichedText => |enrichedText| {
                renderer.renderEnrichedText(enrichedText);
                std.debug.print("\n\n", .{});
            },
            .dialog => |dialog| renderer.renderDialog(dialog),
        }
    }

    fn renderChapterTitle(renderer: *const Renderer, chapterTitle: Node.ChapterTitle) void {
        std.debug.print("\\ChapterStart{{", .{});
        renderer.renderSimpleText(chapterTitle.text);
        std.debug.print("}}\n\n", .{});
    }

    fn renderChapter(renderer: *const Renderer, chapter: Node.Chapter) void {
        if (chapter.title) |title| {
            renderer.renderChapterTitle(title);
        }
        for (chapter.texts) |text| {
            renderer.renderText(text);
        }
    }

    fn renderRoot(renderer: *const Renderer, root: Node.Root) void {
        if (root.title) |title| {
            renderer.renderNovelTitle(title);
        }
        for (root.chapters) |chapter| {
            renderer.renderChapter(chapter);
        }
    }
};

pub fn main() anyerror!void {
    var argsIt = std.process.args();
    defer argsIt.deinit();
    const processName = try argsIt.next(std.heap.page_allocator).?;
    std.heap.page_allocator.free(processName);
    const filepath = try argsIt.next(std.heap.page_allocator).?;
    defer std.heap.page_allocator.free(filepath);

    const input = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, filepath, 1024 * 1024);

    var root = try parse(std.heap.page_allocator, input);
    const renderer = Renderer{
        .source = input,
    };
    renderer.renderRoot(root);
}
