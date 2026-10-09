## SBEmacs mode ABI: borrowed UTF-8 buffers; one face per byte.
## No editor calls, retained pointers, or Nim objects cross the C boundary.

import std/strutils

type
  Token = object
    first, last: int
    word: string
    face: uint8
    closed: bool

const
  keywords = (
    "addr and as asm bind block break case cast concept const continue " &
    "converter defer discard distinct div do elif else end enum except " &
    "export finally for from func if import in include interface is isnot " &
    "iterator let macro method mixin mod nil not notin object of or out " &
    "proc ptr raise ref return shl shr static template try tuple type " &
    "using var when while xor yield true false"
  ).split()

  definers = [
    "proc", "func", "method", "iterator", "converter", "macro", "template"
  ]

proc word(c: char): bool =
  c.isAlphaNumeric or c == '_' or ord(c) >= 128

proc normalize(s: string): string =
  if s.len > 0:
    result = $s[0] & s[1..^1].replace("_", "").toLowerAscii

proc at(s, p: string; i: int): bool =
  i + p.len <= s.len and s.substr(i, i + p.len - 1) == p

proc lex(s: string): seq[Token] =
  var i = 0
  var expect = false

  while i < s.len:
    let start = i
    var face = 5'u8
    var closed = true

    if s[i] in {' ', '\t', '\r'}:
      inc i
      continue

    if s[i] == '\n':
      inc i
      expect = false

    elif at(s, "#[", i) or at(s, "##[", i):
      var stack: seq[string]
      stack.add(if at(s, "##[", i): "]##" else: "]#")
      i += (if at(s, "##[", i): 3 else: 2)

      while i < s.len and stack.len > 0:
        if at(s, "##[", i):
          stack.add("]##")
          i += 3
        elif at(s, "#[", i):
          stack.add("]#")
          i += 2
        elif at(s, stack[^1], i):
          i += stack.pop().len
        else:
          inc i

      face = 7
      closed = stack.len == 0

    elif s[i] == '#':
      while i < s.len and s[i] != '\n':
        inc i
      face = 7

    elif s[i] == '`':
      inc i
      while i < s.len and s[i] != '`':
        inc i
      if i < s.len:
        inc i
      if expect:
        face = 11
        expect = false

    elif s[i].isDigit:
      inc i
      while i < s.len and
          (word(s[i]) or s[i] == '\'' or
           (s[i] == '.' and not at(s, "..", i)) or
           (s[i] in {'+', '-'} and s[i - 1] in {'e', 'E'})):
        inc i
      face = 6

    else:
      var opening = i
      var raw = false

      if word(s[i]):
        inc i
        while i < s.len and word(s[i]):
          inc i
        if i < s.len and s[i] == '"':
          opening = i
          raw = true
        else:
          opening = -1

      if opening < 0:
        let name = normalize(s[start..<i])
        if expect:
          face = 11
          expect = false
        elif name in keywords:
          face = 4
          expect = name in definers

      elif s[opening] in {'"', '\''}:
        let delim =
          if at(s, "\"\"\"", opening): "\"\"\""
          else: $s[opening]

        i = opening + delim.len
        closed = false
        face = 9

        while i < s.len:
          if raw and delim.len == 1 and at(s, "\"\"", i):
            i += 2
          elif at(s, delim, i):
            i += delim.len
            closed = true
            break
          elif not raw and delim.len == 1 and s[i] == '\\':
            i = min(s.len, i + 2)
          elif delim.len == 1 and s[i] == '\n':
            break
          else:
            inc i

      else:
        inc i
        face = 1

    result.add Token(
      first: start,
      last: i,
      word: s[start..<i],
      face: face,
      closed: closed
    )

proc copyInput(p: ptr UncheckedArray[uint8]; n: int): string =
  result = newString(n)
  for i in 0..<n:
    result[i] = char(p[i])

proc column(s: string; pos: int): int =
  var start = pos
  while start > 0 and s[start - 1] != '\n':
    dec start

  while start < s.len and s[start] in {' ', '\t'}:
    if s[start] == '\t':
      result = (result div 8 + 1) * 8
    else:
      inc result
    inc start

proc indentation(s: string; line, width: int): int =
  let tokens = lex(s[0..<line])
  if tokens.len > 0 and not tokens[^1].closed:
    return -1

  var statements: seq[seq[Token]]
  var pending: seq[Token]
  var brackets: seq[Token]

  for t in tokens:
    if t.face == 7'u8:
      continue

    if t.word in ["(", "[", "{"]:
      brackets.add t
    elif t.word in [")", "]", "}"] and brackets.len > 0:
      discard brackets.pop()

    if t.word == "\n":
      if brackets.len == 0 and pending.len > 0:
        statements.add pending
        pending = @[]
    else:
      pending.add t

  if pending.len > 0:
    statements.add pending

  let current = lex(s[line..^1])
  let head = if current.len > 0: current[0].word else: ""

  if brackets.len > 0:
    let b = brackets[^1]
    let close =
      if b.word == "(": ")"
      elif b.word == "[": "]"
      else: "}"
    return column(s, b.first) + (if head == close: 0 else: width)

  if statements.len == 0:
    return 0

  let prev = statements[^1]
  let base = column(s, prev[0].first)
  var partners: seq[string]

  case head
  of "elif":
    partners = @["if", "when", "elif"]
  of "else":
    partners = @[
      "if", "when", "elif", "case", "of", "for", "while", "try", "except"
    ]
  of "of":
    partners = @["case", "of"]
  of "except", "finally":
    partners = @["try", "except"]
  else:
    discard

  var limit = base + width
  for i in countdown(statements.high, 0):
    let st = statements[i]
    let level = column(s, st[0].first)
    if level <= limit and st[0].word in partners:
      return level + (if st[0].word == "case": width else: 0)
    limit = min(limit, level)

  let first = prev[0].word
  let tail = prev[^1].word

  if tail in [":", "=", "object", "enum", "tuple"] or
      first in ["case", "type", "var", "let", "const"]:
    if first in ["let", "var", "const", "type"] and
        prev.len > 1 and tail notin ["=", "object", "enum", "tuple"]:
      return base
    return base + width

  if tail in ["+", "-", "*", "/", ",", "and", "or", "&"]:
    return base + width

  base

proc sbemacsNimAbi(): cint
    {.exportc: "sbemacs_nim_abi", dynlib, cdecl.} =
  1

proc sbemacsNimHighlight(
    text: ptr UncheckedArray[uint8];
    n: csize_t;
    colors: ptr UncheckedArray[uint8]
): cint {.exportc: "sbemacs_nim_highlight", dynlib, cdecl.} =
  if n > csize_t(high(int)) or
      (n > 0 and (text == nil or colors == nil)):
    return -1

  try:
    let s = copyInput(text, int(n))
    for i in 0..<s.len:
      colors[i] = 5
    for t in lex(s):
      for i in t.first..<t.last:
        colors[i] = t.face
    return 0
  except:
    return -2

proc sbemacsNimIndent(
    text: ptr UncheckedArray[uint8];
    n, line: csize_t;
    width: cint
): cint {.exportc: "sbemacs_nim_indent", dynlib, cdecl.} =
  if n > csize_t(high(int)) or line > n or
      width <= 0 or width > 256 or (n > 0 and text == nil):
    return -2

  try:
    return cint(indentation(
      copyInput(text, int(n)), int(line), int(width)
    ))
  except:
    return -2
