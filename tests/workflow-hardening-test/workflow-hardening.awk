# Reports GitHub Actions workflow hardening violations.
#
# Usage:  awk -f workflow-hardening.awk WORKFLOW-FILE
#
# Writes one line per violation, "LINE<tab>MESSAGE", sorted by line number,
# and writes nothing for a workflow that violates nothing.  The exit status is
# 0 either way; the caller counts the lines.
#
# This knows only as much YAML as the checks need:  indentation delimits jobs,
# a `- ` list item begins a step, and a `run:` key introduces either a one-line
# command or a more-indented block of them.  Parsing that much is what makes
# the checks per-step and per-job rather than per-file, which matters because a
# file-wide `grep` for a hardened construct is satisfied by one hardened
# occurrence no matter how many unhardened ones accompany it.

BEGIN {
  # A command that fetches a file.  The character before it may not be part of
  # a word, so that `sha256sum` is not `sh` and `--curl-args` is not `curl`.
  DOWNLOAD = "(^|[^[:alnum:]_-])(curl|wget)([[:space:]]|$)"

  # An invocation of a shell interpreter, optionally under `sudo` with
  # options.  `./script.sh` is deliberately not an invocation of one:  a script
  # in the repository was reviewed, unlike one that was just downloaded.
  SUDO = "(sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)?"
  SHELL_CMD = "(^|[|&;(){}/[:space:]])" SUDO "(ba|da|k|z)?sh([[:space:]]|$)"

  # A download piped into a shell.  The `.*` between the two permits any
  # number of intervening pipeline stages, as in `curl URL | tr -d '\r' | sh`.
  PIPE_TO_SHELL = "(^|[^[:alnum:]_-])(curl|wget).*\\|[[:space:]]*" SUDO \
    "(ba|da|k|z)?sh([[:space:]]|$)"

  # A URL that names a branch, which is a moving target, rather than a tag or
  # a commit SHA.
  MUTABLE_URL = "https?://[^[:space:]\"'`]*/(main|master|HEAD)/"

  # Refs that a third-party action must not be pinned to, for the same reason.
  MUTABLE_REF = "@(main|master|develop|latest|HEAD)$"
}

{ text[NR] = $0 }

END {
  nlines = NR
  prepare()
  find_jobs()
  find_steps()
  find_run_blocks()

  check_parsed()
  check_fetch_and_run()
  check_mutable_urls()
  check_action_refs()
  check_permissions()
  check_checkout()

  report()
}

