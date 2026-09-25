.pragma library
.import "GitHubLogic.js" as Logic
.import "GitHubEmoji.js" as Emoji

// GitHub-flavored Markdown as the popout carries it (GitHubMarkdown.qml
// draws it): parsed into blocks that each render as their own item, with
// inline markup as rich text in the theme's colors. It reads what
// github.com renders in issues, pull requests, and comments:
//
// - blocks: ATX and setext headings; paragraphs, whose line breaks stay
//   (as in comments there); block quotes and the alerts ([!NOTE], [!TIP],
//   [!IMPORTANT], [!WARNING], [!CAUTION]), which hold blocks of their own;
//   bullet, numbered, nested, and task lists whose items hold blocks too;
//   fenced and indented code, with its language (diff, suggestion, math,
//   mermaid, ...); display math ($$ and ```math); pipe tables with column
//   alignment; horizontal rules; lines of images; video attachments;
//   footnotes; collapsible sections (<details> and <summary>), which hold
//   blocks of their own.
// - inline: bold, italic, strikethrough (** __ * _ ~~ ~), code spans (with
//   the color swatch of a color), links (inline, reference, autolinks,
//   bare URLs, www. and mail addresses), inline math, backslash escapes,
//   HTML entities, :emoji: shortcodes, @user and @org/team mentions, and
//   #12, GH-12, owner/repo#12, owner/repo@sha, and full commit SHAs as
//   GitHub links, which read as github.com shortens them.
// - HTML, as GitHub lets it through: comments drop; <b> <i> <em> <strong>
//   <s> <del> <ins> <sub> <sup> <small> <mark> <kbd> <code> <tt> <samp>
//   <var> <q> and <a href> keep their meaning; <img> is an image (its width
//   kept); <br> a line break; <pre> code; <h1>-<h6> headings; <hr> a rule;
//   <table> a table; <ul>/<ol>/<li> a list; <blockquote> a quote; <p
//   align>, <div align>, and <center> center or right-align what they
//   hold; other tags drop for their text.
//
// Code keeps every character: fenced and indented code and code spans are
// set aside before anything else is read. The rest is written by anyone,
// so none of it reaches the rich text as markup: its text is escaped, and
// only the tags written here go through (an image loads only from the
// signed URL GitHub rendered for it, never from rich text).
//
// style: { link, codeFont, codeSize, codeBackground, codeText,
// keyBackground, mark, dark (the shell's scheme, which picks a picture's
// image) }.

var escapeHtml = Logic.escapeHtml;

// ---------------------------------------------------------------- links

function linkOpen(url, style) {
    return "<a href=\"" + escapeHtml(url) + "\" style=\"text-decoration:none\"><span style=\"color:" + String(style.link) + "\">";
}

var LINK_CLOSE = "</span></a>";

function linkHtml(url, html, style) {
    return linkOpen(url, style) + html + LINK_CLOSE;
}

function monoHtml(text, style) {
    return "<span style=\"font-family:'" + style.codeFont + "'\">" + escapeHtml(text) + "</span>";
}

// Code's face on its tint, as a code span or <code> shows it, or a size
// smaller on its own color as a <kbd> key.
function codeOpen(style, key) {
    const background = key ? style.keyBackground || style.codeBackground : style.codeBackground;
    return "<span style=\"font-family:'" + style.codeFont + "'; font-size:" + Math.round(style.codeSize - (key ? 1 : 0)) + "px; background-color:" + String(background) + "; color:" + String(style.codeText) + "\">";
}

// How github.com shows a link to itself: a reference (#12, or owner/repo#12
// from elsewhere, "(comment)" or "(review)" for a link into one), a commit
// as its short SHA; other links read as written.
function linkLabelHtml(url, repo, style) {
    const ref = url.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/(?:pull|issues|discussions)\/(\d+)\/?(#(?:issuecomment|discussioncomment|discussion_r)-?\d+|#pullrequestreview-\d+)?$/);
    if (ref)
        return escapeHtml((ref[1] === repo ? "" : ref[1]) + "#" + ref[2] + (ref[3] ? (ref[3].indexOf("review") >= 0 ? " (review)" : " (comment)") : ""));
    const commit = url.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/commit\/([0-9a-f]{7,40})\/?$/);
    if (commit)
        return (commit[1] === repo ? "" : escapeHtml(commit[1]) + "@") + monoHtml(commit[2].slice(0, 7), style);
    return escapeHtml(url);
}

// The color a code span names (#rgb, #rrggbb, rgb(), rgba(), hsl(), hsla()),
// as #rrggbb, or "": github.com shows a swatch after it.
function spanColor(code) {
    const text = String(code).trim();
    const hex = text.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
    if (hex)
        return "#" + (hex[1].length === 3 ? hex[1].split("").map(c => c + c).join("") : hex[1]).toLowerCase();
    const two = n => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0");
    const rgb = text.match(/^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+%?\s*)?\)$/);
    if (rgb)
        return "#" + two(+rgb[1]) + two(+rgb[2]) + two(+rgb[3]);
    const hsl = text.match(/^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*[\d.]+%?\s*)?\)$/);
    if (hsl) {
        const h = (+hsl[1] % 360) / 360, s = Math.min(100, +hsl[2]) / 100, l = Math.min(100, +hsl[3]) / 100;
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
        const channel = t => {
            t = (t + 1) % 1;
            return 255 * (t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p);
        };
        return "#" + two(channel(h + 1 / 3)) + two(channel(h)) + two(channel(h - 1 / 3));
    }
    return "";
}

function codeSpanHtml(code, style) {
    const color = spanColor(code);
    return codeOpen(style, false) + "&nbsp;" + escapeHtml(code) + (color ? "&nbsp;" + Logic.tint(color, "●") : "") + "&nbsp;</span>";
}

function emojify(s) {
    return s.replace(/:([a-z0-9_+-]+):/g, (m, name) => Object.prototype.hasOwnProperty.call(Emoji.EMOJI, name) ? Emoji.EMOJI[name] : m);
}

// A link's text: escaped, with its emphasis and emoji.
function labelHtml(label) {
    return emojify(emphasis(escapeHtml(label)));
}

function emphasis(s) {
    s = s.replace(/(\*\*\*|___)(?=\S)([\s\S]*?\S)\1/g, "<b><i>$2</i></b>");
    s = s.replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, "<b>$1</b>");
    s = s.replace(/(^|[^\w])__(?=\S)([\s\S]*?\S)__(?!\w)/g, "$1<b>$2</b>");
    s = s.replace(/(^|[^*])\*(?=[^\s*])([^*\n]*?[^\s*])\*(?!\*)/g, "$1<i>$2</i>");
    s = s.replace(/(^|[^_\w])_(?=\S)([^_\n]*?\S)_(?!\w)/g, "$1<i>$2</i>");
    s = s.replace(/~~(?=\S)([\s\S]*?\S)~~/g, "<s>$1</s>");
    s = s.replace(/(^|[^~])~(?=[^\s~])([^~\n]*?[^\s~])~(?!~)/g, "$1<s>$2</s>");
    return s;
}

// Sets text aside behind a marker no body contains (its index between two
// control characters, which parseMarkdown takes out of every body) while
// the rest is rewritten, and puts it back, kept text inside kept text too
// (which can only hold what was kept before it).
function stasher() {
    const kept = [];
    const put = text => text.replace(/\u0001(\d+)\u0002/g, (m, i) => put(kept[Number(i)]));
    return {
        "keep": text => {
            kept.push(text);
            return "\u0001" + (kept.length - 1) + "\u0002";
        },
        "restore": put
    };
}

