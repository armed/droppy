#!/usr/bin/env python3
"""Builds the reference half of Droppy's config template from Ghostty's pinned docs and source.

usage: generate-config-template.py <ghostty.5.md> <Config.zig> <output>
"""
import re
import sys
import textwrap

docs_path, source_path, out_path = sys.argv[1:4]

# Droppy embeds libghostty with its own window, tab bar and platform layer, so options that only
# Ghostty's own app layers read have no effect. Each group is a reason shown in the template.
EXCLUDED = [
    ("belong to Ghostty's own windows and macOS app layer", lambda k: k.startswith("window-") and k not in {
        "window-padding-x", "window-padding-y", "window-padding-balance", "window-padding-color"}
        or k.startswith("macos-") and k != "macos-option-as-alt"
        or k in {"maximize", "fullscreen", "initial-window", "quit-after-last-window-closed",
                 "quit-after-last-window-closed-delay", "undo-timeout", "tab-inherit-working-directory",
                 "split-inherit-working-directory", "drag-handle", "focus-follows-mouse", "background-blur",
                 "auto-update", "auto-update-channel", "title-report-ignore"}),
    ("belong to the quick terminal", lambda k: k.startswith("quick-terminal-")),
    ("are GTK or Linux only", lambda k: k.startswith(("gtk-", "linux-", "x11-", "adw-"))
        or k in {"language", "class", "async-backend", "freetype-load-flags"}),
    ("need Ghostty's own user interface (link previews, notifications, bell, scrollbar, overlays, palette)",
        lambda k: k in {"link-previews", "scrollbar", "resize-overlay",
                        "resize-overlay-position", "resize-overlay-duration", "command-palette-entry",
                        "app-notifications", "desktop-notifications", "notify-on-command-finish",
                        "notify-on-command-finish-action", "notify-on-command-finish-after", "bell-features",
                        "bell-audio-path", "bell-audio-volume", "progress-style",
                        "split-preserve-zoom"}),
    ("would read other files, and Droppy's file is the only configuration source",
        lambda k: k in {"config-file", "config-default-files"}),
]

EXAMPLES = {
    "keybind": "keybind = ctrl+shift+t=new_tab",
    "palette": "palette = 0=#1d1f21",
    "font-family": "font-family = JetBrains Mono",
    "font-family-bold": "font-family-bold = JetBrains Mono",
    "font-family-italic": "font-family-italic = JetBrains Mono",
    "font-family-bold-italic": "font-family-bold-italic = JetBrains Mono",
    "env": "env = EDITOR=vim",
    "font-feature": "font-feature = -calt",
    "font-variation": "font-variation = wght=500",
    "custom-shader": "custom-shader = shaders/crt.glsl",
    "key-remap": "key-remap = ctrl=super",
    "theme": "theme = Kanagawa Wave",
}


def exclusion(key):
    for reason, test in EXCLUDED:
        if test(key):
            return reason
    return None


def clean(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = text.replace("`", "")
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"(?<![A-Za-z0-9_])_([^_]+)_(?![A-Za-z0-9_])", r"\1", text)
    return text


def parse_docs(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    start = lines.index("# CONFIGURATION OPTIONS")
    entries, key, body = [], None, []
    for line in lines[start + 1:]:
        if re.match(r"^# [A-Z]", line):
            break
        match = re.match(r"^\*\*`([^`]+)`\*\*$", line)
        if match:
            if key:
                entries.append((key, body))
            key, body = match.group(1), []
        elif key:
            body.append(line)
    if key:
        entries.append((key, body))
    result, previous = [], ("", "")
    for key, body in entries:
        # Keys documented together appear as consecutive headings with the text under the first.
        text = first_paragraph(body)
        if text:
            previous = (key, text)
            result.append((key, text))
        else:
            result.append((key, f"Companion of {previous[0]}, with the same meaning for its own style or role."))
    return result


def first_paragraph(body):
    paragraph = []
    for line in body:
        text = re.sub(r"^(:   |    )", "", line)
        if not text.strip():
            if paragraph:
                break
            continue
        paragraph.append(text.strip())
    return clean(" ".join(paragraph))


def parse_defaults(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    defaults = {}
    for index, line in enumerate(lines):
        match = re.match(r'^(?:@"([a-z0-9-]+)"|([a-z0-9_]+)): ([^=]+?) = (.+?),\s*$', line)
        if match:
            key = (match.group(1) or match.group(2)).replace("_", "-")
            value = simple_value(match.group(4))
            if value is not None:
                defaults[key] = value
            continue
        match = re.match(r'^(?:@"([a-z0-9-]+)"|([a-z0-9_]+)): ([^=]+?) = switch \(builtin\.target\.os\.tag\) \{', line)
        if match:
            key = (match.group(1) or match.group(2)).replace("_", "-")
            for follow in lines[index + 1:index + 12]:
                mac = re.match(r"^\s*\.macos => (.+?),\s*$", follow)
                if mac and simple_value(mac.group(1)) is not None:
                    defaults[key] = simple_value(mac.group(1))
                    break
                if follow.startswith("}"):
                    break
    return defaults


def simple_value(raw):
    raw = raw.strip()
    if raw in {"true", "false"}:
        return raw
    if re.fullmatch(r"-?[0-9][0-9_]*(\.[0-9]+)?", raw):
        return raw.replace("_", "")
    enum = re.fullmatch(r'\.(?:@"([a-z0-9-]+)"|([a-z][a-z0-9_]*))', raw)
    if enum and (enum.group(1) or enum.group(2)) not in {"default", "empty", "none_set"}:
        return enum.group(1) or enum.group(2)
    string = re.fullmatch(r'"([^"\\]+)"', raw)
    if string:
        return string.group(1)
    return None


def comment(text, width=78):
    return "\n".join(textwrap.wrap(text, width=width, initial_indent="# ", subsequent_indent="# ",
                                   break_long_words=False, break_on_hyphens=False))


entries = parse_docs(docs_path)
defaults = parse_defaults(source_path)

included, excluded = [], {}
for key, text in entries:
    reason = exclusion(key)
    if reason:
        excluded.setdefault(reason, []).append(key)
    else:
        included.append((key, text))

out = [
    "# ---- Ghostty options ----",
    "# Every key below is passed to Ghostty's terminal core. A line shows the default where Ghostty's source",
    "# has a simple one, an example for repeatable keys (keybind, palette, font-family, ...) that can be given",
    "# several times, and otherwise just the key. Cmd+J and Cmd+K (panel height) stay Droppy's whatever",
    "# keybind says.",
    "",
]
real = 0
for key, text in included:
    out.append(comment(text or key))
    if key in EXAMPLES:
        out.append("# " + EXAMPLES[key])
    elif key in defaults:
        real += 1
        out.append(f"# {key} = {defaults[key]}")
    else:
        out.append(f"# {key} =")
    out.append("")

out.append("# ---- Options without effect in Droppy ----")
out.append("# These are still accepted, so a config shared with Ghostty keeps working, but Droppy ignores them.")
for reason, keys in excluded.items():
    out.append("#")
    out.append(comment(f"These {reason}: " + ", ".join(keys)))
out.append("")

open(out_path, "w", encoding="utf-8").write("\n".join(out))
total_excluded = sum(len(v) for v in excluded.values())
print(f"template: {len(included)} included ({real} real defaults), {total_excluded} excluded, {len(entries)} total",
      file=sys.stderr)
