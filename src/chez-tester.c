/* Visible native regression driver. Lean verifies observations and batch acks.
 * Only the disposable fixture is edited. No shell commands or log growth. */
#include "header.h"

static int requested, running, editing_active;
int chez_tester_clipboard_isolated(void) { return editing_active; }
static long edit_values[8];
static unsigned long edit_stats_serial;
void fe_tester_history_stats(long a, long b, long c, long d, long e, long f, long g, long h)
{
 edit_values[0]=a;edit_values[1]=b;edit_values[2]=c;edit_values[3]=d;
 edit_values[4]=e;edit_values[5]=f;edit_values[6]=g;edit_values[7]=h;edit_stats_serial++;
}
void chez_tester(void)
{
 if (running) { msg("chez-tester is already running"); return; }
 requested = getenv("CHEZ_TESTER_AUTORUN") ? 1 : 2;
}

void run_tester(void)
{
 if (running) { msg("run-tester is already running"); return; }
 requested = 2;
}

#if defined(__EMSCRIPTEN__) || defined(_WIN32)
void chez_tester_poll(void)
{
 if (requested) { requested = 0; msg("chez-tester: native POSIX terminal/GUI adapter required"); }
}
#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

#define TRACE_CAP 8192u
#define SUMMARY_CAP 4096u
#define LINE_CAP 128u
#define BATCH_MAX 62u
#define CHECKER_TIMEOUT 10000

extern char chezemax_program_path[4096];
extern int fe_line_number(long);

struct run {
 unsigned lines, passes, profile, delay, batch;
 unsigned seq, acked, pending, bytes, max_enters, file_count, edit_cycles, seed;
 int edit_test;
 long ring_peak, ring_bytes_peak, undo_bytes_peak, undo_accounted_peak;
 int histories_restored;
 int to, from, cancelled, keep_reference;
 pid_t child;
 FILE *trace_file, *failure_file, *summary_file;
 char trace[TRACE_CAP], header[LINE_CAP];
 size_t used;
 char *expected;
 char directory[4096], lock[4096];
 char snapshot_dir[64], snapshot[128], diagnostic[128], data_path[128], selected[4096];
 dev_t protected_dev[2]; ino_t protected_ino[2]; unsigned protected_count;
};

