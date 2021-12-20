const std = @import("std");

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
        eof,
    };
};

const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn init(buffer: [:0]const u8) Tokenizer {
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

        while (true) : (self.index += 1) {
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
                        state = .start;
                        self.index -= 1;
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
        chapterTitle: ChapterTitle,
        simpleText: SimpleText,
        emphText: EmphText,
        text: Text,
        dialog: Dialog,
        dialogLine: DialogLine,
    };

    const Root = struct {
        title: ?ChapterTitle,
        texts: []Text,
    };

    const ChapterTitle = struct {
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
    };

    const Text = union(enum) {
        enrichedText: EnrichedText,
        dialog: Dialog,
    };

    const Dialog = struct {
        lines: []EnrichedText,
    };
};

// GRAMMAR
// Root <- ChapterTitle? [Text]
// ChapterTitle <- # EnrichedText
// Text <- EnrichedText | Dialog
// EnrichedText <- [SimpleText | EmphText]
// SimpleText <- a..zA..Z
// EmphText <- _ SimpleText _
// Dialog <- " [EnrichedText] "

const Parser = struct {
    gpa: *std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    token_index: usize,

    fn parseRoot(p: *Parser) !Node.Root {
        return Node.Root{
            .title = try p.parseChapterTitle(),
            .texts = try p.parseTextBlock(),
        };
    }

    fn parseChapterTitle(p: *Parser) !?Node.ChapterTitle {
        if (p.tokens[p.token_index].tag == .hashtag) {
            p.token_index += 1;
            return Node.ChapterTitle{
                .title = try p.parseSimpleText(),
            };
        } else {
            return null;
        }
    }

    fn parseSimpleText(p: *Parser) !Node.SimpleText {
        if (p.tokens[p.token_index].tag != .text) return error.ParseError;
        p.token_index += 1;
        return Node.SimpleText{
            .token = p.tokens[p.token_index - 1],
        };
    }

    fn parseTextBlock(p: *Parser) ![]Node.Text {
        var texts = std.ArrayList(Node.Text).init(p.gpa);
        while (p.token_index < p.tokens.len) {
            if (p.tokens[p.token_index].tag == .quotationMark) {
                try texts.append(.{
                    .dialog = try p.parseDialog(),
                });
            } else {
                try texts.append(.{
                    .enrichedText = try p.parseEnrichedText(),
                });
            }
        }

        return texts.items;
    }

    fn parseEmphText(p: *Parser) !Node.EmphText {
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
        var texts = std.ArrayList(Node.SimpleOrEmpthText).init(p.gpa);
        while (p.token_index < p.tokens.len and (p.tokens[p.token_index].tag == .underscore or p.tokens[p.token_index].tag == .text)) {
            try texts.append(try p.parseSimpleOrEmphText());
            if (p.tokens[p.token_index - 1].tag == .text and p.token_index < p.tokens.len and p.tokens[p.token_index].tag == .text) break;
        }
        return Node.EnrichedText{
            .texts = texts.items,
        };
    }

    fn parseDialog(p: *Parser) !Node.Dialog {
        if (p.tokens[p.token_index].tag != .quotationMark) return error.ParseError;
        p.token_index += 1;

        var lines = std.ArrayList(Node.EnrichedText).init(p.gpa);
        try lines.append(try p.parseEnrichedText());
        while (p.tokens[p.token_index].tag != .quotationMark) {
            if (p.tokens[p.token_index].tag != .dashDialogStart) return error.ParseError;
            p.token_index += 1;
            try lines.append(try p.parseEnrichedText());
        }
        p.token_index += 1;
        return Node.Dialog{
            .lines = lines.items,
        };
    }
};

fn parse(gpa: *std.mem.Allocator, source: [:0]const u8) !Node.Root {
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

    fn renderChapterTitle(renderer: *const Renderer, title: Node.ChapterTitle) void {
        std.debug.print("## ", .{});
        renderer.renderSimpleText(title.title);
        std.debug.print("\n\n\n", .{});
    }

    fn renderEmphText(renderer: *const Renderer, emph: Node.EmphText) void {
        std.debug.print("__", .{});
        renderer.renderSimpleText(emph.simpleText);
        std.debug.print("__", .{});
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
    }

    fn renderDialog(renderer: *const Renderer, dialog: Node.Dialog) void {
        if (dialog.lines.len > 0) {
            std.debug.print("«", .{});
            renderer.renderEnrichedText(dialog.lines[0]);
            for (dialog.lines[1..]) |line| {
                std.debug.print("\n\n--- ", .{});
                renderer.renderEnrichedText(line);
            }
            std.debug.print("»", .{});
        }
    }

    fn renderText(renderer: *const Renderer, text: Node.Text) void {
        switch (text) {
            .enrichedText => |enrichedText| renderer.renderEnrichedText(enrichedText),
            .dialog => |dialog| renderer.renderDialog(dialog),
        }
        std.debug.print("\n\n", .{});
    }

    fn renderRoot(renderer: *const Renderer, root: Node.Root) void {
        if (root.title) |title| {
            renderer.renderChapterTitle(title);
        }
        for (root.texts) |text| {
            renderer.renderText(text);
        }
    }
};

pub fn main() anyerror!void {
    const input = "# Le titre du chapitre\n\nUn texte court avant le dialogue.\n\"bonjour\n- ça va ?\n- oui et toi _Jean-Jacques_ ?\"\n\"\" iiiii\neeeeee";
    var root = try parse(std.heap.page_allocator, input);
    const renderer = Renderer{
        .source = input,
    };
    renderer.renderRoot(root);
}
