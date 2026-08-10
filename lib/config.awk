# Safely replace the two codex-mini-hud-managed keys in [tui].
#
# Required variables:
#   action: install | restore
#   block_file: desired status_line block
#   color_file: desired status_line_use_colors block
#   title_file: desired terminal_title block

function emit_file(path, line) {
  if (path == "") return
  while ((getline line < path) > 0) print line
  close(path)
}

function emit_managed() {
  if (emitted || invalid) return
  emit_file(block_file)
  emit_file(color_file)
  emit_file(title_file)
  emitted = 1
}

function bracket_delta(text, i, ch, delta, in_basic, in_literal, escaped) {
  # Managed values are arrays of ordinary TOML strings. Count structural
  # brackets while ignoring quoted text and comments. Conservatively refuse
  # multiline TOML strings instead of attempting to partially parse them.
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

BEGIN {
  in_tui = 0
  skipping = 0
  other_depth = 0
  status_count = 0
  color_count = 0
  title_count = 0
  tui_count = 0
  emitted = 0
  invalid = 0
}

{
  line = $0

  if (index(line, "\"\"\"") || index(line, "\047\047\047")) {
    print "codex-mini-hud: multiline TOML strings are not safely editable" > "/dev/stderr"
    invalid = 1
    next
  }

  if (line ~ /^[[:space:]]*(tui|"tui"|\047tui\047)[[:space:]]*\.[[:space:]]*(status_line|status_line_use_colors|terminal_title|"status_line"|\047status_line\047|"status_line_use_colors"|\047status_line_use_colors\047|"terminal_title"|\047terminal_title\047)[[:space:]]*=/) {
    print "codex-mini-hud: dotted tui status keys are not safely editable" > "/dev/stderr"
    invalid = 1
    next
  }

  if (line ~ /^[[:space:]]*(tui|"tui"|\047tui\047)[[:space:]]*=[[:space:]]*\{/) {
    print "codex-mini-hud: inline root tui tables are not safely editable" > "/dev/stderr"
    invalid = 1
    next
  }

  if (skipping) {
    depth += bracket_delta(line)
    if (depth <= 0) skipping = 0
    next
  }

  if (other_depth > 0) {
    other_depth += bracket_delta(line)
    print line
    next
  }

  if (line ~ /^[[:space:]]*\[/) {
    if (in_tui) emit_managed()
    in_tui = (line ~ /^[[:space:]]*\[[[:space:]]*(tui|"tui"|\047tui\047)[[:space:]]*\][[:space:]]*(#.*)?$/)
    if (in_tui) {
      tui_count++
      if (tui_count > 1) {
        print "codex-mini-hud: duplicate [tui] tables are not safely editable" > "/dev/stderr"
        invalid = 1
      }
    }
    print line
    next
  }

  if (in_tui && line ~ /^[[:space:]]*status_line[[:space:]]*=/) {
    status_count++
    if (status_count > 1) {
      print "codex-mini-hud: duplicate tui.status_line keys are not safely editable" > "/dev/stderr"
      invalid = 1
    }
    depth = bracket_delta(line)
    if (depth > 0) skipping = 1
    next
  }

  if (in_tui && line ~ /^[[:space:]]*status_line_use_colors[[:space:]]*=/) {
    color_count++
    if (color_count > 1) {
      print "codex-mini-hud: duplicate tui.status_line_use_colors keys are not safely editable" > "/dev/stderr"
      invalid = 1
    }
    next
  }

  if (in_tui && line ~ /^[[:space:]]*terminal_title[[:space:]]*=/) {
    title_count++
    if (title_count > 1) {
      print "codex-mini-hud: duplicate tui.terminal_title keys are not safely editable" > "/dev/stderr"
      invalid = 1
    }
    depth = bracket_delta(line)
    if (depth > 0) skipping = 1
    next
  }


  if (in_tui && line ~ /^[[:space:]]*("status_line"|\047status_line\047|"status_line_use_colors"|\047status_line_use_colors\047|"terminal_title"|\047terminal_title\047)[[:space:]]*=/) {
    print "codex-mini-hud: quoted managed keys are not safely editable" > "/dev/stderr"
    invalid = 1
    next
  }

  if (in_tui && line ~ /=/) {
    other_depth = bracket_delta(line)
    print line
    next
  }

  print line
}

END {
  if (parse_error) {
    print "codex-mini-hud: multiline strings in tui.status_line are not safely editable" > "/dev/stderr"
    invalid = 1
  }
  if (skipping) {
    print "codex-mini-hud: unterminated tui.status_line array" > "/dev/stderr"
    invalid = 1
  }
  if (!invalid) {
    if (in_tui) {
      emit_managed()
    } else if (tui_count == 0 && action == "install") {
      if (NR > 0) print ""
      print "[tui]"
      emit_managed()
    }
  }
  if (invalid) exit 42
}