// ----------------------------------------------------------------- math
//
// TeX as text: Greek letters, operators, relations, and arrows become their
// characters, fractions a/b, roots √, scripts sub and sup, and variables
// italic, in a serif face, as MathJax sets it on github.com. What it cannot
// read shows as written.

var TEX_SYMBOLS = {
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
    "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
    "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ",
    "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
    "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    "times": "×", "cdot": "⋅", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆", "circ": "∘", "bullet": "∙",
    "oplus": "⊕", "otimes": "⊗", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "ll": "≪",
    "gg": "≫", "approx": "≈", "equiv": "≡", "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "infty": "∞",
    "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭",
    "oint": "∮", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇",
    "cup": "∪", "cap": "∩", "bigcup": "⋃", "bigcap": "⋂", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
    "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬", "land": "∧", "wedge": "∧", "lor": "∨",
    "vee": "∨", "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "Rightarrow": "⇒", "Leftarrow": "⇐",
    "leftrightarrow": "↔", "Leftrightarrow": "⇔", "iff": "⟺", "implies": "⟹", "mapsto": "↦", "uparrow": "↑",
    "downarrow": "↓", "longrightarrow": "⟶", "longleftarrow": "⟵", "ldots": "…", "cdots": "⋯", "dots": "…",
    "vdots": "⋮", "ddots": "⋱", "perp": "⊥", "parallel": "∥", "mid": "∣", "angle": "∠", "prime": "′", "hbar": "ℏ",
    "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "langle": "⟨", "rangle": "⟩", "lceil": "⌈", "rceil": "⌉",
    "lfloor": "⌊", "rfloor": "⌋", "vert": "|", "lvert": "|", "rvert": "|", "Vert": "‖", "lVert": "‖", "rVert": "‖",
    "backslash": "∖", "top": "⊤", "bot": "⊥", "vdash": "⊢", "models": "⊨", "therefore": "∴", "because": "∵",
    "degree": "°", "quad": "\u2003", "qquad": "\u2003\u2003", "cdotp": "⋅", "colon": ":"
};
var TEX_WORDS = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "log", "ln", "lg", "exp", "lim", "liminf", "limsup", "max", "min", "sup", "inf", "arg", "det", "dim", "deg", "gcd", "ker", "hom", "Pr", "mod", "bmod"];
var TEX_ACCENTS = {
    "hat": "\u0302", "widehat": "\u0302", "bar": "\u0304", "overline": "\u0305", "vec": "\u20d7", "dot": "\u0307",
    "ddot": "\u0308", "tilde": "\u0303", "widetilde": "\u0303", "acute": "\u0301", "grave": "\u0300", "check": "\u030c"
};
var TEX_BLACKBOARD = { "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ", "E": "𝔼", "F": "𝔽" };
var TEX_SKIP = ["left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits", "mathstrut", "notag", "nonumber", "label"];

function texHtml(tex) {
    const s = String(tex || "");
    const owns = (table, name) => Object.prototype.hasOwnProperty.call(table, name);
    let i = 0;
    const plain = html => html.replace(/<[^>]+>/g, "").replace(/&\w+;/g, "x");
    const wrap = html => plain(html).length > 1 ? "(" + html + ")" : html;
    // A group's text as written, braces matched ({\rm x} and \text{x}).
    function raw() {
        while (s[i] === " ")
            i++;
        if (s[i] !== "{")
            return s[i++] || "";
        let depth = 0;
        const start = ++i;
        while (i < s.length && (s[i] !== "}" || depth > 0)) {
            if (s[i] === "{")
                depth++;
            else if (s[i] === "}")
                depth--;
            i++;
        }
        return s.slice(start, i++);
    }
    function group() {
        let out = "";
        while (i < s.length && s[i] !== "}")
            out += atom();
        i++;
        return out;
    }
    function arg() {
        while (s[i] === " ")
            i++;
        if (s[i] === "{") {
            i++;
            return group();
        }
        return atom();
    }
    function command() {
        const m = s.slice(i + 1).match(/^([A-Za-z]+|.?)/);
        const name = m[1];
        i += 1 + name.length;
        if (name === "frac" || name === "dfrac" || name === "tfrac" || name === "cfrac") {
            const top = arg();
            const bottom = arg();
            return wrap(top) + "/" + wrap(bottom);
        }
        if (name === "sqrt") {
            let degree = "";
            const end = s[i] === "[" ? s.indexOf("]", i) : -1;
            if (end > i) {
                degree = "<sup>" + escapeHtml(s.slice(i + 1, end)) + "</sup>";
                i = end + 1;
            }
            return degree + "√" + wrap(arg());
        }
        if (name === "binom") {
            const n = arg();
            const k = arg();
            return "(" + n + " choose " + k + ")";
        }
        if (/^(text|textrm|textnormal|mathrm|operatorname|textsf|mathsf|texttt|mathtt|mbox|hbox)$/.test(name))
            return escapeHtml(raw());
        if (name === "textit" || name === "mathit" || name === "emph")
            return "<i>" + escapeHtml(raw()) + "</i>";
        if (/^(textbf|mathbf|boldsymbol|bm)$/.test(name))
            return "<b>" + arg() + "</b>";
        if (name === "mathbb" || name === "Bbb")
            return escapeHtml(raw().split("").map(c => owns(TEX_BLACKBOARD, c) ? TEX_BLACKBOARD[c] : c).join(""));
        if (name === "mathcal" || name === "mathscr" || name === "mathfrak")
            return arg();
        if (owns(TEX_ACCENTS, name)) {
            const body = arg();
            return body.replace(/(<\/i>)?$/, TEX_ACCENTS[name] + "$1");
        }
        if (name === "begin" || name === "end") {
            raw();
            return "";
        }
        if (TEX_SKIP.indexOf(name) >= 0) {
            // \left. has no delimiter to show.
            if (s[i] === ".")
                i++;
            return "";
        }
        if (name === "\\")
            return "<br>";
        if (name === "," || name === ":" || name === ";" || name === " ")
            return "\u2009";
        if (name === "!")
            return "";
        if (name.length === 1)
            return escapeHtml(name);
        if (owns(TEX_SYMBOLS, name))
            return TEX_SYMBOLS[name];
        if (TEX_WORDS.indexOf(name) >= 0)
            return name;
        return escapeHtml(name);
    }
    function atom() {
        const c = s[i];
        if (c === "{") {
            i++;
            return group();
        }
        if (c === "}") {
            i++;
            return "";
        }
        if (c === "\\")
            return command();
        if (c === "^" || c === "_") {
            i++;
            const body = arg();
            return c === "^" ? "<sup>" + body + "</sup>" : "<sub>" + body + "</sub>";
        }
        if (c === "&") {
            i++;
            return "\u2003";
        }
        if (c === "'") {
            i++;
            return "′";
        }
        i++;
        return /[A-Za-z]/.test(c) ? "<i>" + c + "</i>" : escapeHtml(c);
    }
    let out = "";
    try {
        while (i < s.length)
            out += atom();
    } catch (e) {
        // Nested past what the stack holds.
        out = escapeHtml(s);
    }
    return "<span style=\"font-family:serif\">" + out.replace(/<\/i><i>/g, "") + "</span>";
}

// --------------------------------------------------------------- inline

