
    NF != 5 || $4 !~ /^[0-9]+([.][0-9]+)?$/ || $5 !~ /^[0-9]+([.][0-9]+)?$/ { printf "MISSING %s %s: no time in the record\n", fx, $2; bad=1; next }
    { kind = $1; name = $2; s = $4 + 0; l = $5 + 0
      us = l * 1000 / big
      if (kind == "local" || kind == "scan") {
        ok = (l <= 2 * s + 20) || (kind == "scan" && us <= 0.5)
        verdict = sprintf("%8.1f %9.1f ms  x%.1f", s, l, (s > 0 ? l / s : 0))
        if (kind == "scan") verdict = verdict sprintf(", %.3f us/byte", us) }
      else { ok = (us <= 0.5); verdict = sprintf("%8.1f %9.1f ms  %.3f us/byte", s, l, us) }
      printf "%s %-8s %-6s %-32s %s\n", (ok ? "ok  " : "SLOW"), fx, kind, name, verdict }
    END { if (bad) exit 1 }
