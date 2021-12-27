const template = @embedFile("../template.tex");
const std = @import("std");

// TODO
// * proper templated with something like mustache
// * ability to pass author and below title as arguments
// * do not hardcode out file path, make it specifiable
// * make the template file specifiable
// * improve lexer and parser code
// * avoid infinite loop when errors in input file

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
        sceneBreak,
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
                        if (self.index + 2 < self.buffer.len and self.buffer[self.index + 1] == '-' and self.buffer[self.index + 2] == '-') {
                            result.tag = .sceneBreak;
                            self.index += 3;
                        } else {
                            result.tag = .dashDialogStart;
                            self.index += 1;
                        }
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

    const NewlineType = enum {
        none,
        simple,
        double,
    };

    const EnrichedText = struct {
        texts: []SimpleOrEmpthText,
        endWithNewline: NewlineType,
    };

    const Text = union(enum) {
        enrichedText: EnrichedText,
        dialog: Dialog,
        sceneBreak: void,
    };

    const Dialog = struct {
        paragraphs: []DialogParagraph,
        endWithNewline: NewlineType,
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
// Text <- EnrichedText | Dialog | SceneBreak
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
        while (p.token_index < p.tokens.len and (p.tokens[p.token_index].tag == .quotationMark or p.tokens[p.token_index].tag == .text or p.tokens[p.token_index].tag == .newline or p.tokens[p.token_index].tag == .sceneBreak)) {
            if (p.tokens[p.token_index].tag == .sceneBreak) {
                try texts.append(.{
                    .sceneBreak = {},
                });
                p.token_index += 1;
            } else if (p.tokens[p.token_index].tag == .quotationMark) {
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
        var endWithNewline = Node.NewlineType.none;
        if (p.tokens[p.token_index - 1].tag == .newline) {
            endWithNewline = Node.NewlineType.simple;
            if (p.token_index + 1 < p.tokens.len and p.tokens[p.token_index].tag == .newline and p.tokens[p.token_index + 1].tag == .newline) {
                endWithNewline = Node.NewlineType.double;
            }
        }
        return Node.EnrichedText{
            .texts = texts.items,
            .endWithNewline = endWithNewline,
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
        var endWithNewline = Node.NewlineType.none;
        if (p.token_index < p.tokens.len and p.tokens[p.token_index].tag == .newline) {
            endWithNewline = Node.NewlineType.simple;
            p.token_index += 1;
            if (p.token_index + 1 < p.tokens.len and p.tokens[p.token_index].tag == .newline and p.tokens[p.token_index + 1].tag == .newline) {
                endWithNewline = Node.NewlineType.double;
                p.token_index += 2;
            }
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
    out: std.fs.File,

    fn renderSimpleText(renderer: *const Renderer, text: Node.SimpleText) !void {
        _ = try renderer.out.write(renderer.source[text.token.loc.start..text.token.loc.end]);
    }

    fn renderNovelTitle(renderer: *const Renderer, title: Node.NovelTitle) !void {
        _ = try renderer.out.write("## ");
        try renderer.renderSimpleText(title.title);
        _ = try renderer.out.write("\n\n\n");
    }

    fn renderEmphText(renderer: *const Renderer, emph: Node.EmphText) !void {
        _ = try renderer.out.write("\\emph{");
        try renderer.renderSimpleText(emph.simpleText);
        _ = try renderer.out.write("}");
    }

    fn renderSimpleOrEmph(renderer: *const Renderer, simpleOrEmph: Node.SimpleOrEmpthText) !void {
        switch (simpleOrEmph) {
            .simpleText => |simple| try renderer.renderSimpleText(simple),
            .emphText => |emph| try renderer.renderEmphText(emph),
        }
    }

    fn renderEnrichedText(renderer: *const Renderer, enrichedText: Node.EnrichedText) !void {
        for (enrichedText.texts) |simpleOrEmph| {
            try renderer.renderSimpleOrEmph(simpleOrEmph);
        }
        switch (enrichedText.endWithNewline) {
            .none => {},
            .simple => _ = try renderer.out.write("\n\n"),
            .double => _ = try renderer.out.write("\\\\\n\n"),
        }
    }

    fn renderDialogNewSpeaker(renderer: *const Renderer, dialogNewSpeaker: Node.DialogNewSpeaker) !void {
        _ = try renderer.out.write("— ");
        try renderer.renderEnrichedText(dialogNewSpeaker.text);
    }

    fn renderDialogSameSpeaker(renderer: *const Renderer, dialogSameSpeaker: Node.DialogSameSpeaker) !void {
        try renderer.renderEnrichedText(dialogSameSpeaker.text);
    }

    fn renderDialogParagraph(renderer: *const Renderer, dialogParagraph: Node.DialogParagraph) !void {
        switch (dialogParagraph) {
            .dialogNewSpeaker => |dialogNewSpeaker| try renderer.renderDialogNewSpeaker(dialogNewSpeaker),
            .dialogSameSpeaker => |dialogSameSpeaker| try renderer.renderDialogSameSpeaker(dialogSameSpeaker),
        }
    }

    fn renderDialog(renderer: *const Renderer, dialog: Node.Dialog) !void {
        if (dialog.paragraphs.len > 0) {
            _ = try renderer.out.write("«");
            try renderer.renderDialogParagraph(dialog.paragraphs[0]);
            if (dialog.paragraphs.len > 1) {
                _ = try renderer.out.write("\n\n");
                for (dialog.paragraphs[1 .. dialog.paragraphs.len - 1]) |p| {
                    try renderer.renderDialogParagraph(p);
                    _ = try renderer.out.write("\n\n");
                }
                try renderer.renderDialogParagraph(dialog.paragraphs[dialog.paragraphs.len - 1]);
            }
            _ = try renderer.out.write("»");
        }
        switch (dialog.endWithNewline) {
            .none => {},
            .simple => _ = try renderer.out.write("\n\n"),
            .double => _ = try renderer.out.write("\\\\\n\n"),
        }
    }

    fn renderSceneBreak(renderer: *const Renderer) !void {
        _ = try renderer.out.write("\\sceneline\n");
    }

    fn renderText(renderer: *const Renderer, text: Node.Text) !void {
        switch (text) {
            .enrichedText => |enrichedText| {
                try renderer.renderEnrichedText(enrichedText);
            },
            .dialog => |dialog| try renderer.renderDialog(dialog),
            .sceneBreak => try renderer.renderSceneBreak(),
        }
    }

    fn renderChapterTitle(renderer: *const Renderer, chapterTitle: Node.ChapterTitle) !void {
        _ = try renderer.out.write("\\clearpage\n\\begin{ChapterStart}");
        _ = try renderer.out.write("\\ChapterTitle{");
        try renderer.renderSimpleText(chapterTitle.text);
        _ = try renderer.out.write("}\\end{ChapterStart}\n\n");
    }

    fn renderChapter(renderer: *const Renderer, chapter: Node.Chapter) !void {
        if (chapter.title) |title| {
            try renderer.renderChapterTitle(title);
        } else {
            _ = try renderer.out.write("\\clearpage\n\\begin{ChapterStart}\\end{ChapterStart}");
        }
        for (chapter.texts) |text| {
            try renderer.renderText(text);
        }
    }

    fn renderRoot(renderer: *const Renderer, root: Node.Root) !void {
        if (root.title) |title| {
            try renderer.renderNovelTitle(title);
        }
        for (root.chapters) |chapter| {
            try renderer.renderChapter(chapter);
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
        .out = try std.fs.cwd().createFile("/tmp/out.tex", .{}),
    };

    var template_iterator = std.mem.split(template, "{{}}");
    const before_title = template_iterator.next().?;
    const after_title_before_author = template_iterator.next().?;
    const after_author_before_below_text = template_iterator.next().?;
    const after_below_text_before_main = template_iterator.next().?;
    const after_main = template_iterator.next().?;

    _ = try renderer.out.write(before_title);
    try renderer.renderSimpleText(root.title.?.title);
    _ = try renderer.out.write(after_title_before_author);
    _ = try renderer.out.write("Hugo Viala");
    _ = try renderer.out.write(after_author_before_below_text);
    _ = try renderer.out.write("EDITIONS DE SOHEN • NANTES");
    _ = try renderer.out.write(after_below_text_before_main);
    for (root.chapters) |chapter| {
        try renderer.renderChapter(chapter);
    }
    _ = try renderer.out.write(after_main);

    const latexCompilationResult = try std.ChildProcess.exec(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "lualatex", "/tmp/out.tex" },
    });
    std.debug.print("{s}\n", .{latexCompilationResult.stdout});
}