// Inline HTML GitHub keeps, as the rich text that shows it: [open, close].
function inlineTags(style) {
    const code = codeOpen(style, false);
    return {
        "b": ["<b>", "</b>"],
        "strong": ["<b>", "</b>"],
        "i": ["<i>", "</i>"],
        "em": ["<i>", "</i>"],
        "var": ["<i>", "</i>"],
        "cite": ["<i>", "</i>"],
        "dfn": ["<i>", "</i>"],
        "s": ["<s>", "</s>"],
        "strike": ["<s>", "</s>"],
        "del": ["<s>", "</s>"],
        "ins": ["<u>", "</u>"],
        "u": ["<u>", "</u>"],
        "sub": ["<sub>", "</sub>"],
        "sup": ["<sup>", "</sup>"],
        "small": ["<small>", "</small>"],
        "big": ["<big>", "</big>"],
        "mark": ["<span style=\"background-color:" + String(style.mark || style.codeBackground) + "\">", "</span>"],
        "code": [code, "</span>"],
        "tt": [code, "</span>"],
        "samp": [code, "</span>"],
        "kbd": [codeOpen(style, true) + "&nbsp;", "&nbsp;</span>"],
        "q": ["“", "”"]
    };
}

// Tags that say nothing inline, and block tags the cleaning left behind (a
// stray closing tag, one inside a table cell): they drop for their text.
var DROPPED_TAGS = ["span", "font", "abbr", "bdo", "time", "wbr", "picture", "source", "center", "figure", "figcaption", "caption", "ruby", "rt", "rp", "dl", "dt", "dd", "thead", "tbody", "tfoot", "tr", "td", "th", "table", "ul", "ol", "li", "p", "div", "details", "summary", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "aside", "header", "footer", "nav", "main", "video", "a", "img", "hr", "pre", "g-emoji"];

// A code span: its backticks, matched in number, not after a backslash.
var CODE_SPAN = /(^|[^\\`])(`+)([^`]|[^`][\s\S]*?[^`])\2(?!`)/g;

// "[text][label]" and "[label]" look up a definition by its label, in any
// case and spacing.
function refKey(label) {
    return String(label).trim().replace(/\s+/g, " ").toLowerCase();
}

// ctx: { repo, style, tags, refs, notes, noteOrder, anchors }
// (parseMarkdown's).
function inlineHtml(text, ctx) {
    const repo = ctx.repo || "";
    const style = ctx.style;
    const stash = stasher();
    const keep = stash.keep;
    const tags = ctx.tags || inlineTags(style);
    const link = (url, html) => keep(linkHtml(resolveUrl(url, repo), html, style));
    let s = String(text || "");
    // A backslash at the end of a line breaks it, as the line end does.
    s = s.replace(/\\\n/g, "\n");
    s = s.replace(/\$`([^`]+)`\$/g, (m, tex) => keep(texHtml(tex)));
    s = s.replace(CODE_SPAN, (m, pre, ticks, code) => pre + keep(codeSpanHtml(code.replace(/\n/g, " ").replace(/^ (.*[^ ].*) $/, "$1"), style)));
    s = s.replace(/\\([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])/g, (m, c) => keep(escapeHtml(c)));
    s = s.replace(/(^|[^\w$])\$(?=[^\s$])([^$\n]*?[^\s\\$])\$(?![\w$])/g, (m, pre, tex) => pre + keep(texHtml(tex)));
    s = s.replace(/&(#\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});/g, entity => keep(entity));
    s = s.replace(/\u0005/g, () => keep("<br>"));
    // Footnote references, numbered as they first appear.
    s = s.replace(/\[\^([^\]\s]+)\]/g, (m, label) => {
        const key = refKey(label);
        if (!ctx.notes || !(key in ctx.notes))
            return m;
        let n = ctx.noteOrder.indexOf(key);
        if (n < 0) {
            ctx.noteOrder.push(key);
            n = ctx.noteOrder.length - 1;
        }
        ctx.anchors.push("fnref-" + key);
        return keep("<sup>" + linkHtml("#fn-" + key, String(n + 1), style) + "</sup>");
    });
    // Autolinks; a link's destination in angle brackets, [text](<url>),
    // is the link's own.
    s = s.replace(/(^|[^(])<(https?:\/\/[^>\s]+)>/g, (m, pre, url) => pre + keep(linkHtml(url, linkLabelHtml(url, repo, style), style)));
    s = s.replace(/(^|[^(])<([\w.+-]+@[\w-]+(?:\.[\w-]+)+)>/g, (m, pre, mail) => pre + keep(linkHtml("mailto:" + mail, escapeHtml(mail), style)));
    // <a href> links what it holds; an anchor without one (<a name>) drops.
    const opened = [];
    s = s.replace(/<a\b([^>]*)>|<\/a\s*>/gi, (m, attrs) => {
        if (attrs === undefined)
            return opened.pop() ? keep(LINK_CLOSE) : "";
        const href = attrOf(attrs, "href");
        opened.push(href !== "");
        return href !== "" ? keep(linkOpen(resolveUrl(href, repo), style)) : "";
    });
    s = s.replace(/<(\/?)([A-Za-z][A-Za-z0-9-]*)\b[^<>]*?(\/?)>/g, (m, close, name) => {
        const tag = name.toLowerCase();
        if (Object.prototype.hasOwnProperty.call(tags, tag))
            return keep(tags[tag][close ? 1 : 0]);
        return DROPPED_TAGS.indexOf(tag) >= 0 ? "" : m;
    });
    s = s.replace(/!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?[^)]*\)/g, (m, alt, url) => link(url, escapeHtml(alt || "image")));
    s = s.replace(/\[([^\]]+)\]\(\s*<?((?:[^()\s<>]|\([^()\s]*\))*)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)/g, (m, label, url) => link(url, labelHtml(label)));
    if (ctx.refs) {
        const refLink = (m, label, ref) => {
            const found = ctx.refs[refKey(ref || label)];
            return found ? link(found, labelHtml(label)) : m;
        };
        s = s.replace(/\[([^\]]+)\]\[([^\]]*)\]/g, (m, label, ref) => refLink(m, label, ref));
        s = s.replace(/\[([^\]]+)\](?![(\[:])/g, (m, label) => refLink(m, label, ""));
    }
    s = s.replace(/(^|[^\w/])((?:https?:\/\/|www\.)(?:[^\s<>()\u0001]|\([^\s<>()]*\))+(?:[^\s<>().,;:!?'"*_~\u0001]|\([^\s<>()]*\)))/g, (m, pre, url) => {
        const www = url.indexOf("www.") === 0;
        const href = www ? "http://" + url : url;
        return pre + keep(linkHtml(href, www ? escapeHtml(url) : linkLabelHtml(href, repo, style), style));
    });
    s = s.replace(/(^|[^\w.+\/-])([\w.+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})(?![\w-])/g, (m, pre, mail) => pre + keep(linkHtml("mailto:" + mail, escapeHtml(mail), style)));
    s = escapeHtml(s);
    s = s.replace(/(^|[^\w`])([\w.-]+\/[\w.-]+)@([0-9a-f]{7,40})\b/g, (m, pre, other, sha) => pre + keep(linkHtml(Logic.commitUrl(other, sha), escapeHtml(other) + "@" + monoHtml(sha.slice(0, 7), style), style)));
    s = s.replace(/(^|[^\w`\/.-])([\w.-]+\/[\w.-]+)#(\d+)\b/g, (m, pre, other, n) => pre + keep(linkHtml(Logic.repoUrl(other) + "/issues/" + n, escapeHtml(other) + "#" + n, style)));
    s = s.replace(/(^|[^\w/`])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))(?:\/([A-Za-z0-9][\w-]*))?(?![\w-])/g, (m, pre, user, team) => pre + keep(team ? linkHtml(Logic.teamUrl(user, team), "@" + user + "/" + team, style) : linkHtml(Logic.profileUrl(user), "@" + user, style)));
    if (repo !== "") {
        s = s.replace(/(^|[^\w&/])(#|GH-)(\d+)\b/g, (m, pre, mark, n) => pre + keep(linkHtml(Logic.repoUrl(repo) + "/issues/" + n, mark + n, style)));
        s = s.replace(/(^|[^\w/@])([0-9a-f]{40})\b/g, (m, pre, sha) => pre + keep(linkHtml(Logic.commitUrl(repo, sha), monoHtml(sha.slice(0, 7), style), style)));
    }
    s = emojify(s);
    s = emphasis(s);
    s = s.replace(/\n/g, "<br>");
    return stash.restore(s);
}

// Where a link in a body leads: absolute links as written, a page anchor
// (#section) as itself for the view to scroll to, and a path the way the
// browser resolves it on the issue's page.
function resolveUrl(url, repo) {
    const text = String(url || "").trim();
    if (text === "" || /^[a-z][a-z0-9+.-]*:/i.test(text) || text.charAt(0) === "#")
        return text;
    if (text.indexOf("//") === 0)
        return "https:" + text;
    if (text.charAt(0) === "/")
        return "https://github.com" + text;
    const parts = (repo ? repo + "/issues" : "").split("/").filter(part => part !== "");
    for (const part of text.split("/")) {
        if (part === "..")
            parts.pop();
        else if (part !== ".")
            parts.push(part);
    }
    return "https://github.com/" + parts.join("/");
}

// ------------------------------------------------------------- cleaning
//
// Block structure HTML carries becomes lines parseMarkdown reads: a mark
// (MARK and a letter: D0 or D1 opens a collapsible section, closed or open,
// S its summary, E ends it; Ac or Ar aligns what follows to the center or
// the right, a ends that) or the Markdown that says the same (headings,
// images, rules, lists, tables, quotes, code). No body contains the mark,
// and BR (a line break inside a line, so a table row keeps whole) neither.
var MARK = "\u0003";
var BR = "\u0005";

var ATTRIBUTES = {};

// An attribute's value in a tag's attributes, "" when it has none.
function attrOf(attrs, name) {
    const pattern = ATTRIBUTES[name] || (ATTRIBUTES[name] = new RegExp("(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", "i"));
    const m = String(attrs || "").match(pattern);
    return m ? (m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3])) : "";
}

