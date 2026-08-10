# Extract the exact raw blocks managed by codex-mini-hud.
# Variables: status_out, color_out, title_out

function bracket_delta(text, i, ch, delta, in_basic, in_literal, escaped) {
  if (index(text, "\"\"\"") || index(text, "\047\047\047")) {
    parse_error = 1
    return 0
  }
  delta = 0
  in_basic = 0
  in_literal = 0
  escaped = 0
  for (i = 1; i <= length(text); i++) {
    ch = substr(text, i, 1)
    if (in_basic) {
      if (escaped) escaped = 0
      else if (ch == "\\") escaped = 1
      else if (ch == "\"") in_basic = 0
    } else if (in_literal) {
      if (ch == "\047") in_literal = 0
    } else {
      if (ch == "#") break
      if (ch == "\"") in_basic = 1
      else if (ch == "\047") in_literal = 1
      else if (ch == "[") delta++
      else if (ch == "]") delta--
    }
  }
  return delta
}

BEGIN { in_tui = 0; capture = 0; depth = 0; other_depth = 0 }

{
  line = $0

  if (capture) {
    print line >> capture_out
    depth += bracket_delta(line)
    if (depth <= 0) capture = 0
    next
  }


  if (other_depth > 0) {
    other_depth += bracket_delta(line)
    next
  }

  if (line ~ /^[[:space:]]*\[/) {
    in_tui = (line ~ /^[[:space:]]*\[[[:space:]]*(tui|"tui"|\047tui\047)[[:space:]]*\][[:space:]]*(#.*)?$/)
    next
  }

  if (in_tui && line ~ /^[[:space:]]*status_line[[:space:]]*=/) {
    print line >> status_out
    capture_out = status_out
    depth = bracket_delta(line)
    if (depth > 0) capture = 1
    next
  }

  if (in_tui && line ~ /^[[:space:]]*status_line_use_colors[[:space:]]*=/) {
    print line >> color_out
    next
  }

  if (in_tui && line ~ /^[[:space:]]*terminal_title[[:space:]]*=/) {
    print line >> title_out
    capture_out = title_out
    depth = bracket_delta(line)
    if (depth > 0) capture = 1
    next
  }

  if (in_tui && line ~ /=/) {
    other_depth = bracket_delta(line)
  }
}

END {
  if (capture || other_depth > 0 || parse_error) {
    print "codex-mini-hud: cannot safely read the existing tui.status_line" > "/dev/stderr"
    exit 42
  }
}
