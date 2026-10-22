// Native (POSIX) implementation of dii/rg/sys.
//
// Conventions:
// - Paths arrive as NUL-terminated UTF-8 `Bytes` (borrowed).
// - Functions that fail return -1 (or an empty `Bytes`) and record the
//   errno, translated to its Linux value, in `last_err`, which MoonBit reads
//   with `moonbit_rgsys_last_err`.

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <moonbit.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <crt_externs.h>
#define RGSYS_ENVIRON (*_NSGetEnviron())
#else
extern char **environ;
#define RGSYS_ENVIRON environ
#endif

static int last_err = 0;

// Translate a host errno into the Linux numbering used by the MoonBit side.
static int linux_errno(int e) {
  switch (e) {
  case EPERM: return 1;
  case ENOENT: return 2;
  case ESRCH: return 3;
  case EINTR: return 4;
  case EIO: return 5;
  case ENXIO: return 6;
  case E2BIG: return 7;
  case ENOEXEC: return 8;
  case EBADF: return 9;
  case ECHILD: return 10;
  case EAGAIN: return 11;
  case ENOMEM: return 12;
  case EACCES: return 13;
  case EFAULT: return 14;
  case EBUSY: return 16;
  case EEXIST: return 17;
  case EXDEV: return 18;
  case ENODEV: return 19;
  case ENOTDIR: return 20;
  case EISDIR: return 21;
  case EINVAL: return 22;
  case ENFILE: return 23;
  case EMFILE: return 24;
  case ENOTTY: return 25;
  case ETXTBSY: return 26;
  case EFBIG: return 27;
  case ENOSPC: return 28;
  case ESPIPE: return 29;
  case EROFS: return 30;
  case EMLINK: return 31;
  case EPIPE: return 32;
  case EDOM: return 33;
  case ERANGE: return 34;
  case EDEADLK: return 35;
  case ENAMETOOLONG: return 36;
  case ENOLCK: return 37;
  case ENOSYS: return 38;
  case ENOTEMPTY: return 39;
  case ELOOP: return 40;
  case EOVERFLOW: return 75;
  case EILSEQ: return 84;
  case ENOTSOCK: return 88;
#if defined(EOPNOTSUPP) && EOPNOTSUPP != ENOTSUP
  case EOPNOTSUPP: return 95;
#endif
  case ENOTSUP: return 95;
  case ECONNRESET: return 104;
  case ETIMEDOUT: return 110;
  case ECONNREFUSED: return 111;
  case ESTALE: return 116;
  case EDQUOT: return 122;
  case ECANCELED: return 125;
  default: return e;
  }
}

static void set_err(void) { last_err = linux_errno(errno); }

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_last_err(void) { return last_err; }

static moonbit_bytes_t make_bytes(const void *data, size_t len) {
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) memcpy(b, data, len);
  return b;
}

static moonbit_bytes_t empty_bytes(void) { return moonbit_make_bytes(0, 0); }

// ---------------------------------------------------------------------------
// Growable byte buffer used to build blobs.

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} buf_t;

static int buf_reserve(buf_t *b, size_t extra) {
  if (b->len + extra <= b->cap) return 0;
  size_t cap = b->cap ? b->cap : 256;
  while (cap < b->len + extra) cap *= 2;
  char *p = realloc(b->data, cap);
  if (!p) return -1;
  b->data = p;
  b->cap = cap;
  return 0;
}

static int buf_push(buf_t *b, const void *data, size_t len) {
  if (buf_reserve(b, len) < 0) return -1;
  memcpy(b->data + b->len, data, len);
  b->len += len;
  return 0;
}

// ---------------------------------------------------------------------------
// Process / environment.

MOONBIT_FFI_EXPORT void moonbit_rgsys_exit(int32_t code) { exit(code); }

// Returns [1] ++ value if set, or [] if unset.
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_getenv(moonbit_bytes_t name) {
  const char *v = getenv((const char *)name);
  if (!v) return empty_bytes();
  size_t len = strlen(v);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)(len + 1), 0);
  b[0] = 1;
  memcpy(b + 1, v, len);
  return b;
}