function alignMark(attrs) {
    const align = attrOf(attrs, "align").toLowerCase();
    return align === "center" || align === "right" ? MARK + "A" + align.charAt(0) : "";
}

var BR_EDGES = new RegExp("^[\\s" + BR + "]+|[\\s" + BR + "]+$", "g");

// An HTML table as a pipe table: its first row the header, a cell's
// alignment the column's, and what a cell holds on one line.
function tableMarkdown(html) {
    const rows = [];
    const aligns = [];
    const rowPattern = /<tr\b[^>]*>([\s\S]*?)(?=<tr\b|<\/table|$)/gi;
    let row;
    while ((row = rowPattern.exec(html)) !== null) {
        const cells = [];
        const cellPattern = /<t([hd])\b([^>]*)>([\s\S]*?)(?=<t[hd]\b|<\/tr|$)/gi;
        let cell;
        while ((cell = cellPattern.exec(row[1])) !== null) {
            if (rows.length === 0) {
                const align = attrOf(cell[2], "align").toLowerCase();
                aligns.push(align === "center" ? ":---:" : (align === "right" ? "---:" : "---"));
            }
            // Its paragraphs as lines of the cell.
            const text = cell[3].replace(/<\/t[hd]\s*>/gi, "").replace(/<\/(p|div)\s*>/gi, BR).replace(/<(p|div)\b[^>]*>/gi, "").replace(/<br\s*\/?>/gi, BR).replace(/\s*\n\s*/g, " ").replace(/\|/g, "\\|");
            cells.push(text.replace(BR_EDGES, ""));
        }
        if (cells.length > 0)
            rows.push(cells);
    }
    if (rows.length === 0)
        return "";
    const width = Math.max.apply(null, rows.map(cells => cells.length));
    while (aligns.length < width)
        aligns.push("---");
    const line = cells => "| " + Array.from({
            "length": width
        }, (_, i) => cells[i] || " ").join(" | ") + " |";
    return "\n\n" + [line(rows[0]), "| " + aligns.join(" | ") + " |"].concat(rows.slice(1).map(line)).join("\n") + "\n\n";
}

// HTML lists as Markdown ones, nested by indenting.
function listMarkdown(html) {
    const stack = [];
    return html.replace(/<(\/?)(ul|ol|li)\b[^>]*>/gi, (m, close, tag) => {
        tag = tag.toLowerCase();
        if (tag === "li") {
            if (close)
                return "";
            const indent = stack.slice(0, -1).reduce((sum, kind) => sum + (kind === "ol" ? 3 : 2), 0);
            return "\n" + " ".repeat(indent) + (stack[stack.length - 1] === "ol" ? "1. " : "- ");
        }
        if (close)
            stack.pop();
        else
            stack.push(tag);
        return close ? "\n" : "";
    });
}

// The quote markers and list markers a line starts with.
var LEAD = /^((?:[ \t]*>)*(?:[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+)*[ \t]*)/;
// A list item at any depth: its indent, marker, and the spaces after it.
var ITEM_AT = /^( *)([-*+]|\d{1,9}[.)])(?:( +)|$)/;

