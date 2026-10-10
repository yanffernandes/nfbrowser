// Entry point shared by the Chromium helper apps (GPU, renderer, network, ...).
// Based on tests/cefsimple/process_helper_mac.cc from the CEF repository.

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

int main(int argc, char* argv[]) {
    // The framework is loaded at runtime instead of linked, as CEF requires on macOS.
    CefScopedLibraryLoader libraryLoader;
    if (!libraryLoader.LoadInHelper()) {
        return 1;
    }

    CefMainArgs mainArgs(argc, argv);
    return CefExecuteProcess(mainArgs, nullptr, nullptr);
}