static long long milliseconds(void)
{
 struct timespec t;
 clock_gettime(CLOCK_MONOTONIC, &t);
 return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/* Never wait forever on a dead or non-reading checker. */
static int ready(struct run *r, int fd, int writing, long long end)
{
 if (fd < 0 || fd >= FD_SETSIZE) return 0;
 while (milliseconds() < end) {
  if (screen_test_cancelled()) { r->cancelled = 1; return 0; }
  fd_set set; FD_ZERO(&set); FD_SET(fd, &set);
  struct timeval timeout = { 0, 100000 };
  int n = select(fd + 1, writing ? NULL : &set, writing ? &set : NULL, NULL, &timeout);
  if (n > 0) return 1;
  if (n < 0 && errno != EINTR) return 0;
 }
 return 0;
}

static int send_line(struct run *r, const char *line)
{
 size_t len = strlen(line), at = 0;
 if (len > LINE_CAP) return 0;
 long long end = milliseconds() + CHECKER_TIMEOUT;
 while (at < len) {
  if (!ready(r, r->to, 1, end)) return 0;
  ssize_t n = write(r->to, line + at, len - at);
  if (n > 0) at += (size_t)n;
  else if (n < 0 && errno != EINTR && errno != EAGAIN) return 0;
 }
 return 1;
}

static int read_reply(struct run *r, char *line, size_t capacity)
{
 size_t at = 0;
 long long end = milliseconds() + CHECKER_TIMEOUT;
 while (at + 1 < capacity) {
  if (!ready(r, r->from, 0, end)) return 0;
  char c; ssize_t n = read(r->from, &c, 1);
  if (n == 0) return 0;
  if (n < 0) { if (errno == EINTR || errno == EAGAIN) continue; return 0; }
  if (c == '\n') { line[at] = 0; return 1; }
  line[at++] = c;
 }
 return 0;
}

static int receive(struct run *r, const char *expected)
{
 char line[64];
 if (!read_reply(r,line,sizeof line)) return 0;
 if (strcmp(line,expected)) { snprintf(r->diagnostic,sizeof r->diagnostic,"%s",line); return 0; }
 return 1;
}

/* Copy the current, possibly unsaved buffer; never write its visited file.
 * The source snapshot has its own 256 KiB cap and is removed after the run. */
static int snapshot_buffer(struct run *r, buffer_t *bp)
{
 point_t size = document_size(bp);
 if (size <= 0 || size > 262144) return 0;
 snprintf(r->snapshot_dir, sizeof r->snapshot_dir, "/tmp/chez-tester-source.XXXXXX");
 if (!mkdtemp(r->snapshot_dir)) { r->snapshot_dir[0] = 0; return 0; }
 snprintf(r->snapshot, sizeof r->snapshot, "%s/chez-tester.lean", r->snapshot_dir);
 FILE *f = fopen(r->snapshot, "wx");
 if (!f) return 0;
 int ok = 1;
 for (point_t i = 0; i < size; i++) if (fputc((unsigned char)*ptr(bp, i), f) == EOF) { ok = 0; break; }
 if (fclose(f)) ok = 0;
 return ok;
}

static int read_plan(struct run *r)
{
 char line[128];
 if (!read_reply(r, line, sizeof line)) return 0;
 if (!strncmp(line,"PLAN3 ",6)) {
  unsigned values[4];
  const char *p=line+6;
  for(unsigned i=0;i<4;i++){
   if(*p<'0'||*p>'9')return 0;
   errno=0;char *end;unsigned long v=strtoul(p,&end,10);
   if(errno||v>4294967295UL)return 0;
   values[i]=(unsigned)v;
   if(i==3){if(*end)return 0;}else{if(*end!=' ')return 0;p=end+1;}
  }
  r->file_count=values[0];r->edit_cycles=values[1];r->delay=values[2];r->seed=values[3];r->edit_test=1;r->keep_reference=0;
  return r->file_count>0&&r->file_count<=64&&r->edit_cycles>0&&r->delay<=1000&&
    (unsigned long long)r->file_count*r->edit_cycles<=1000000;
 }
 if (strncmp(line, "PLAN2 ", 6)) { snprintf(r->diagnostic, sizeof r->diagnostic, "%s", line); return 0; }
 unsigned reference;
 unsigned *fields[] = { &r->bytes, &r->max_enters, &r->passes, &r->profile, &r->delay, &reference };
 unsigned lower[] = {0, 8, 1, 1, 0, 0}, upper[] = {67108864, 1000000, 1000, 3, 1000, 1};
 const char *p = line + 6;
 for (unsigned i = 0; i < 6; i++) {
  if (*p < '0' || *p > '9') return 0;
  errno = 0; char *end; unsigned long value = strtoul(p, &end, 10);
  if (errno || value < lower[i] || value > upper[i]) return 0;
  *fields[i] = (unsigned)value;
  if (i == 5) { if (*end) return 0; }
  else { if (*end != ' ') return 0; p = end + 1; }
 }
 r->keep_reference = (int)reference;
 return (unsigned long long)r->passes * (r->max_enters + 1) <= 1000000;
}

static FILE *output_file(struct run *r, const char *directory, const char *name)
{
 char path[4096];
 if (snprintf(path, sizeof path, "%s/%s", directory, name) >= (int)sizeof path) return NULL;
 int fd = open(path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
 if (fd < 0) return NULL;
 struct stat st;
 if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 || st.st_uid != getuid()) {
  close(fd); return NULL;
 }
 /* A selected text or the current Lean source may itself have one of the
  * managed report names. Preserve it rather than truncating a visited file. */
 for (unsigned i = 0; i < r->protected_count; i++)
  if (st.st_dev == r->protected_dev[i] && st.st_ino == r->protected_ino[i]) { close(fd); return NULL; }
 if (ftruncate(fd, 0)) { close(fd); return NULL; }
 FILE *f = fdopen(fd, "w"); if (!f) close(fd);
 return f;
}

static int prepare_output(struct run *r, const char *base)
{
 const char *dir = getenv("CHEZ_TESTER_DIR");
 if (snprintf(r->directory, sizeof r->directory, "%s", dir ? dir : base) >= (int)sizeof r->directory) return 0;
 if (mkdir(r->directory, 0700) && errno != EEXIST) return 0;
 struct stat st;
 if (lstat(r->directory, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 0022)) return 0;
 if (snprintf(r->lock, sizeof r->lock, "%s/run.lock", r->directory) >= (int)sizeof r->lock) return 0;
 int fd = open(r->lock, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
 if (fd < 0) { r->lock[0] = 0; return 0; }
 close(fd);
 r->trace_file = output_file(r, r->directory, "pending.trace");
 r->failure_file = output_file(r, r->directory, "failure.trace");
 r->summary_file = output_file(r, r->directory, "summary.txt");
 return r->trace_file && r->failure_file && r->summary_file;
}

static int append_trace(struct run *r, const char *text)
{
 size_t n = strlen(text);
 if (n > LINE_CAP || n > TRACE_CAP - r->used) return 0;
 if (fwrite(text, 1, n, r->trace_file) != n || fflush(r->trace_file)) return 0;
 memcpy(r->trace + r->used, text, n); r->used += n;
 return 1;
}

static int new_batch(struct run *r)
{
 if (fflush(r->trace_file) || ftruncate(fileno(r->trace_file), 0) || fseek(r->trace_file, 0, SEEK_SET)) return 0;
 r->used = 0;
 char checkpoint[LINE_CAP];
 snprintf(checkpoint, sizeof checkpoint, "C %u\n", r->acked);
 return append_trace(r, r->header) && (r->keep_reference || append_trace(r, checkpoint));
}

static int acknowledge_batch(struct run *r)
{
 if (!r->pending) return 1;
 char line[LINE_CAP], expected[64];
 snprintf(line, sizeof line, "B %u\n", r->seq);
 snprintf(expected, sizeof expected, "ACK %u", r->seq);
 if ((r->keep_reference && !append_trace(r, line)) || !send_line(r, line) || !receive(r, expected)) return 0;
 /* Only a matching acknowledgment permits deletion/reuse. */
 r->acked = r->seq; r->pending = 0;
 return r->keep_reference || new_batch(r);
}

static int start_checker(struct run *r, const char *path, int from_buffer)
{
 int in[2], out[2];
 if (pipe(in)) return 0;
 if (pipe(out)) { close(in[0]); close(in[1]); return 0; }
 r->child = fork();
 if (r->child == 0) {
  dup2(in[0], STDIN_FILENO); dup2(out[1], STDOUT_FILENO);
  int null = open("/dev/null", O_WRONLY); if (null >= 0) { dup2(null, STDERR_FILENO); close(null); }
  close(in[0]); close(in[1]); close(out[0]); close(out[1]);
  if (from_buffer) execlp("lean", "lean", "--run", r->snapshot, "--editor-file", r->selected, r->data_path, (char *)NULL);
  else execl(path, path, (char *)NULL);
  _exit(127);
 }
 close(in[0]); close(out[1]);
 if (r->child < 0) { close(in[1]); close(out[0]); return 0; }
 r->to = in[1]; r->from = out[0];
 if (fcntl(r->to, F_SETFL, O_NONBLOCK) < 0 || fcntl(r->from, F_SETFL, O_NONBLOCK) < 0) return 0;
 return !from_buffer || read_plan(r);
}

static int stop_checker(struct run *r, int success)
{
 if (r->to >= 0) { close(r->to); r->to = -1; }
 if (r->from >= 0) { close(r->from); r->from = -1; }
 if (r->child <= 0) return 0;
 if (!success) kill(r->child, SIGTERM);
 int status = 0;
 for (int i = 0; i < 100; i++) {
  pid_t got = waitpid(r->child, &status, WNOHANG);
  if (got == r->child) { r->child = 0; return success && WIFEXITED(status) && WEXITSTATUS(status) == 0; }
  if (got < 0 && errno != EINTR) { r->child = 0; return 0; }
  screen_pause(10);
 }
 kill(r->child, SIGKILL); waitpid(r->child, &status, 0); r->child = 0;
 return 0;
}

static int number(const char *env, const char *prompt, unsigned fallback, unsigned low, unsigned high, unsigned *out)
{
 char value[32] = "";
 const char *s = getenv(env);
 if (!s && !getenv("CHEZ_TESTER_NONINTERACTIVE")) {
  snprintf(value, sizeof value, "%u", fallback);
  if (!getinput((char *)prompt, value, sizeof value, F_NONE)) return 0;
  s = value;
 }
 if (!s || !*s) { *out = fallback; return 1; }
 for (const char *p = s; *p; p++) if (*p < '0' || *p > '9') return 0;
 errno = 0; char *end; unsigned long n = strtoul(s, &end, 10);
 if (errno || *end || n < low || n > high) return 0;
 *out = (unsigned)n; return 1;
}

static int fixture_intact(buffer_t *bp, const struct run *r)
{
 if (curbp != bp || document_size(bp) != (point_t)r->bytes) return 0;
 for (point_t i = 0; i < document_size(bp); i++) if (*ptr(bp, i) != (unsigned char)r->expected[i]) return 0;
 return 1;
}

static int observe(struct run *r, buffer_t *bp, unsigned action, unsigned long errors)
{
 char line[LINE_CAP];
 int mode = curbp == bp && (bp->b_flags & B_READONLY) && !bp->b_read_visual ? bp->b_read_mode : 0;
 long point = curbp == bp ? bp->b_point : -1;
 int logical = curbp == bp && point >= 0 && point <= document_size(bp) ? fe_line_number(point) : 0;
 snprintf(line, sizeof line, "S %u %u %d %ld %d %d %u\n", r->seq, action, mode, point, logical,
          fixture_intact(bp, r), runtime_failure_serial() != errors);
 if ((r->keep_reference && r->seq >= 60) || !append_trace(r, line) || !send_line(r, line)) return 0;
 r->seq++; r->pending++;
 return r->pending < r->batch || acknowledge_batch(r);
}

#include "chez-edit-tester.h"

static void run_test(int from_buffer)
{
 struct run r = { .to = -1, .from = -1, .batch = 62 };
 const char *reason = "configuration rejected"; int success = 0;
 buffer_t *origin = curbp, *fixture = NULL;
 int original_mark = mark_active;
 char origin_name[NBUFN], fixture_name[NBUFN] = "", checker[4096], base[4096], install[4096];
 snprintf(origin_name, sizeof origin_name, "%s", origin->b_bname);
 snprintf(install, sizeof install, "%s", chezemax_program_path);
 char *slash = strrchr(install, '/'); if (!slash) { msg("chez-tester: cannot locate installation"); return; } *slash = 0;
 const char *override = getenv("CHEZ_TESTER_CHECKER");
 if (snprintf(checker, sizeof checker, "%s/Lean/chez-tester", install) >= (int)sizeof checker ||
     snprintf(base, sizeof base, "%s/Lean/results", install) >= (int)sizeof base) { msg("chez-tester: path too long"); return; }
 if (override && snprintf(checker, sizeof checker, "%s", override) >= (int)sizeof checker) { msg("chez-tester: checker path too long"); return; }
 if (!from_buffer && access(checker, X_OK)) { msg("chez-tester: build optional checker first: make -C Lean"); return; }
 if (!screen_active() || screen_cols() < 16 || screen_rows() < 3 || !tester_can_inject()) {
  msg("chez-tester: needs an idle screen >=16 columns; no keyboard macro"); return;
 }
 if (!from_buffer && (!number("CHEZ_TESTER_PROFILE", "Profile 1 READ, 2 VIM, 3 both [3]: ", 3, 1, 3, &r.profile) ||
     !number("CHEZ_TESTER_PASSES", "Complete passes [4]: ", 4, 1, 1000, &r.passes) ||
     !number("CHEZ_TESTER_DELAY_MS", "Visible delay per Enter, ms [10]: ", 10, 0, 1000, &r.delay) ||
     !number("CHEZ_TESTER_LINES", "Fixture lines [256]: ", 256, 1, 4096, &r.lines) ||
     r.passes * (r.lines + 9) > 1000000)) { msg("chez-tester: cancelled or invalid bounded configuration"); return; }
 if (from_buffer) {
  if (snprintf(r.selected, sizeof r.selected, "%s/docs/chezemax.md", install) >= (int)sizeof r.selected ||
      !getfilename_default("Text file or Markdown directory: ", r.selected, sizeof r.selected)) {
   msg("chez-tester: file selection cancelled"); return;
  }
 }
 r.keep_reference = getenv("CHEZ_TESTER_KEEP_REFERENCE") != NULL;
 if (!from_buffer && r.keep_reference && r.passes * (r.lines + 9) > 60) { msg("Reference mode requires <=60 observations; choose a tiny fixture/run"); return; }
 snprintf(r.header, sizeof r.header, "H 1 %u %u %u %u\n", r.lines, r.passes, r.profile, r.batch);
 void (*oldpipe)(int) = signal(SIGPIPE, SIG_IGN);
 if (oldpipe == SIG_ERR) { msg("chez-tester: cannot guard checker pipe"); return; }
 if (from_buffer) {
  const char *protected_paths[] = { r.selected, origin->b_fname };
  for (unsigned i = 0; i < 2; i++) {
   struct stat st;
   if (protected_paths[i][0] && !stat(protected_paths[i], &st)) {
    r.protected_dev[r.protected_count] = st.st_dev;
    r.protected_ino[r.protected_count++] = st.st_ino;
   }
  }
 }
 if (!prepare_output(&r, base)) { reason = "output directory busy/unsafe or IO failure (stale run.lock requires review)"; goto finish; }
 if (from_buffer) {
  struct stat input_stat;
  if (stat(r.selected, &input_stat) || (!S_ISREG(input_stat.st_mode) && !S_ISDIR(input_stat.st_mode)) || input_stat.st_size > 67108864 ||
      strchr(r.selected, '\n') || strchr(r.selected, '\r')) {
   reason = "choose an existing regular UTF-8 text file, within maxInputBytes (64 MiB ceiling)"; goto finish;
  }
  msg("chez-tester: Lean is checking this buffer and evaluating TestSettings..."); dispmsg(); screen_refresh();
  if (!snapshot_buffer(&r, origin)) { reason = "cannot snapshot buffer (source limit 256 KiB)"; goto finish; }
  const char *suffix = strrchr(r.selected, '.');
  if (!suffix || strchr(suffix, '/') || strlen(suffix) > 31) suffix = ".txt";
  snprintf(r.data_path, sizeof r.data_path, "%s/input%s", r.snapshot_dir, suffix);
  snprintf(checker, sizeof checker, "lean --run (current buffer snapshot)");
 }
 if (!start_checker(&r, checker, from_buffer)) { reason = "Lean/checker startup failed: check Lean installation, source and settings"; goto finish; }
 if (r.edit_test) {
  success=run_edit_test(&r,origin_name);
  if(success)success=stop_checker(&r,1);
  mark_active=original_mark;
  reason=success ? "Lean accepted edit cycles, exact restoration and bounded histories" : "edit protocol, byte restoration, history bounds or cleanup rejected";
  goto finish;
 }
 if (!from_buffer && r.keep_reference && r.passes * (r.lines + 9) > 60) { reason = "reference mode requires <=60 observations"; goto finish; }
 if (from_buffer)
  snprintf(r.header, sizeof r.header, "H 2 %u %u %u %u %u\n", r.bytes, r.max_enters, r.passes, r.profile, r.batch);
 else snprintf(r.header, sizeof r.header, "H 1 %u %u %u %u\n", r.lines, r.passes, r.profile, r.batch);
 if (!new_batch(&r) || !send_line(&r, r.header) || !receive(&r, "READY")) { reason = "Lean rejected header or pending-file IO failed"; goto finish; }
 for (unsigned i = 0; i < 10000; i++) {
  snprintf(fixture_name, sizeof fixture_name, "*ct%04u*", i);
  if (!find_buffer(fixture_name, FALSE)) break;
  fixture_name[0] = 0;
 }
 if (!fixture_name[0]) { reason = "no unused fixture buffer name"; goto finish; }
 if (!from_buffer) r.bytes = r.lines * 16;
 r.expected = malloc(r.bytes ? r.bytes : 1);
 if (!r.expected) { reason = "document snapshot allocation failed"; goto finish; }
 if (from_buffer) {
  FILE *f = fopen(r.data_path, "rb");
  if (!f) { reason = "cannot open Lean document snapshot"; goto finish; }
  int valid = fread(r.expected, 1, r.bytes, f) == r.bytes && fgetc(f) == EOF;
  if (fclose(f)) valid = 0;
  if (!valid) { reason = "document snapshot read failed"; goto finish; }
  r.lines = 1;
  for (unsigned i = 0; i < r.bytes; i++) if (r.expected[i] == '\n') r.lines++;
 } else {
  for (unsigned i = 0; i < r.lines; i++) {
   char row[32]; snprintf(row, sizeof row, "line %010u\n", i + 1);
   memcpy(r.expected + i * 16, row, 16);
  }
 }
 fixture = find_buffer(fixture_name, TRUE);
 if (!fixture || !growgap(fixture, (point_t)r.bytes)) { reason = "document allocation failed"; goto finish; }
 memcpy(fixture->b_gap, r.expected, r.bytes); fixture->b_gap += r.bytes;
 /* Only the private snapshot is associated with this buffer; never the
  * original filename. Its extension enables normal language/wrapping hooks. */
 if (from_buffer) safe_strncpy(fixture->b_fname, r.data_path, NAME_MAX);
 fixture->b_point = 0; select_buffer(fixture_name); mark_active = 0;
 unsigned long errors = runtime_failure_serial();
 screen_flushinp();
 for (unsigned pass = 0; pass < r.passes; pass++) {
  fe_read_mode(r.profile == 3 ? (pass % 2 ? 1 : 2) : (int)r.profile);
  fixture->b_point = 0; fixture->b_col = 0; fixture->b_page = 0; fixture->b_epage = 0;
  update_display();
  if (!observe(&r, fixture, 0, errors)) { reason = "reset observation/checker/quota rejected"; goto finish; }
  unsigned holds = 0, step = 0;
  unsigned limit = from_buffer ? r.max_enters : r.lines + 8;
  for (; step < limit && (!from_buffer || holds < 8); step++) {
   if (screen_test_cancelled()) { r.cancelled = 1; reason = "user cancelled or resized"; goto finish; }
   point_t before = fixture->b_point;
   unread_key_bytes("\r", 1);
   input = get_key(key_map, &key_return);
   editor_dispatch_key();
   update_display();  /* Real rendering and Scheme callbacks, on every step. */
   if (!observe(&r, fixture, 1, errors)) { reason = "Enter observation/checker/quota rejected"; goto finish; }
   if (before == (point_t)r.bytes && fixture->b_point == (point_t)r.bytes) holds++; else holds = 0;
   msg("chez-tester %u/%u: Enter %u; line %d; Lean acknowledged %u", pass + 1, r.passes, step + 1, fe_line_number(fixture->b_point), r.acked);
   dispmsg(); screen_refresh(); screen_pause((int)r.delay);
  }
  if (from_buffer && holds < 8) { reason = "Enter limit reached before stable EOF"; goto finish; }
 }
 if (!acknowledge_batch(&r)) { reason = "final batch not acknowledged"; goto finish; }
 {
  char end[LINE_CAP], expected[64];
  snprintf(end, sizeof end, "Z %u\n", r.seq); snprintf(expected, sizeof expected, "PASS %u", r.seq);
  if ((r.keep_reference && !append_trace(&r, end)) || !send_line(&r, end)) { reason = "end marker write failed"; goto finish; }
  close(r.to); r.to = -1; /* Lean rejects trailing input before reporting PASS. */
  if (!receive(&r, expected)) { reason = "checker did not accept complete run"; goto finish; }
 }
 success = stop_checker(&r, 1);
 reason = success ? "Lean accepted complete recorded execution" : "checker exit status rejected";
finish:
 if (!success) stop_checker(&r, 0);
 if (fixture) {
  select_buffer(origin_name); mark_active = original_mark;
  delete_buffer(fixture);
 }
 free(r.expected);
 if(r.snapshot_dir[0])for(unsigned i=0;i<64;i++){
  char path[128];snprintf(path,sizeof path,"%s/input-%u.md",r.snapshot_dir,i);unlink(path);
 }
 if (r.data_path[0]) unlink(r.data_path);
 if (r.snapshot[0]) unlink(r.snapshot);
 if (r.snapshot_dir[0]) rmdir(r.snapshot_dir);
 screen_flushinp(); resize_terminal();
 if (success && !r.keep_reference && r.trace_file) { fflush(r.trace_file); ftruncate(fileno(r.trace_file), 0); }
 if (!success && r.failure_file && r.used) fwrite(r.trace, 1, r.used, r.failure_file);
 if (r.summary_file) {
  char report[SUMMARY_CAP];
  int n = snprintf(report, sizeof report,
   "chez-tester v1\nstatus=%s\nreason=%s\nprotocol=%s\nfiles_tested=%u\ncycles_per_file=%u\nseed=%u\nprofile=%u\nlines=%u\npasses=%u\nobservations=%u\nacknowledged=%u\n"
   "ring_peak=%ld\nring_bytes_peak=%ld\nundo_live_bytes_peak=%ld\nundo_accounted_bytes_peak=%ld\nhistories_restored=%d\ninput_file=%.512s\ninput_bytes=%u\nreference_kept=%d\nrun_time_unix=%lld\nchecker=%.512s\nlean_diagnostic=%.120s\npending_limit=8192\nfailure_limit=8192\nsummary_limit=4096\ntotal_disk_limit=20480\n"
   "proof_scope=Lean model/checker/protocol; C observations and OS/IO are trusted\n"
   "failure.trace is a bounded diagnostic window, not a standalone proof certificate\n",
   success ? "PASS" : r.cancelled ? "CANCELLED" : "FAIL", reason, r.edit_test ? "move-copy-paste-undo" : "enter-readonly", r.edit_test ? r.file_count : 1, r.edit_test ? r.edit_cycles : 0, r.seed, r.profile, r.lines, r.passes, r.seq, r.acked, r.ring_peak, r.ring_bytes_peak, r.undo_bytes_peak, r.undo_accounted_peak, r.histories_restored, r.selected, r.bytes, r.keep_reference, (long long)time(NULL), checker, r.diagnostic);
  if (n < 0 || n >= (int)sizeof report || fwrite(report, 1, (size_t)n, r.summary_file) != (size_t)n || fflush(r.summary_file)) success = 0;
 }
 if (r.trace_file && fclose(r.trace_file)) success = 0;
 if (r.failure_file && fclose(r.failure_file)) success = 0;
 if (r.summary_file && fclose(r.summary_file)) success = 0;
 if (r.lock[0]) unlink(r.lock);
 signal(SIGPIPE, oldpipe);
 msg("chez-tester %s: %u observations, %u acknowledged; %.120s/summary.txt",
     success ? "PASS" : r.cancelled ? "CANCELLED" : "FAIL", r.seq, r.acked, r.directory);
 dispmsg(); screen_refresh();
 if (getenv("CHEZ_TESTER_EXIT")) done = 1;
}

void chez_tester_poll(void)
{
 if (!requested || running) return;
 int from_buffer = requested == 2;
 requested = 0; running = 1; run_test(from_buffer); running = 0;
 if (getenv("CHEZ_TESTER_EXIT")) done = 1;
}
#endif