# Fills in, for each line:  `code`, the line without its comment; `ind`, its
# indentation, or -1 if it has no content; `logical`, the line joined with the
# backslash-continuation lines that follow it; and `continuation`, whether the
# line was consumed by a previous line's `logical`.
#
# Comments are removed because a check that fires on a comment fires on a
# workflow that merely documents the construct it forbids -- including on the
# comment that explains why the construct is forbidden.  A `#` that begins a
# comment is at the start of a line or is preceded by whitespace, in YAML and
# in the shell alike.
function prepare(   i, j, s, t) {
  for (i = 1; i <= nlines; i++) {
    s = text[i]
    sub(/(^|[ \t])#.*$/, "", s)
    code[i] = s
    if (s ~ /^[ \t]*$/) {
      ind[i] = -1
    } else {
      match(s, /^[ \t]*/)
      ind[i] = RLENGTH
    }
  }
  for (i = 1; i <= nlines; i++) {
    if (continuation[i]) {
      continue
    }
    s = code[i]
    j = i
    while (s ~ /\\[ \t]*$/ && j < nlines) {
      sub(/\\[ \t]*$/, " ", s)
      j++
      continuation[j] = 1
      t = code[j]
      sub(/^[ \t]+/, "", t)
      s = s t
    }
    logical[i] = s
  }
}

# Fills in the job count `njobs` and, for each job, its first line `jstart`,
# its last line `jend`, the indentation of its contents `jbody`, and its name
# `jname`.
function find_jobs(   i, jobsline, keyind, name) {
  njobs = 0
  jobsline = 0
  for (i = 1; i <= nlines; i++) {
    if (ind[i] == 0 && code[i] ~ /^jobs:[ \t]*$/) {
      jobsline = i
      break
    }
  }
  if (jobsline == 0) {
    return
  }
  keyind = -1
  for (i = jobsline + 1; i <= nlines; i++) {
    if (ind[i] < 0) {
      continue
    }
    if (keyind < 0) {
      keyind = ind[i]
    }
    if (ind[i] < keyind) {
      break
    }
    if (ind[i] == keyind && code[i] ~ /^[ \t]*[^ \t]+:[ \t]*$/) {
      if (njobs > 0) {
        jend[njobs] = i - 1
      }
      njobs++
      name = code[i]
      sub(/^[ \t]+/, "", name)
      sub(/:.*$/, "", name)
      jstart[njobs] = i
      jname[njobs] = name
      jbody[njobs] = -1
    } else if (njobs > 0 && jbody[njobs] < 0) {
      jbody[njobs] = ind[i]
    }
  }
  if (njobs > 0) {
    jend[njobs] = (i > nlines) ? nlines : i - 1
  }
}

# Fills in the step count `nsteps` and, for each step, its first line `sstart`
# and its last line `send`.  A step is a `- ` list item; it ends at the next
# line that is no more indented than the item's dash, which is the next step or
# the end of the list.  Lists that are not lists of steps are included, which
# is harmless:  no check fires on one.
function find_steps(   i, j) {
  nsteps = 0
  for (i = 1; i <= nlines; i++) {
    if (ind[i] < 0 || code[i] !~ /^[ \t]*-([ \t]|$)/) {
      continue
    }
    nsteps++
    sstart[nsteps] = i
    send[nsteps] = nlines
    for (j = i + 1; j <= nlines; j++) {
      if (ind[j] >= 0 && ind[j] <= ind[i]) {
        send[nsteps] = j - 1
        break
      }
    }
  }
}

# Fills in the run-block count `nblocks` and, for each block, its first line
# `bstart` and its last line `bend`.  `run: COMMAND` is a one-line block;
# `run: |` and `run: >` are blocks of every following more-indented line.
function find_run_blocks(   i, j, rest) {
  nblocks = 0
  for (i = 1; i <= nlines; i++) {
    if (ind[i] < 0 || code[i] !~ /(^|[ \t])run:/) {
      continue
    }
    match(code[i], /(^|[ \t])run:[ \t]*/)
    rest = substr(code[i], RSTART + RLENGTH)
    nblocks++
    bstart[nblocks] = i
    bend[nblocks] = i
    if (rest ~ /^[|>][0-9+-]*[ \t]*$/) {
      for (j = i + 1; j <= nlines; j++) {
        if (ind[j] >= 0 && ind[j] <= ind[i]) {
          break
        }
        bend[nblocks] = j
      }
    }
  }
}

# Returns the index of the job that contains LINE, or 0 if no job does.
function job_of(line,   j) {
  for (j = 1; j <= njobs; j++) {
    if (jstart[j] <= line && line <= jend[j]) {
      return j
    }
  }
  return 0
}

# A per-job check examines no job in a file whose jobs this did not find, and
# so reports nothing -- which is also what it reports for a hardened file.
# Rather than pass vacuously, say that the file was not understood.
function check_parsed() {
  if (njobs == 0) {
    add(1, "has no `jobs:` block, so the per-job checks examined nothing")
  }
}

# Code that is downloaded and then run is whatever it says at the moment of the
# download, not what was reviewed; under `sudo` it is that, as root.  Pinning
# the download would not make it reviewable, so the check is not for a pinned
# download but for no download-and-run at all.
#
# The two halves need not be in one pipeline or even in one step:  the steps of
# a job share a workspace, so a step can run what an earlier step downloaded.
# Hence the second check is per job.
function check_fetch_and_run(   b, i, j, line, downline, shellline) {
  for (b = 1; b <= nblocks; b++) {
    for (i = bstart[b]; i <= bend[b]; i++) {
      if (continuation[i]) {
        continue
      }
      if (logical[i] ~ PIPE_TO_SHELL) {
        add(i, "pipes a downloaded file into a shell")
        piped[i] = 1
      }
    }
  }
  for (b = 1; b <= nblocks; b++) {
    for (i = bstart[b]; i <= bend[b]; i++) {
      if (continuation[i] || piped[i]) {
        continue
      }
      j = job_of(bstart[b])
      line = logical[i]
      if (line ~ DOWNLOAD && !(j in downline)) {
        downline[j] = i
      }
      if (line ~ SHELL_CMD && !(j in shellline)) {
        shellline[j] = i
      }
    }
  }
  for (j in shellline) {
    if (j in downline) {
      add(shellline[j], "runs a shell in a job that downloads a file (line " \
        downline[j] ")")
    }
  }
}

function check_mutable_urls(   i) {
  for (i = 1; i <= nlines; i++) {
    if (code[i] ~ MUTABLE_URL) {
      add(i, "downloads from a mutable branch rather than a pinned ref")
    }
  }
}

# A third-party action is code, so `uses: owner/action@main` has the same
# problem as a URL that names a branch:  what runs is whatever the branch says
# when the workflow runs.
function check_action_refs(   i, v) {
  for (i = 1; i <= nlines; i++) {
    if (code[i] !~ /(^|[ \t])uses:/) {
      continue
    }
    match(code[i], /(^|[ \t])uses:[ \t]*/)
    v = substr(code[i], RSTART + RLENGTH)
    sub(/[ \t].*$/, "", v)
    gsub(/["']/, "", v)
    if (v == "" || v ~ /^\.\// || v ~ /^docker:\/\//) {
      continue
    }
    if (v !~ /@/) {
      add(i, "uses an action that names no version:  " v)
    } else if (v ~ MUTABLE_REF) {
      add(i, "uses an action pinned to a mutable branch:  " v)
    }
  }
}

# Without a `permissions:` block a job gets the repository's default token
# permissions, which may be read-write.  A top-level block covers every job; a
# job-level one covers only its own job, so every job needs its own.  This
# checks only that a block is present, not what is in it, so that it does not
# object to a job that legitimately needs to write.
function check_permissions(   i, j, found) {
  for (i = 1; i <= nlines; i++) {
    if (ind[i] == 0 && code[i] ~ /^permissions:/) {
      return
    }
  }
  for (j = 1; j <= njobs; j++) {
    found = 0
    for (i = jstart[j]; i <= jend[j]; i++) {
      if (ind[i] == jbody[j] && code[i] ~ /^[ \t]*permissions:/) {
        found = 1
      }
    }
    if (!found) {
      add(jstart[j], "job \"" jname[j] "\" does not declare permissions")
    }
  }
}

# `actions/checkout` leaves the token in `.git/config` unless
# `persist-credentials: false`, so any later step -- including one from a
# third-party action -- can read it and push with it.  A full-history checkout
# is both slow and more than these workflows use; `fetch-depth: 1` says so
# explicitly rather than by default.
#
# Each checkout step is checked separately:  hardening one of them does not
# harden another.
function check_checkout(   s, i, persist, depth) {
  for (s = 1; s <= nsteps; s++) {
    persist = 0
    depth = 0
    for (i = sstart[s]; i <= send[s]; i++) {
      if (code[i] ~ /persist-credentials:[ \t]*false/) {
        persist = 1
      }
      if (code[i] ~ /fetch-depth:[ \t]*[0-9]/) {
        depth = 1
      }
    }
    for (i = sstart[s]; i <= send[s]; i++) {
      if (code[i] !~ /uses:[ \t]*actions\/checkout@/) {
        continue
      }
      if (!persist) {
        add(i, "checks out without persist-credentials: false")
      }
      if (!depth) {
        add(i, "checks out without fetch-depth")
      }
    }
  }
}

function add(line, message) {
  nviolations++
  vline[nviolations] = line
  vmessage[nviolations] = message
}

function report(   i, j, l, m) {
  for (i = 2; i <= nviolations; i++) {
    l = vline[i]
    m = vmessage[i]
    for (j = i - 1; j >= 1 && vline[j] > l; j--) {
      vline[j + 1] = vline[j]
      vmessage[j + 1] = vmessage[j]
    }
    vline[j + 1] = l
    vmessage[j + 1] = m
  }
  for (i = 1; i <= nviolations; i++) {
    print vline[i] "\t" vmessage[i]
  }
}
