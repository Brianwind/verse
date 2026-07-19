#include "app_identity.h"

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>
#include <vector>

namespace {

HRESULT GetExecutablePath(std::wstring* executable_path) {
  if (executable_path == nullptr) return E_POINTER;

  std::vector<wchar_t> buffer(MAX_PATH);
  while (buffer.size() <= 32768) {
    SetLastError(ERROR_SUCCESS);
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return HRESULT_FROM_WIN32(GetLastError());
    if (length < buffer.size()) {
      executable_path->assign(buffer.data(), length);
      return S_OK;
    }
    buffer.resize(buffer.size() * 2);
  }
  return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
}

bool FileExists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

// Keep an existing, valid Verse registration. This prevents a development or
// portable build from redirecting an installed copy's Start Menu shortcut.
HRESULT CheckExistingShortcut(const std::wstring& shortcut_path,
                              bool* should_write) {
  if (should_write == nullptr) return E_POINTER;
  *should_write = true;
  if (!FileExists(shortcut_path)) return S_OK;

  Microsoft::WRL::ComPtr<IShellLinkW> shell_link;
  HRESULT result = CoCreateInstance(CLSID_ShellLink, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&shell_link));
  if (FAILED(result)) return result;

  Microsoft::WRL::ComPtr<IPersistFile> persist_file;
  result = shell_link.As(&persist_file);
  if (FAILED(result)) return result;
  result = persist_file->Load(shortcut_path.c_str(), STGM_READ);
  if (FAILED(result)) return result;

  Microsoft::WRL::ComPtr<IPropertyStore> property_store;
  result = shell_link.As(&property_store);
  if (FAILED(result)) return result;

  PROPVARIANT app_id{};
  result = property_store->GetValue(PKEY_AppUserModel_ID, &app_id);
  if (FAILED(result)) return result;
  const bool belongs_to_verse =
      app_id.vt == VT_LPWSTR && app_id.pwszVal != nullptr &&
      _wcsicmp(app_id.pwszVal, kVerseAppUserModelId) == 0;
  PropVariantClear(&app_id);
  if (!belongs_to_verse) return HRESULT_FROM_WIN32(ERROR_FILE_EXISTS);

  std::vector<wchar_t> target(32768);
  result = shell_link->GetPath(target.data(), static_cast<int>(target.size()),
                               nullptr, SLGP_RAWPATH);
  if (FAILED(result)) return result;
  if (FileExists(target.data())) {
    *should_write = false;
  }
  return S_OK;
}

}  // namespace

HRESULT RegisterVerseAppIdentity() {
  std::wstring executable_path;
  HRESULT result = GetExecutablePath(&executable_path);
  if (FAILED(result)) return result;

  PWSTR programs_path_raw = nullptr;
  result = SHGetKnownFolderPath(
      FOLDERID_Programs, KF_FLAG_CREATE, nullptr, &programs_path_raw);
  if (FAILED(result)) return result;

  std::wstring shortcut_path(programs_path_raw);
  CoTaskMemFree(programs_path_raw);
  if (!shortcut_path.empty() && shortcut_path.back() != L'\\') {
    shortcut_path.push_back(L'\\');
  }
  shortcut_path += L"Verse.lnk";

  bool should_write = true;
  result = CheckExistingShortcut(shortcut_path, &should_write);
  if (FAILED(result) || !should_write) return result;

  Microsoft::WRL::ComPtr<IShellLinkW> shell_link;
  result = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(&shell_link));
  if (FAILED(result)) return result;

  result = shell_link->SetPath(executable_path.c_str());
  if (FAILED(result)) return result;

  const auto separator = executable_path.find_last_of(L"\\/");
  if (separator != std::wstring::npos) {
    result = shell_link->SetWorkingDirectory(
        executable_path.substr(0, separator).c_str());
    if (FAILED(result)) return result;
  }
  result = shell_link->SetDescription(L"Verse music player");
  if (FAILED(result)) return result;
  result = shell_link->SetIconLocation(executable_path.c_str(), 0);
  if (FAILED(result)) return result;

  Microsoft::WRL::ComPtr<IPropertyStore> property_store;
  result = shell_link.As(&property_store);
  if (FAILED(result)) return result;

  PROPVARIANT app_id{};
  result = InitPropVariantFromString(kVerseAppUserModelId, &app_id);
  if (FAILED(result)) return result;
  result = property_store->SetValue(PKEY_AppUserModel_ID, app_id);
  PropVariantClear(&app_id);
  if (FAILED(result)) return result;
  result = property_store->Commit();
  if (FAILED(result)) return result;

  Microsoft::WRL::ComPtr<IPersistFile> persist_file;
  result = shell_link.As(&persist_file);
  if (FAILED(result)) return result;
  result = persist_file->Save(shortcut_path.c_str(), TRUE);
  if (FAILED(result)) return result;

  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, shortcut_path.c_str(), nullptr);
  return S_OK;
}