// All "KEY=VALUE" entries, each terminated by NUL.
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_environ(void) {
  buf_t b = {0};
  char **env = RGSYS_ENVIRON;
  for (; env && *env; env++) {
    if (buf_push(&b, *env, strlen(*env) + 1) < 0) break;
  }
  moonbit_bytes_t r = make_bytes(b.data, b.len);
  free(b.data);
  return r;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_getcwd(void) {
  last_err = 0;
  size_t cap = 256;
  for (;;) {
    char *p = malloc(cap);
    if (!p) {
      last_err = 12;
      return empty_bytes();
    }
    if (getcwd(p, cap)) {
      moonbit_bytes_t r = make_bytes(p, strlen(p));
      free(p);
      return r;
    }
    int e = errno;
    free(p);
    if (e != ERANGE) {
      last_err = linux_errno(e);
      return empty_bytes();
    }
    cap *= 2;
  }
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_gethostname(void) {
  last_err = 0;
  char name[1024];
  if (gethostname(name, sizeof name) != 0) {
    set_err();
    return empty_bytes();
  }
  name[sizeof name - 1] = 0;
  return make_bytes(name, strlen(name));
}

MOONBIT_FFI_EXPORT int64_t moonbit_rgsys_now_nanos(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
  return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

// ---------------------------------------------------------------------------
// File descriptors.

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_write_all(int32_t fd, uint8_t *buf,
                                                   int32_t start, int32_t len) {
  const uint8_t *p = buf + start;
  while (len > 0) {
    ssize_t n = write(fd, p, (size_t)len);
    if (n < 0) {
      if (errno == EINTR) continue;
      set_err();
      return -1;
    }
    p += n;
    len -= (int32_t)n;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_read(int32_t fd, uint8_t *buf,
                                              int32_t start, int32_t len) {
  for (;;) {
    ssize_t n = read(fd, buf + start, (size_t)len);
    if (n < 0) {
      if (errno == EINTR) continue;
      set_err();
      return -1;
    }
    return (int32_t)n;
  }
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_isatty(int32_t fd) {
  return isatty(fd) ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_stdin_readable(void) {
  if (isatty(0)) return 0;
  struct stat st;
  if (fstat(0, &st) != 0) return 0;
  return (S_ISREG(st.st_mode) || S_ISFIFO(st.st_mode) || S_ISSOCK(st.st_mode))
             ? 1
             : 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_open_read(moonbit_bytes_t path) {
  for (;;) {
    int fd = open((const char *)path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
      if (errno == EINTR) continue;
      set_err();
      return -1;
    }
    return fd;
  }
}

MOONBIT_FFI_EXPORT void moonbit_rgsys_close(int32_t fd) { close(fd); }

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_write_file(moonbit_bytes_t path,
                                                    uint8_t *data,
                                                    int32_t len) {
  int fd = open((const char *)path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
                0666);
  if (fd < 0) {
    set_err();
    return -1;
  }
  if (moonbit_rgsys_write_all(fd, data, 0, len) < 0) {
    close(fd);
    return -1;
  }
  if (close(fd) != 0) {
    set_err();
    return -1;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Paths.

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_mkdir(moonbit_bytes_t path) {
  if (mkdir((const char *)path, 0777) != 0) {
    set_err();
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_rmdir(moonbit_bytes_t path) {
  if (rmdir((const char *)path) != 0) {
    set_err();
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_unlink(moonbit_bytes_t path) {
  if (unlink((const char *)path) != 0) {
    set_err();
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_symlink(moonbit_bytes_t target,
                                                 moonbit_bytes_t link) {
  if (symlink((const char *)target, (const char *)link) != 0) {
    set_err();
    return -1;
  }
  return 0;
}

// File type codes shared with MoonBit: 0 unknown, 1 file, 2 dir, 3 symlink,
// 4 other.
static int32_t mode_kind(mode_t m) {
  if (S_ISREG(m)) return 1;
  if (S_ISDIR(m)) return 2;
  if (S_ISLNK(m)) return 3;
  return 4;
}

// out[0] = kind, out[1] = size, out[2] = dev, out[3] = ino
MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_stat(moonbit_bytes_t path,
                                              int32_t follow, int64_t *out) {
  struct stat st;
  int r = follow ? stat((const char *)path, &st) : lstat((const char *)path, &st);
  if (r != 0) {
    set_err();
    return -1;
  }
  out[0] = mode_kind(st.st_mode);
  out[1] = (int64_t)st.st_size;
  out[2] = (int64_t)(uint64_t)st.st_dev;
  out[3] = (int64_t)(uint64_t)st.st_ino;
  return 0;
}

// Each entry: kind byte, name bytes, NUL. "." and ".." are skipped.
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_readdir(moonbit_bytes_t path) {
  last_err = 0;
  DIR *d = opendir((const char *)path);
  if (!d) {
    set_err();
    return empty_bytes();
  }
  buf_t b = {0};
  for (;;) {
    errno = 0;
    struct dirent *ent = readdir(d);
    if (!ent) {
      if (errno != 0) set_err();
      break;
    }
    const char *name = ent->d_name;
    if (name[0] == '.' &&
        (name[1] == 0 || (name[1] == '.' && name[2] == 0)))
      continue;
    uint8_t kind = 0;
#ifdef DT_UNKNOWN
    switch (ent->d_type) {
    case DT_REG: kind = 1; break;
    case DT_DIR: kind = 2; break;
    case DT_LNK: kind = 3; break;
    case DT_UNKNOWN: kind = 0; break;
    default: kind = 4; break;
    }
#endif
    if (buf_push(&b, &kind, 1) < 0 || buf_push(&b, name, strlen(name) + 1) < 0) {
      last_err = 12;
      break;
    }
  }
  closedir(d);
  moonbit_bytes_t r = last_err ? empty_bytes() : make_bytes(b.data, b.len);
  free(b.data);
  return r;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_readlink(moonbit_bytes_t path) {
  last_err = 0;
  size_t cap = 256;
  for (;;) {
    char *p = malloc(cap);
    if (!p) {
      last_err = 12;
      return empty_bytes();
    }
    ssize_t n = readlink((const char *)path, p, cap);
    if (n < 0) {
      set_err();
      free(p);
      return empty_bytes();
    }
    if ((size_t)n < cap) {
      moonbit_bytes_t r = make_bytes(p, (size_t)n);
      free(p);
      return r;
    }
    free(p);
    cap *= 2;
  }
}

// ---------------------------------------------------------------------------
// Processes.

static void put_i32(uint8_t *p, int32_t v) {
  uint32_t u = (uint32_t)v;
  p[0] = u & 0xff;
  p[1] = (u >> 8) & 0xff;
  p[2] = (u >> 16) & 0xff;
  p[3] = (u >> 24) & 0xff;
}

static int set_cloexec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) return -1;
  return fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

// Runs `prog` with `nargs` NUL-separated arguments in `argblob` (argv[0] is
// `prog`). stdin comes from `stdin_path`. On success returns
// [status:i32le][stdout_len:i32le][stdout][stderr]; on failure an empty
// `Bytes` with `last_err` set.
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_rgsys_run(moonbit_bytes_t prog,
                                                     moonbit_bytes_t argblob,
                                                     int32_t nargs,
                                                     moonbit_bytes_t stdin_path) {
  last_err = 0;
  char **argv = calloc((size_t)nargs + 2, sizeof(char *));
  if (!argv) {
    last_err = 12;
    return empty_bytes();
  }
  argv[0] = (char *)prog;
  char *p = (char *)argblob;
  for (int32_t i = 0; i < nargs; i++) {
    argv[i + 1] = p;
    p += strlen(p) + 1;
  }
  argv[nargs + 1] = NULL;

  int in_fd = -1, out_p[2] = {-1, -1}, err_p[2] = {-1, -1};
  buf_t out = {0}, err = {0};
  moonbit_bytes_t result = NULL;
  posix_spawn_file_actions_t fa;
  int fa_init = 0;

  in_fd = open((const char *)stdin_path, O_RDONLY | O_CLOEXEC);
  if (in_fd < 0) {
    set_err();
    goto done;
  }
  if (pipe(out_p) != 0 || pipe(err_p) != 0) {
    set_err();
    goto done;
  }
  set_cloexec(out_p[0]);
  set_cloexec(out_p[1]);
  set_cloexec(err_p[0]);
  set_cloexec(err_p[1]);

  if (posix_spawn_file_actions_init(&fa) != 0) {
    last_err = 12;
    goto done;
  }
  fa_init = 1;
  posix_spawn_file_actions_adddup2(&fa, in_fd, 0);
  posix_spawn_file_actions_adddup2(&fa, out_p[1], 1);
  posix_spawn_file_actions_adddup2(&fa, err_p[1], 2);

  pid_t pid;
  int rc = posix_spawnp(&pid, (const char *)prog, &fa, NULL, argv, RGSYS_ENVIRON);
  if (rc != 0) {
    last_err = linux_errno(rc);
    goto done;
  }
  close(out_p[1]);
  out_p[1] = -1;
  close(err_p[1]);
  err_p[1] = -1;
  close(in_fd);
  in_fd = -1;

  struct pollfd fds[2];
  int open_count = 2;
  int fd_of[2] = {out_p[0], err_p[0]};
  buf_t *dst[2] = {&out, &err};
  char chunk[65536];
  while (open_count > 0) {
    int n = 0;
    int idx[2];
    for (int i = 0; i < 2; i++) {
      if (fd_of[i] >= 0) {
        fds[n].fd = fd_of[i];
        fds[n].events = POLLIN;
        fds[n].revents = 0;
        idx[n] = i;
        n++;
      }
    }
    int pr = poll(fds, (nfds_t)n, -1);
    if (pr < 0) {
      if (errno == EINTR) continue;
      break;
    }
    for (int j = 0; j < n; j++) {
      if (!fds[j].revents) continue;
      int i = idx[j];
      ssize_t r = read(fd_of[i], chunk, sizeof chunk);
      if (r < 0 && errno == EINTR) continue;
      if (r <= 0) {
        close(fd_of[i]);
        fd_of[i] = -1;
        open_count--;
      } else {
        buf_push(dst[i], chunk, (size_t)r);
      }
    }
  }
  for (int i = 0; i < 2; i++)
    if (fd_of[i] >= 0) close(fd_of[i]);
  out_p[0] = err_p[0] = -1;

  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      set_err();
      goto done;
    }
  }
  int code;
  if (WIFEXITED(status))
    code = WEXITSTATUS(status);
  else if (WIFSIGNALED(status))
    code = 128 + WTERMSIG(status);
  else
    code = -1;

  result = moonbit_make_bytes((int32_t)(8 + out.len + err.len), 0);
  put_i32(result, code);
  put_i32(result + 4, (int32_t)out.len);
  if (out.len) memcpy(result + 8, out.data, out.len);
  if (err.len) memcpy(result + 8 + out.len, err.data, err.len);

done:
  if (fa_init) posix_spawn_file_actions_destroy(&fa);
  if (in_fd >= 0) close(in_fd);
  if (out_p[0] >= 0) close(out_p[0]);
  if (out_p[1] >= 0) close(out_p[1]);
  if (err_p[0] >= 0) close(err_p[0]);
  if (err_p[1] >= 0) close(err_p[1]);
  free(out.data);
  free(err.data);
  free(argv);
  return result ? result : empty_bytes();
}

// out[0..2] = mtime (sec, nsec, ok), out[3..5] = atime, out[6..8] = btime.
MOONBIT_FFI_EXPORT int32_t moonbit_rgsys_file_times(moonbit_bytes_t path,
                                                    int64_t *out) {
  struct stat st;
  if (stat((const char *)path, &st) != 0) {
    set_err();
    return -1;
  }
#if defined(__APPLE__)
  out[0] = (int64_t)st.st_mtimespec.tv_sec;
  out[1] = (int64_t)st.st_mtimespec.tv_nsec;
  out[2] = 1;
  out[3] = (int64_t)st.st_atimespec.tv_sec;
  out[4] = (int64_t)st.st_atimespec.tv_nsec;
  out[5] = 1;
  out[6] = (int64_t)st.st_birthtimespec.tv_sec;
  out[7] = (int64_t)st.st_birthtimespec.tv_nsec;
  out[8] = 1;
#else
  out[0] = (int64_t)st.st_mtim.tv_sec;
  out[1] = (int64_t)st.st_mtim.tv_nsec;
  out[2] = 1;
  out[3] = (int64_t)st.st_atim.tv_sec;
  out[4] = (int64_t)st.st_atim.tv_nsec;
  out[5] = 1;
  out[6] = 0;
  out[7] = 0;
  out[8] = 0;
#endif
  return 0;
}