// A <picture> as github.com shows it: the image of its source for the
// scheme (prefers-color-scheme: dark or light) when it has one, else its
// <img>.
function pictureImage(inner, dark) {
    const img = inner.match(/<img\b[^>]*>/i);
    if (!img)
        return "";
    const scheme = new RegExp("prefers-color-scheme\\s*:\\s*" + (dark ? "dark" : "light"), "i");
    const source = (inner.match(/<source\b[^>]*>/gi) || []).find(tag => scheme.test(attrOf(tag, "media")));
    const url = source ? attrOf(source, "srcset").trim().split(/[\s,]+/)[0] : "";
    return url ? img[0].replace(/(\ssrc\s*=\s*)("[^"]*"|'[^']*'|[^\s>]+)/i, (m, name) => name + "\"" + url.replace(/"/g, "&quot;") + "\"") : img[0];
}

// A line's quote markers.
var QUOTE_MARKS = /^(?: {0,3}> ?)*/;

function quoteDepth(line) {
    return (line.match(QUOTE_MARKS)[0].match(/>/g) || []).length;
}

// Sets code aside (fenced code, in a quote or a list item too, indented
// code, in a quote or a list item too, and code spans) and reads the block
// HTML outside it: { text, with the code still set aside behind markers,
// restore(text), which puts it back as written }. `dark` picks a picture's
// image (pictureImage).
function cleanMarkdown(text, dark) {
    const stash = stasher();
    const keep = stash.keep;
    const raw = String(text || "").replace(/\r\n?/g, "\n").split("\n");
    const lines = raw.map(line => line.replace(/^\t+/, tabs => "    ".repeat(tabs.length)));
    const out = [];
    // The content columns of the list items around a line, innermost last:
    // indented code sits four columns past the innermost.
    const items = [];
    let blank = true;
    let depth = 0;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        // A quote's lines read as what follows their markers, and a quote
        // starting or ending starts a block, as a blank line does.
        const quote = line.match(QUOTE_MARKS)[0];
        const body = line.slice(quote.length);
        const level = quoteDepth(line);
        if (level !== depth) {
            blank = true;
            depth = level;
        }
        if (body.trim() === "") {
            out.push(line);
            blank = true;
            continue;
        }
        const indent = indentOf(body);
        const base = level === 0 && items.length > 0 ? items[items.length - 1] : 0;
        // Indented code starts after a blank line (a paragraph's next line
        // carries the paragraph on) and runs through blank lines; its
        // marker keeps the line's place (a footnote's indented paragraph).
        if (blank && indent >= base + 4) {
            const inCode = next => quoteDepth(next) === level && (next.slice(next.match(QUOTE_MARKS)[0].length).trim() === "" || indentOf(next.slice(next.match(QUOTE_MARKS)[0].length)) >= base + 4);
            let end = i + 1;
            while (end < lines.length && inCode(lines[end]))
                end++;
            while (end > i + 1 && lines[end - 1].slice(lines[end - 1].match(QUOTE_MARKS)[0].length).trim() === "")
                end--;
            out.push(quote + " ".repeat(indent) + keep([body.slice(indent)].concat(lines.slice(i + 1, end)).join("\n")));
            i = end - 1;
            blank = false;
            continue;
        }
        const lead = raw[i].match(LEAD)[1];
        const fence = raw[i].slice(lead.length).match(/^(`{3,}|~{3,})/);
        if (fence && !(fence[1].charAt(0) === "`" && raw[i].slice(lead.length + fence[1].length).indexOf("`") >= 0)) {
            const block = [raw[i].slice(lead.length)];
            let j = i + 1;
            while (j < raw.length && raw[j].replace(/^(?:\s*>)*\s*/, "").indexOf(fence[1]) !== 0)
                block.push(raw[j++]);
            if (j < raw.length)
                block.push(raw[j]);
            out.push(lead + keep(block.join("\n")));
            i = j;
            blank = true;
            continue;
        }
        // A list item, or a paragraph after a blank line, closes the items
        // deeper than where it starts.
        const item = line.match(ITEM_AT);
        if (item || blank) {
            while (items.length > 0 && items[items.length - 1] > indent)
                items.pop();
        }
        if (item && !isRule(line))
            items.push(indent + item[2].length + (item[3] ? (item[3].length > 4 ? 1 : item[3].length) : 1));
        out.push(line);
        blank = false;
    }
    let s = out.join("\n");
    s = s.replace(CODE_SPAN, (m, pre, ticks, code) => pre + keep(ticks + code + ticks));
    s = s.replace(/<!--[\s\S]*?(-->|$)/g, "");
    s = s.replace(/<pre\b[^>]*>([\s\S]*?)<\/pre\s*>/gi, (m, code) => "\n" + keep("```\n" + Logic.htmlText(code).replace(/^\n|\n$/g, "") + "\n```") + "\n");
    s = s.replace(/<picture\b[^>]*>([\s\S]*?)(<\/picture\s*>|$)/gi, (m, inner) => pictureImage(inner, !!dark));
    s = s.replace(/<img\b([^>]*)>/gi, (m, attrs) => {
        const src = attrOf(attrs, "src");
        const width = attrOf(attrs, "width").match(/^\s*(\d+)\s*(px)?\s*$/);
        return src ? "![" + (attrOf(attrs, "alt") || "image").replace(/[\[\]]/g, "") + "](" + src + (width ? " " + MARK + width[1] : "") + ")" : "";
    });
    // A link around an image alone is a linked image.
    s = s.replace(/<\/?(picture|source)\b[^>]*>/gi, "");
    s = s.replace(/<a\b([^>]*)>\s*(!\[[^\]]*\]\([^)]*\))\s*<\/a\s*>/gi, (m, attrs, image) => attrOf(attrs, "href") ? "[" + image + "](" + attrOf(attrs, "href") + ")" : image);
    s = s.replace(/<video\b([^>]*)>[\s\S]*?(<\/video\s*>|$)/gi, (m, attrs) => attrOf(attrs, "src") ? "\n\n" + attrOf(attrs, "src") + "\n\n" : "");
    s = s.replace(/<table\b[^>]*>([\s\S]*?)(<\/table\s*>|$)/gi, (m, inner) => tableMarkdown(inner));
    s = s.replace(/<br\s*\/?>/gi, BR);
    s = s.replace(/<summary\b[^>]*>([\s\S]*?)<\/summary\s*>/gi, (m, summary) => "\n" + MARK + "S" + summary.replace(new RegExp(BR, "g"), " ").replace(/\s+/g, " ").trim() + "\n");
    s = s.replace(/<details\b([^>]*)>/gi, (m, attrs) => "\n" + MARK + "D" + (/\bopen\b/i.test(attrs) ? "1" : "0") + "\n");
    s = s.replace(/<\/details\s*>/gi, "\n" + MARK + "E\n");
    s = s.replace(/<h([1-6])\b([^>]*)>([\s\S]*?)<\/h\1\s*>/gi, (m, level, attrs, inner) => {
        const align = alignMark(attrs);
        return "\n\n" + (align ? align + "\n" : "") + "#".repeat(Number(level)) + " " + inner.replace(/\s*\n\s*/g, " ").trim() + "\n" + (align ? MARK + "a\n" : "") + "\n";
    });
    // Paragraphs and divisions break lines; aligned ones (and <center>) mark
    // what they hold.
    const aligned = [];
    s = s.replace(/<(\/?)(p|div|center)\b([^>]*)>/gi, (m, close, tag, attrs) => {
        if (close)
            return aligned.pop() ? "\n" + MARK + "a\n" : "\n";
        const align = tag.toLowerCase() === "center" ? MARK + "Ac" : alignMark(attrs);
        aligned.push(align !== "");
        return align ? "\n" + align + "\n" : "\n";
    });
    s = listMarkdown(s);
    s = s.replace(/<hr\b[^>]*>/gi, "\n\n---\n\n");
    // A quote holds what it holds as Markdown's does, each line after ">"
    // (the code in it too, and a quote inside, done first).
    let before;
    do {
        before = s;
        s = s.replace(/<blockquote\b[^>]*>((?:(?!<blockquote\b)[\s\S])*?)(?:<\/blockquote\s*>|$)/i, (m, inner) => "\n\n" + keep(stash.restore(inner).trim().split("\n").map(line => "> " + line).join("\n")) + "\n\n");
    } while (s !== before);
    s = s.replace(/<\/?(thead|tbody|tfoot)\b[^>]*>/gi, "");
    s = s.replace(/\n{3,}/g, "\n\n").replace(/^\n+|\s+$/g, "");
    return {
        "text": s,
        "restore": stash.restore
    };
}

// --------------------------------------------------------------- blocks

function indentOf(line) {
    return line.match(/^ */)[0].length;
}

function dedent(line, n) {
    const indent = indentOf(line);
    return line.slice(Math.min(indent, n));
}

var LIST_ITEM = /^( {0,3})([-*+]|\d{1,9}[.)])(?:( +)(.*))?$/;

function isListLine(line) {
    return LIST_ITEM.test(line) && !isRule(line);
}

function isRule(line) {
    return /^ {0,3}([-*_])( *\1){2,} *$/.test(line);
}

// A code fence: its indent, its backticks or tildes, and its language.
var FENCE = /^( {0,3})(`{3,}|~{3,})\s*([^`\s]*)/;

function isFence(line) {
    return FENCE.test(line);
}

// A line holding nothing but images (each possibly wrapped in a link) shows
// them as pictures; an image inside prose stays a link.
var IMAGE = "(?:\\[\\s*)?!\\[([^\\]]*)\\]\\(\\s*<?([^)\\s>]+)>?([^)]*)\\)(?:\\s*\\]\\(([^)\\s]+)[^)]*\\))?";

var IMAGE_LINE = new RegExp("^\\s*(" + IMAGE + "\\s*)+$");

// The width an <img> gave its image, which cleanMarkdown writes after it.
var IMAGE_WIDTH = new RegExp(MARK + "(\\d+)");
var IMAGE_WIDTHS = new RegExp(MARK + "\\d+", "g");

function isImageLine(line) {
    return IMAGE_LINE.test(line);
}

function lineImages(line) {
    const found = [];
    const pattern = new RegExp(IMAGE, "g");
    let m;
    while ((m = pattern.exec(line)) !== null) {
        const width = m[3].match(IMAGE_WIDTH);
        found.push({
            "alt": m[1] || "image",
            "url": m[2],
            "href": m[4] || m[2],
            "width": width ? Number(width[1]) : 0
        });
    }
    return found;
}

function tableCells(line) {
    const cells = [];
    let cell = "";
    const text = line.trim().replace(/^\|/, "");
    for (let i = 0; i < text.length; i++) {
        if (text[i] === "\\" && text[i + 1] === "|") {
            cell += "|";
            i++;
        } else if (text[i] === "|") {
            cells.push(cell.trim());
            cell = "";
        } else {
            cell += text[i];
        }
    }
    if (cell.trim() !== "" || !/\|\s*$/.test(line))
        cells.push(cell.trim());
    return cells;
}

// A table's delimiter row: its columns' alignments, or null.
function tableAligns(line) {
    if (!/^ {0,3}\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(line) || line.indexOf("-") < 0)
        return null;
    return tableCells(line).map(cell => /^:-+:$/.test(cell) ? "center" : (/-:$/.test(cell) ? "right" : (/^:/.test(cell) ? "left" : "")));
}

function startsTable(lines, i) {
    if (i + 1 >= lines.length || lines[i].indexOf("|") < 0)
        return false;
    const aligns = tableAligns(lines[i + 1]);
    return !!aligns && aligns.length === tableCells(lines[i]).length;
}

// Whether a line ends the paragraph before it and begins a block.
function startsBlock(line) {
    const item = line.match(LIST_ITEM);
    return isFence(line) || /^ {0,3}(#{1,6}(\s|$)|>|\$\$)/.test(line) || isRule(line) || line.indexOf(MARK) === 0 || isImageLine(line) || Logic.VIDEO.test(line) || (!!item && !!item[4] && item[4].trim() !== "" && (!/\d/.test(item[2]) || /^1\D/.test(item[2] + " ")));
}

// GitHub's anchor for a heading: lowercase, punctuation dropped, spaces as
// dashes, and a number after one already taken.
function headingSlug(html, slugs) {
    const base = Logic.htmlText(html).toLowerCase().trim().replace(/[^\w\- \u00c0-\uffff]/g, "").replace(/ /g, "-");
    let slug = base;
    for (let n = 1; slugs.indexOf(slug) >= 0; n++)
        slug = base + "-" + n;
    slugs.push(slug);
    return slug;
}

// The alerts a quote can open with ([!NOTE]), each in github.com's colors
// (five kinds must read apart, which a theme's accents need not) and with
// its icon.
var ALERTS = {
    "note": {
        "icon": "info",
        "light": "#0969da",
        "dark": "#4493f8"
    },
    "tip": {
        "icon": "lightbulb",
        "light": "#1a7f37",
        "dark": "#3fb950"
    },
    "important": {
        "icon": "feedback",
        "light": "#8250df",
        "dark": "#ab7df8"
    },
    "warning": {
        "icon": "warning",
        "light": "#9a6700",
        "dark": "#d29922"
    },
    "caution": {
        "icon": "report",
        "light": "#d1242f",
        "dark": "#f85149"
    }
};

var ALERT_LINE = new RegExp("^\\[!(" + Object.keys(ALERTS).join("|") + ")\\]$", "i");

var ROMAN = [[1000, "m"], [900, "cm"], [500, "d"], [400, "cd"], [100, "c"], [90, "xc"], [50, "l"], [40, "xl"], [10, "x"], [9, "ix"], [5, "v"], [4, "iv"], [1, "i"]];

// A numbered item's marker as github.com's lists count: 1. at the top,
// i. in a list inside another, a. deeper.
function listMarker(n, depth) {
    if (depth === 1) {
        let out = "";
        for (const [value, letters] of ROMAN) {
            while (n >= value) {
                out += letters;
                n -= value;
            }
        }
        return out + ".";
    }
    if (depth >= 2) {
        let out = "";
        for (let k = n; k > 0; k = Math.floor((k - 1) / 26))
            out = String.fromCharCode(97 + (k - 1) % 26) + out;
        return out + ".";
    }
    return n + ".";
}

var BULLETS = ["disc", "circle", "square"];

// Bodies parse once for a text, a repository, and a style: the page builds
// a post's view again as its conversation changes, and every view of a body
// shares the answer. The last few are kept.
var PARSED = new Map();
var PARSED_KEPT = 64;

// The blocks of a body: { type, size, align?, anchors?, ... }, size being
// how much of the source the block shows at first (for cutting a long
// body), align "center" or "right" when HTML aligned it, and anchors the
// in-page links (#section, a footnote) that lead to it. Types:
//
//   heading { level, html }        paragraph { html }
//   quote { alert, blocks }        list { ordered, loose, items: [{ marker,
//   code { text, lines, lang }       task, blocks }] }
//   math { html }                  table { aligns, header, rows } (cells
//   images { images }                { html, images })
//   video { url }                  rule {}
//   details { id, open, html,      footnotes { items: [{ key, html }] }
//     blocks }
//
// A section (<details>) shows its summary and, once open, what it holds.
function parseMarkdown(text, repo, style) {
    const key = [repo || "", Object.keys(style).sort().map(name => name + "=" + String(style[name])).join(";"), String(text || "")].join("\u0000");
    let blocks = PARSED.get(key);
    if (blocks)
        PARSED.delete(key);
    else
        blocks = parseBody(String(text || ""), repo, style);
    PARSED.set(key, blocks);
    if (PARSED.size > PARSED_KEPT)
        PARSED.delete(PARSED.keys().next().value);
    return blocks;
}

function parseBody(text, repo, style) {
    const ctx = {
        "repo": repo || "",
        "style": style,
        "tags": inlineTags(style),
        "refs": {},
        "notes": {},
        "noteOrder": [],
        "anchors": [],
        "align": [],
        "slugs": [],
        "nextSection": 0,
        "lists": 0
    };
    // The markers cleaning and stashing write are no body's own. The
    // definitions come out while code is still set aside, so what looks
    // like one inside code stays code.
    const cleaned = cleanMarkdown(text.replace(/[\u0001-\u0005]/g, ""), style.dark);
    const lines = cleaned.restore(definitions(cleaned.text.split("\n"), ctx, cleaned.restore).join("\n")).split("\n");
    const blocks = parseBlocks(lines, ctx);
    if (ctx.noteOrder.length > 0) {
        ctx.align = [];
        const items = [];
        // A note may cite another, which then joins the list.
        for (let n = 0; n < ctx.noteOrder.length; n++) {
            const key = ctx.noteOrder[n];
            items.push({
                "key": key,
                "html": inlineHtml(ctx.notes[key], ctx) + " " + linkHtml("#fnref-" + key, "↩", style)
            });
        }
        ctx.anchors = ctx.noteOrder.map(key => "fn-" + key);
        addBlock(blocks, ctx, {
            "type": "footnotes",
            "items": items
        }, ctx.noteOrder.map(key => ctx.notes[key]).join("\n"));
    }
    return blocks;
}

// Takes out the link reference definitions ([label]: url) and footnotes
// ([^label]: text, with its indented lines) from lines whose code is set
// aside (cleanMarkdown), putting back what a note holds of it.
function definitions(lines, ctx, restore) {
    const out = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const note = line.match(/^ {0,3}\[\^([^\]\s]+)\]:\s*(.*)$/);
        if (note) {
            const body = [note[2]];
            while (i + 1 < lines.length && (/^\s{2,}\S/.test(lines[i + 1]) || (lines[i + 1].trim() !== "" && !startsBlock(lines[i + 1]) && !/^ {0,3}\[/.test(lines[i + 1]) && lines[i].trim() !== "") || (lines[i + 1].trim() === "" && i + 2 < lines.length && /^\s{4,}\S/.test(lines[i + 2]))))
                body.push(lines[++i].trim());
            ctx.notes[refKey(note[1])] = restore(body.join("\n").trim());
            continue;
        }
        const ref = line.match(/^ {0,3}\[([^\]^][^\]]*)\]:\s*<?([^\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*$/);
        if (ref) {
            const key = refKey(ref[1]);
            if (!(key in ctx.refs))
                ctx.refs[key] = restore(ref[2]);
            continue;
        }
        out.push(line);
    }
    return out;
}

function addBlock(blocks, ctx, block, source) {
    block.size = String(source).length;
    if (ctx.align.length > 0)
        block.align = ctx.align[ctx.align.length - 1];
    if (ctx.anchors.length > 0) {
        block.anchors = ctx.anchors;
        ctx.anchors = [];
    }
    blocks.push(block);
}

// Blocks held by another (a quote, a list item, a section), parsed with the
// alignment around them left as it was.
function nestedBlocks(lines, ctx) {
    const align = ctx.align.length;
    const blocks = parseBlocks(lines, ctx);
    ctx.align.length = align;
    return blocks;
}

// A section's lines: from after its D mark to the E that closes it
// (sections nest), or to the end of what holds it.
function sectionEnd(lines, from) {
    let depth = 0;
    for (let i = from; i < lines.length; i++) {
        const mark = lines[i].indexOf(MARK) === 0 ? lines[i].charAt(1) : "";
        if (mark === "D")
            depth++;
        else if (mark === "E" && depth-- === 0)
            return i;
    }
    return lines.length;
}

function parseBlocks(lines, ctx) {
    const blocks = [];
    const add = (block, source) => addBlock(blocks, ctx, block, source);
    const inline = text => inlineHtml(text, ctx);
    const heading = (level, text, source) => {
        const html = inline(text);
        ctx.anchors.push(headingSlug(html, ctx.slugs));
        add({
            "type": "heading",
            "level": level,
            "html": html
        }, source);
    };
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        let m;
        if (line.trim() === "") {
            i++;
            continue;
        }
        if (line.indexOf(MARK) === 0) {
            const kind = line.charAt(1);
            i++;
            if (kind === "D") {
                const end = sectionEnd(lines, i);
                let body = lines.slice(i, end);
                i = end + 1;
                // The summary comes right after the tag, or not at all.
                let summary = "Details";
                const first = body.findIndex(entry => entry.trim() !== "");
                if (first >= 0 && body[first].indexOf(MARK + "S") === 0) {
                    summary = body[first].slice(2) || summary;
                    body = body.slice(first + 1);
                }
                const open = line.charAt(2) === "1";
                const section = {
                    "type": "details",
                    "id": ctx.nextSection++,
                    "open": open,
                    "html": inline(summary)
                };
                // What it holds is only read once it has what leads to
                // the summary.
                add(section, open ? summary + "\n" + body.join("\n") : summary);
                section.blocks = nestedBlocks(body, ctx);
            } else if (kind === "A") {
                ctx.align.push(line.charAt(2) === "r" ? "right" : "center");
            } else if (kind === "a") {
                ctx.align.pop();
            }
            // A summary outside a section is just its text.
            else if (kind === "S") {
                add({
                    "type": "paragraph",
                    "html": inline(line.slice(2))
                }, line);
            }
            continue;
        }
        if (indentOf(line) >= 4) {
            const body = [];
            while (i < lines.length && (indentOf(lines[i]) >= 4 || lines[i].trim() === ""))
                body.push(dedent(lines[i++], 4));
            while (body.length > 0 && body[body.length - 1].trim() === "")
                body.pop();
            add({
                "type": "code",
                "text": body.join("\n"),
                "lines": body.length,
                "lang": ""
            }, body.join("\n"));
            continue;
        }
        if ((m = line.match(FENCE))) {
            const indent = m[1].length;
            const fence = m[2];
            const lang = m[3].toLowerCase();
            const body = [];
            i++;
            while (i < lines.length && !(indentOf(lines[i]) < 4 && lines[i].trim().indexOf(fence) === 0 && /^[`~]+$/.test(lines[i].trim())))
                body.push(dedent(lines[i++], indent));
            i++;
            const code = body.join("\n");
            if (lang === "math")
                add({
                    "type": "math",
                    "html": texHtml(code)
                }, code);
            else
                add({
                    "type": "code",
                    "text": code,
                    "lines": body.length,
                    "lang": lang
                }, code);
            continue;
        }
        if (/^ {0,3}\$\$/.test(line)) {
            const first = line.trim().slice(2);
            const body = [];
            i++;
            if (/\$\$$/.test(first)) {
                body.push(first.slice(0, -2));
            } else {
                body.push(first);
                while (i < lines.length && !/\$\$\s*$/.test(lines[i]))
                    body.push(lines[i++]);
                if (i < lines.length)
                    body.push(lines[i++].replace(/\$\$\s*$/, ""));
            }
            const tex = body.join("\n").trim();
            add({
                "type": "math",
                "html": texHtml(tex)
            }, tex);
            continue;
        }
        if ((m = line.match(/^ {0,3}(#{1,6})(?:\s+(.*?))?(?:\s+#+)?\s*$/))) {
            heading(m[1].length, m[2] || "", line);
            i++;
            continue;
        }
        if (isRule(line)) {
            add({
                "type": "rule"
            }, line);
            i++;
            continue;
        }
        if (/^ {0,3}>/.test(line)) {
            const body = [];
            let lazy = false;
            while (i < lines.length) {
                const l = lines[i];
                if (/^ {0,3}>/.test(l)) {
                    const inner = l.replace(/^ {0,3}> ?/, "");
                    body.push(inner);
                    lazy = inner.trim() !== "" && !isFence(inner);
                    i++;
                } else if (lazy && l.trim() !== "" && !startsBlock(l)) {
                    body.push(l);
                    i++;
                } else {
                    break;
                }
            }
            const alert = body.length > 0 ? body[0].trim().match(ALERT_LINE) : null;
            if (alert)
                body.shift();
            add({
                "type": "quote",
                "alert": alert ? alert[1].toLowerCase() : "",
                "blocks": nestedBlocks(body, ctx)
            }, body.join("\n"));
            continue;
        }
        if (startsTable(lines, i)) {
            const aligns = tableAligns(lines[i + 1]);
            const cell = text => isImageLine(text) && text.trim() !== "" ? {
                "html": "",
                "images": lineImages(text)
            } : {
                "html": inline(text.replace(IMAGE_WIDTHS, "")),
                "images": []
            };
            const row = l => {
                const cells = tableCells(l);
                return aligns.map((a, c) => cell(cells[c] || ""));
            };
            const source = [line];
            const header = row(line);
            const rows = [];
            i += 2;
            while (i < lines.length && lines[i].trim() !== "" && !startsBlock(lines[i])) {
                source.push(lines[i]);
                rows.push(row(lines[i++]));
            }
            add({
                "type": "table",
                "aligns": aligns,
                "header": header,
                "rows": rows
            }, source.join("\n"));
            continue;
        }
        if (isListLine(line)) {
            const first = line.match(LIST_ITEM);
            const ordered = /\d/.test(first[2]);
            const start = ordered ? parseInt(first[2], 10) : 1;
            const items = [];
            const source = [];
            let loose = false;
            let gap = false;
            while (i < lines.length) {
                const im = lines[i].match(LIST_ITEM);
                if (!im || isRule(lines[i]) || /\d/.test(im[2]) !== ordered)
                    break;
                if (gap)
                    loose = true;
                // Where the item's text begins: after the marker and its
                // space, or one space in when more follow (indented code).
                const spaces = im[3] ? im[3].length : 1;
                const width = im[1].length + im[2].length + (spaces > 4 ? 1 : spaces);
                const body = [im[4] !== undefined ? (spaces > 4 ? im[3].slice(1) : "") + im[4] : ""];
                source.push(lines[i]);
                i++;
                let blank = false;
                gap = false;
                while (i < lines.length) {
                    const l = lines[i];
                    if (l.trim() === "") {
                        blank = true;
                        body.push("");
                        i++;
                        continue;
                    }
                    if (indentOf(l) >= width) {
                        if (blank)
                            loose = loose || body.slice(0, -1).some(entry => entry.trim() !== "");
                        blank = false;
                        body.push(dedent(l, width));
                        source.push(l);
                        i++;
                        continue;
                    }
                    // A lazy line carries the paragraph on.
                    if (!blank && !isListLine(l) && !startsBlock(l) && body[body.length - 1].trim() !== "" && !isFence(body[body.length - 1])) {
                        body.push(l.trim());
                        source.push(l);
                        i++;
                        continue;
                    }
                    break;
                }
                while (body.length > 0 && body[body.length - 1].trim() === "")
                    body.pop();
                gap = blank;
                let task = "";
                const tm = body[0].match(/^\[([ xX])\](?:\s+|$)(.*)$/);
                if (tm) {
                    task = tm[1] === " " ? "open" : "done";
                    body[0] = tm[2];
                }
                items.push({
                    "marker": ordered ? listMarker(start + items.length, ctx.lists) : BULLETS[Math.min(ctx.lists, 2)],
                    "task": task,
                    "lines": body
                });
                if (i < lines.length && lines[i].trim() !== "" && !isListLine(lines[i]))
                    break;
            }
            ctx.lists++;
            for (const item of items) {
                item.blocks = nestedBlocks(item.lines, ctx);
                delete item.lines;
            }
            ctx.lists--;
            add({
                "type": "list",
                "ordered": ordered,
                "loose": loose,
                "items": items
            }, source.join("\n"));
            continue;
        }
        if (isImageLine(line)) {
            add({
                "type": "images",
                "images": lineImages(line)
            }, line);
            i++;
            continue;
        }
        if ((m = line.match(Logic.VIDEO))) {
            add({
                "type": "video",
                "url": m[1]
            }, line);
            i++;
            continue;
        }
        const body = [line.trim()];
        i++;
        let level = 0;
        while (i < lines.length && lines[i].trim() !== "") {
            if (/^ {0,3}=+\s*$/.test(lines[i]) || /^ {0,3}-+\s*$/.test(lines[i])) {
                level = lines[i].trim().charAt(0) === "=" ? 1 : 2;
                i++;
                break;
            }
            if (startsBlock(lines[i]) || startsTable(lines, i))
                break;
            body.push(lines[i++].trim());
        }
        if (level > 0)
            heading(level, body.join(" "), body.join("\n"));
        else
            add({
                "type": "paragraph",
                "html": inline(body.join("\n"))
            }, body.join("\n"));
    }
    return blocks;
}

// How many leading blocks fit a budget of source characters; at least one.
// A section closed at first costs its summary: what it holds shows only
// when the viewer opens it.
function blocksWithin(blocks, budget) {
    let used = 0;
    for (let i = 0; i < blocks.length; i++) {
        used += blocks[i].size || 0;
        if (used > budget)
            return Math.max(1, i);
    }
    return blocks.length;
}

// Where an in-page link leads: { index (of the body's block that holds
// its target), sections (the ids of the sections around the target,
// outermost first) }, or null when no block has that anchor.
function anchorPath(blocks, name) {
    const find = (list, sections) => {
        for (const block of list) {
            if ((block.anchors || []).indexOf(name) >= 0)
                return sections;
            const within = block.type === "details" ? sections.concat([block.id]) : sections;
            const inner = block.blocks ? [block.blocks] : (block.items || []).map(item => item.blocks || []);
            for (const held of inner) {
                const found = find(held, within);
                if (found)
                    return found;
            }
        }
        return null;
    };
    for (let i = 0; i < blocks.length; i++) {
        const sections = find([blocks[i]], []);
        if (sections)
            return {
                "index": i,
                "sections": sections
            };
    }
    return null;
}

// Column widths for a table: each column's natural width when they all fit,
// else the narrow ones keep theirs and the rest share what is left, none
// under a minimum.
function fitColumns(natural, available, minimum) {
    const total = natural.reduce((sum, w) => sum + w, 0);
    if (total <= available)
        return natural.map(w => Math.ceil(w));
    const widths = natural.map(() => 0);
    let left = available;
    let open = natural.map((w, i) => i);
    while (open.length > 0) {
        const share = left / open.length;
        const narrow = open.filter(i => natural[i] <= share);
        if (narrow.length === 0) {
            open.forEach(i => widths[i] = Math.floor(Math.max(minimum, share)));
            break;
        }
        narrow.forEach(i => {
            widths[i] = Math.ceil(natural[i]);
            left -= natural[i];
        });
        open = open.filter(i => natural[i] > share);
    }
    return widths;
}

// ----------------------------------------------------------------- code

// A diff block as github.com colors it: additions and removals on their
// tints, hunk headers in the accent, file headers bold. colors: { added,
// addedBackground, removed, removedBackground, hunk }. A suggestion's lines
// are all additions.
function diffHtml(text, colors, suggestion) {
    const line = (color, background, html) => "<span style=\"color:" + String(color) + "; background-color:" + String(background) + "\">" + html + "</span>";
    return "<div style=\"white-space:pre-wrap\">" + String(text).split("\n").map(row => {
        const html = escapeHtml(row) || " ";
        if (suggestion)
            return line(colors.added, colors.addedBackground, html);
        if (/^(diff |index |\+\+\+ |--- )/.test(row))
            return "<b>" + html + "</b>";
        if (row.charAt(0) === "+")
            return line(colors.added, colors.addedBackground, html);
        if (row.charAt(0) === "-")
            return line(colors.removed, colors.removedBackground, html);
        if (row.indexOf("@@") === 0)
            return Logic.tint(colors.hunk, html);
        return html;
    }).join("<br>") + "</div>";
}

// Fence languages KDE's syntax definitions know by neither the name nor
// the file extension ("x.<name>"), and the file that names theirs.
var CODE_FILES = {
    "python3": "x.py",
    "golang": "x.go",
    "shell": "x.sh",
    "console": "x.sh",
    "shellsession": "x.sh",
    "pwsh": "x.ps1",
    "ocaml": "x.ml",
    "docker": "Dockerfile",
    "containerfile": "Dockerfile",
    "make": "Makefile",
    "justfile": "justfile",
    "gitignore": ".gitignore",
    "systemd": "x.service",
    "nasm": "x.asm",
    "cuda": "x.cu",
    "batch": "x.bat",
    "fortran": "x.f90"
};

// What to look a fence's language up by (GitHubHighlighter.use): its
// definition's name, then the file it names; null for none (plain text, or
// a block drawn its own way).
function codeLookup(lang) {
    const name = String(lang || "").toLowerCase();
    if (name === "" || /^(text|txt|plain|plaintext|output|log|diff|patch|suggestion|mermaid|geojson|topojson|stl)$/.test(name))
        return null;
    return {
        "name": name,
        "file": Object.prototype.hasOwnProperty.call(CODE_FILES, name) ? CODE_FILES[name] : "x." + name
    };
}
