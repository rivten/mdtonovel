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
        simpleText: *SimpleText,
    };

    const Text = union(enum) {
        simpleText: *SimpleText,
        emphText: *EmphText,
    };

    const Dialog = struct {
        lines: []DialogLine,
    };

    const DialogLine = struct {
        text: *Text,
    };
};

// GRAMMAR
// Root <- ChapterTitle? [Text]
// ChapterTitle <- # Text
// Text <- SimpleText | EmphText | Dialog
// SimpleText <- a..zA..Z
// EmphText <- _ SimpleText _
// Dialog <- " [DialogLine] "
// DialogLine <- SimpleText | EmphText

const Parser = struct {
    gpa: *std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    token_index: usize,

    fn parseRoot(p: *Parser) Node.Root {
        return Node.Root{
            .title = p.parseChapterTitle(),
            .texts = &[_]Node.Text{},
        };
    }

    fn parseChapterTitle(p: *Parser) ?Node.ChapterTitle {
        if (p.tokens[p.token_index].tag == .hashtag) {
            p.token_index += 1;
            return Node.ChapterTitle{
                .title = p.parseSimpleText(),
            };
        } else {
            return null;
        }
    }

    fn parseSimpleText(p: *Parser) Node.SimpleText {
        if (p.tokens[p.token_index].tag != .text) std.os.abort();
        p.token_index += 1;
        return Node.SimpleText{
            .token = p.tokens[p.token_index - 1],
        };
    }

    fn eatToken(p: *Parser, tokenTag: Token.Tag) void {
        if (p.tokens[p.token_index].tag == tokenTag) {
            p.token_index += 1;
        } else {
            std.os.abort();
        }
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

    return parser.parseRoot();
}

pub fn main() anyerror!void {
    const input = "# Le titre du chapitre\n\nUn texte court avant le dialogue.\n\"bonjour\n- ça va ?\n- oui et toi _Jean-Jacques_ ?\"\n\"\"\" iiiii\neeeeee";
    var root = try parse(std.heap.page_allocator, input);
    std.log.info("{} <<{s}>>", .{ root.title, input[root.title.?.title.token.loc.start..root.title.?.title.token.loc.end] });
}

test "parseDialog" {}
