#include <jni.h>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <vector>

namespace {
bool path_bytes(JNIEnv* env, jbyteArray input, std::vector<char>& output) {
  const auto length = env->GetArrayLength(input);
  if (length < 1 || length >= 4096) return false;
  output.resize(static_cast<size_t>(length) + 1, '\0');
  env->GetByteArrayRegion(input, 0, length,
                          reinterpret_cast<jbyte*>(output.data()));
  if (env->ExceptionCheck()) return false;
  return std::memchr(output.data(), '\0', static_cast<size_t>(length)) == nullptr;
}
}  // namespace

// Byte arrays use ordinary UTF-8. JNI's modified UTF-8 string API would encode
// non-BMP names differently from Dart and the actual Android filesystem.
extern "C" JNIEXPORT jint JNICALL
Java_io_imagehost_imagehost_AndroidPublication_renameExclusive(
    JNIEnv* env, jobject, jbyteArray source, jbyteArray destination) {
  std::vector<char> old_path;
  std::vector<char> new_path;
  if (!path_bytes(env, source, old_path) ||
      !path_bytes(env, destination, new_path)) return EINVAL;

  // Bionic's renameat2 wrapper starts at API 30; use the NDK's architecture-
  // specific syscall number for API 29 too. Unsupported kernels/filesystems
  // fail closed. Never substitute a replacing rename or a copy fallback.
#ifdef SYS_renameat2
  const long result = ::syscall(SYS_renameat2, AT_FDCWD, old_path.data(),
                                AT_FDCWD, new_path.data(), RENAME_NOREPLACE);
  return result == 0 ? 0 : errno;
#else
  return ENOSYS;
#endif
}
