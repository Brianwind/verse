#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

#include <windows.h>

inline constexpr wchar_t kVerseAppUserModelId[] = L"Verse.Player";

// Registers the portable Win32 application with Windows Shell so its explicit
// AppUserModelID can be resolved to the Verse display name.
HRESULT RegisterVerseAppIdentity();

#endif  // RUNNER_APP_IDENTITY_H_
